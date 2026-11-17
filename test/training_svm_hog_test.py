"""Small synthetic validation only. These are not ASL accuracy results."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "training" / "SVM_HOG" / "train_svm_hog.py"
NOTEBOOK = SOURCE.with_name("TRAINING_SVM_HOG_COLAB.ipynb")
spec = importlib.util.spec_from_file_location("svm_hog_under_test", SOURCE)
trainer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trainer)
trainer.tqdm = lambda values, **kwargs: values


def synthetic_images(per_class):
    images, labels = [], []
    for label in trainer.LABEL_IDS:
        for sample in range(per_class):
            # Connected geometric glyphs, NOT real sign-language photographs.
            image = trainer.np.full((28, 28), 225 - sample, dtype=trainer.np.uint8)
            image[4:25, 12:15] = 25
            for bit in range(5):
                y = 5 + bit * 4
                if (int(label) + 1) & (1 << bit):
                    image[y:y + 2, 5:15] = 25
                else:
                    image[y:y + 2, 12:23] = 25
            image[1, 1] = 100 + sample
            images.append(image)
            labels.append(int(label))
    return trainer.np.array(images), trainer.np.array(labels)


class TrainingTests(unittest.TestCase):
    def test_notebook_contains_exact_source_and_compiles(self):
        notebook = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
        embedded = None
        for cell in notebook["cells"]:
            if cell["cell_type"] != "code":
                continue
            text = "".join(cell["source"])
            if text.startswith("%pip"):
                continue
            tree = ast.parse(text)
            for item in tree.body:
                if isinstance(item, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "TRAINING_SOURCE" for t in item.targets):
                    embedded = ast.literal_eval(item.value)
            compile(text, "notebook_cell", "exec")
        self.assertEqual(embedded.lstrip("\n"), SOURCE.read_text(encoding="utf-8"))
        compile(embedded, "embedded_training", "exec")
        self.assertNotIn("import tensorflow", embedded)
        self.assertNotIn("import mediapipe", embedded)

    def test_segmentation_and_hog_contract(self):
        cfg = trainer.default_config()
        gray = trainer.np.full((160, 120), 240, dtype=trainer.np.uint8)
        gray[30:130, 40:75] = 30
        result = trainer.preprocess(gray, cfg)
        self.assertTrue(result["accepted"])
        self.assertEqual(result["normalized"].shape, (64, 64))
        self.assertEqual(result["crop"].shape[0], result["crop"].shape[1])
        features = trainer.hog_features(result["normalized"], cfg)
        self.assertEqual(features.shape, (1764,))
        self.assertTrue(trainer.np.isfinite(features).all())
        self.assertFalse(trainer.preprocess(trainer.np.full((128, 128), 240, dtype=trainer.np.uint8), cfg)["accepted"])
        two = trainer.np.full((160, 160), 240, dtype=trainer.np.uint8)
        two[30:130, 15:45] = 20
        two[30:130, 110:140] = 20
        self.assertFalse(trainer.preprocess(two, cfg)["accepted"])

    def test_augmentation_is_reproducible_and_bounded(self):
        images, _ = synthetic_images(1)
        cfg = trainer.default_config()
        a = trainer.augment_image(images[0], cfg, 42)
        b = trainer.augment_image(images[0], cfg, 42)
        self.assertTrue(trainer.np.array_equal(a, b))
        self.assertEqual(a.shape, images[0].shape)
        self.assertEqual(a.dtype, trainer.np.uint8)

    def test_rejections_are_errors_in_overall_accuracy(self):
        truth = trainer.LABEL_IDS.copy()
        predictions = truth.copy()
        predictions[0] = trainer.REJECTED
        metrics = trainer.prediction_metrics(truth, predictions)
        self.assertEqual(metrics["rejected"], 1)
        self.assertEqual(metrics["correct"], 23)
        self.assertAlmostEqual(metrics["accuracy_end_to_end"], 23 / 24)
        self.assertEqual(metrics["accuracy_accepted_only"], 1.0)

    def test_duplicate_groups_do_not_leak(self):
        images, labels = synthetic_images(7)
        images = trainer.np.concatenate((images, images[:1]))
        labels = trainer.np.concatenate((labels, labels[:1]))
        test_images, _ = synthetic_images(1)
        cfg = trainer.default_config()
        train, validation, manifest, _ = trainer.make_split(images, labels, test_images, cfg)
        self.assertFalse(set(trainer.image_hashes(images[train])) & set(trainer.image_hashes(images[validation])))
        self.assertFalse(set(trainer.image_hashes(images[train])) & set(trainer.image_hashes(test_images)))
        self.assertEqual(manifest.loc[0, "partition"], manifest.loc[len(images) - 1, "partition"])

    def test_tiny_offline_training_export_and_cache(self):
        # All outputs stay in OS temporary storage, not in the repository.
        with tempfile.TemporaryDirectory(prefix="svm_hog_synthetic_") as temporary:
            base = Path(temporary)
            train_images, train_labels = synthetic_images(7)
            test_images, test_labels = synthetic_images(1)
            test_images = test_images.copy()
            test_images[:, 0, 0] = 10
            archive = base / "synthetic_fixture.zip"
            with zipfile.ZipFile(archive, "w") as zipped:
                for name, images, labels in (("sign_mnist_train.csv", train_images, train_labels),
                                              ("sign_mnist_test.csv", test_images, test_labels)):
                    values = trainer.np.column_stack((labels, images.reshape(len(images), -1)))
                    frame = trainer.pd.DataFrame(values, columns=["label"] + ["pixel" + str(i) for i in range(1, 785)])
                    zipped.writestr(name, frame.to_csv(index=False))
            cfg = trainer.default_config(str(base / "outputs"))
            cfg["dataset_zip_path"] = str(archive)
            cfg["run_name"] = "synthetic_smoke_only"
            cfg["preprocessing"]["mode"] = "full_frame"
            cfg["search"].update(c_values=[1.0], gamma_values=["scale"], augmented_rbf_finalists=1)
            cfg["augmentation"]["fraction"] = 0.2
            cfg["evidence"] = {"correct_per_class": 0, "errors_per_class": 0}
            trainer.SOURCE_SHA256 = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
            ctx = trainer.prepare_run(cfg)
            features = trainer.build_features(ctx)
            self.assertFalse(set(features["augmentation"]["rows"]) & set(ctx["validation"]))
            winner = trainer.train_candidates(ctx, features)
            self.assertEqual(int(winner["model"]["scaler"].n_samples_seen_), winner["record"]["train_examples"])
            evaluation = trainer.evaluate_final(ctx, winner)
            self.assertEqual(evaluation["metrics"]["total"], len(test_images))
            # Validation evidence must also be a real, renderable set of steps.
            processed = trainer.preprocess(test_images[0], cfg)
            trainer.save_case_evidence(ctx["output"] / "evidence" / "synthetic_step", test_images[0], processed, "SYNTHETIC ONLY", cfg)
            export = trainer.export_run(ctx, winner, evaluation, SOURCE.read_text(encoding="utf-8"))
            with zipfile.ZipFile(export) as zipped:
                self.assertIsNone(zipped.testzip())
                self.assertEqual(sum(name.endswith(".joblib") for name in zipped.namelist()), 1)
                self.assertTrue(any(name.endswith("LAPORAN_HASIL.html") for name in zipped.namelist()))
            self.assertTrue((ctx["output"] / "evidence/synthetic_step/08_hog_visualization.png").is_file())
            previous_model = trainer.sha_file(ctx["output"] / "model_svm_hog.joblib")
            reused = trainer.train_candidates(ctx, trainer.build_features(ctx))
            self.assertEqual(trainer.sha_file(ctx["output"] / "model_svm_hog.joblib"), previous_model)
            self.assertEqual(trainer.evaluate_final(ctx, reused), evaluation)
            for item in json.loads((ctx["output"] / "artifact_manifest.json").read_text(encoding="utf-8")):
                self.assertEqual(trainer.sha_file(ctx["output"] / item["path"]), item["sha256"])


if __name__ == "__main__":
    unittest.main()
