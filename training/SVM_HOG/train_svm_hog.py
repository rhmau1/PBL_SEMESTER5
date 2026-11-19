"""Traditional ASL24 training. Colab notebook embeds this exact source.
No TensorFlow, CNN or MediaPipe. Model selection uses validation only.
"""
from __future__ import annotations
import argparse
import hashlib
import html
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import shutil
import time
import warnings
import zipfile

import cv2
import joblib
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageOps
import requests
from skimage.feature import hog
from sklearn.exceptions import ConvergenceWarning
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, f1_score
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import LinearSVC, SVC
from tqdm.auto import tqdm

VERSION = "1.0.0"
LABEL_IDS = np.array([i for i in range(26) if i not in (9, 25)], dtype=np.int64)
LETTERS = [chr(65 + i) for i in LABEL_IDS]
REJECTED = -1
SOURCE_SHA256 = ""
DATASET_URL = "https://www.kaggle.com/api/v1/datasets/download/datamunge/sign-language-mnist"


def default_config(root="/content/drive/MyDrive/LatihIsyarat_SVM_HOG"):
    return {
        "root": str(root), "run_name": "svm_hog_v1", "seed": 42,
        "dataset_zip_path": "", "external_test_dir": "",
        "external_test_role": "development", "auto_download_zip": True,
        "validation_folds": 5,
        "preprocessing": {
            "mode": "full_frame", "max_source_side": 512,
            "margin_per_side": 0.20, "min_foreground_fraction": 0.02,
            "max_foreground_fraction": 0.95, "second_component_ratio": 0.35,
            "minimum_background_difference": 12,
        },
        "hog": {"size": 64, "orientations": 9, "pixels_per_cell": [8, 8],
                "cells_per_block": [2, 2], "block_norm": "L2-Hys",
                "transform_sqrt": True},
        "augmentation": {"enabled": True, "fraction": 0.35,
                         "rotation_degrees": 10, "shift_fraction": 0.05,
                         "scale_min": 0.9, "scale_max": 1.1,
                         "brightness": 10, "contrast_min": 0.9,
                         "contrast_max": 1.1, "noise_std": 2.0},
        "search": {"c_values": [1.0, 10.0, 100.0],
                   "gamma_values": ["scale", 0.001],
                   "augmented_rbf_finalists": 2, "svm_cache_mb": 512,
                   "linear_max_iter": 3000, "linear_tol": 0.001,
                   "train_augmented_linear": False, "include_linear_baseline": False},
        "evidence": {"correct_per_class": 1, "errors_per_class": 2},
    }


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def fingerprint(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def sha_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".part")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False,
                                   allow_nan=False), encoding="utf-8")
    os.replace(temporary, path)


def package_versions():
    names = ["numpy", "pandas", "scikit-learn", "scikit-image", "Pillow",
             "matplotlib", "joblib", "requests", "tqdm"]
    result = {name: importlib.metadata.version(name) for name in names}
    result.update({"opencv": cv2.__version__, "python": platform.python_version()})
    return result


def ensure_dataset(config):
    cache = Path(config["root"]) / "cache" / "dataset"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / "sign-language-mnist.zip"
    source = config.get("dataset_zip_path", "")
    if source:
        source = Path(source)
        if not source.is_file() or not zipfile.is_zipfile(source):
            raise ValueError("dataset_zip_path harus menunjuk ZIP Kaggle yang valid.")
        if source.resolve() != archive.resolve():
            if not archive.exists() or sha_file(source) != sha_file(archive):
                shutil.copy2(source, archive)
    if not archive.exists():
        temporary = archive.with_suffix(".zip.part")
        print("Mengunduh dataset Kaggle ke cache Drive sekali saja...")
        try:
            with requests.get(DATASET_URL, stream=True, timeout=(30, 180)) as response:
                response.raise_for_status()
                total = int(response.headers.get("Content-Length", 0)) or None
                with open(temporary, "wb") as handle, tqdm(total=total, unit="B", unit_scale=True) as bar:
                    for block in response.iter_content(1024 * 1024):
                        if block:
                            handle.write(block)
                            bar.update(len(block))
            if not zipfile.is_zipfile(temporary):
                raise ValueError("Server tidak mengirim ZIP dataset.")
            os.replace(temporary, archive)
        except Exception as error:
            if temporary.exists():
                temporary.unlink()
            raise RuntimeError(
                "Unduhan otomatis gagal. Unduh ZIP Sign Language MNIST dari Kaggle, "
                "upload ke Files Colab, isi DATASET_ZIP_PATH, lalu ulangi persiapan. "
                "Tidak perlu mengirim token Kaggle. Detail: " + str(error)
            ) from error
    archive_hash = sha_file(archive)
    manifest_path = cache / "archive_manifest.json"
    if manifest_path.exists():
        old = json.loads(manifest_path.read_text(encoding="utf-8"))
        if old["sha256"] != archive_hash:
            if not source:
                raise ValueError("Checksum cache dataset berubah. Gunakan ZIP sumber eksplisit untuk menggantinya.")
    files = {}
    with zipfile.ZipFile(archive) as zipped:
        for name in ("sign_mnist_train.csv", "sign_mnist_test.csv"):
            matches = [item for item in zipped.infolist()
                       if Path(item.filename).name == name and not item.is_dir()]
            if not matches:
                raise ValueError("CSV wajib tidak ditemukan dalam ZIP: " + name)
            # Never extract arbitrary ZIP paths. Write only these two known basenames.
            target = cache / name
            if not target.exists() or not manifest_path.exists() or old["sha256"] != archive_hash:
                with zipped.open(matches[0]) as src, open(target.with_suffix(".part"), "wb") as dst:
                    shutil.copyfileobj(src, dst)
                os.replace(target.with_suffix(".part"), target)
            files[name] = target
    csv_hashes = {name: sha_file(p) for name, p in files.items()}
    if manifest_path.exists() and old["sha256"] == archive_hash:
        if old.get("csv_sha256") != csv_hashes:
            raise ValueError("CSV cache berubah/rusak. Hapus dua CSV cache tersebut lalu jalankan ulang.")
    meta = {"dataset": "datamunge/sign-language-mnist", "source_url": DATASET_URL,
            "sha256": archive_hash, "archive_bytes": archive.stat().st_size,
            "csv_sha256": csv_hashes}
    write_json(manifest_path, meta)
    return files, meta


def read_mnist_csv(path):
    frame = pd.read_csv(path)
    expected = ["label"] + ["pixel" + str(i) for i in range(1, 785)]
    if list(frame.columns) != expected or frame.isna().any().any():
        raise ValueError("Format CSV bukan Sign Language MNIST atau terdapat nilai kosong.")
    values = frame.to_numpy(dtype=np.float64)
    if not np.isfinite(values).all() or not np.equal(values, np.floor(values)).all():
        raise ValueError("Label dan piksel harus bilangan bulat hingga.")
    if values[:, 1:].min() < 0 or values[:, 1:].max() > 255:
        raise ValueError("Piksel harus berada pada rentang 0 sampai 255.")
    labels = values[:, 0].astype(np.int64)
    if set(labels) != set(LABEL_IDS):
        raise ValueError("Harus ada 24 kelas A sampai Y tanpa J dan Z.")
    return values[:, 1:].astype(np.uint8).reshape(-1, 28, 28), labels


def image_hashes(images):
    return np.array([hashlib.sha256(im.tobytes()).hexdigest() for im in images])


def make_split(images, labels, test_images, config):
    hashes = image_hashes(images)
    frame = pd.DataFrame({"hash": hashes, "label": labels})
    if frame.groupby("hash")["label"].nunique().max() > 1:
        raise ValueError("Ada gambar identik dengan label bertentangan pada file train.")
    # Hygiene only: exclude exact train/test duplicate pixels, without test labels.
    test_hashes = image_hashes(test_images)
    eligible = np.flatnonzero(~np.isin(hashes, test_hashes))
    groups = hashes[eligible]
    splitter = StratifiedGroupKFold(n_splits=config["validation_folds"],
                                   shuffle=True, random_state=config["seed"])
    train_rel, validation_rel = next(splitter.split(eligible, labels[eligible], groups))
    train, validation = eligible[train_rel], eligible[validation_rel]
    if set(hashes[train]) & set(hashes[validation]):
        raise AssertionError("Gambar identik bocor antara train dan validation.")
    if (set(hashes[train]) | set(hashes[validation])) & set(test_hashes):
        raise AssertionError("Gambar identik bocor ke official test.")
    for subset in (train, validation):
        if set(labels[subset]) != set(LABEL_IDS):
            raise ValueError("Pembagian tidak memuat semua kelas. Periksa dataset/seed.")
    partition = np.full(len(images), "excluded_exact_test_duplicate", dtype=object)
    partition[train] = "train"
    partition[validation] = "validation"
    manifest = pd.DataFrame({"source_row": np.arange(len(images)), "label_id": labels,
                             "letter": [chr(65 + int(i)) for i in labels],
                             "raw_image_sha256": hashes, "partition": partition})
    return train, validation, manifest, test_hashes


def prepare_run(config):
    config = json.loads(json.dumps(config))
    if config["preprocessing"]["mode"] not in ("foreground", "full_frame"):
        raise ValueError("mode harus foreground atau full_frame.")
    if not 0 <= config["augmentation"]["fraction"] <= 1:
        raise ValueError("fraction augmentasi harus antara 0 dan 1.")
    files, dataset = ensure_dataset(config)
    images, labels = read_mnist_csv(files["sign_mnist_train.csv"])
    test_images, test_labels = read_mnist_csv(files["sign_mnist_test.csv"])
    train, validation, split_manifest, test_hashes = make_split(images, labels, test_images, config)
    versions = package_versions()
    training_config = {k: v for k, v in config.items() if k not in
                       ("root", "run_name", "dataset_zip_path", "external_test_dir",
                        "external_test_role", "auto_download_zip", "evidence")}
    signature = fingerprint({"implementation_version": VERSION, "source": SOURCE_SHA256,
                             "config": training_config, "dataset": dataset, "versions": versions})
    name = config["run_name"]
    if not name or Path(name).name != name or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for c in name):
        raise ValueError("run_name hanya boleh huruf, angka, garis bawah, atau tanda hubung.")
    output = Path(config["root"]) / "runs" / (name + "_" + signature[:12])
    output.mkdir(parents=True, exist_ok=True)
    cache = Path(config["root"]) / "cache" / "features"
    cache.mkdir(parents=True, exist_ok=True)
    write_json(output / "config.json", config)
    write_json(output / "environment.json", versions)
    write_json(output / "dataset_manifest.json", dataset)
    split_manifest.to_csv(output / "split_train_validation.csv", index=False)
    pd.DataFrame({"source_row": np.arange(len(test_images)), "raw_image_sha256": test_hashes,
                  "label_id": test_labels, "letter": [chr(65 + int(i)) for i in test_labels]}) .to_csv(output / "official_test_manifest.csv", index=False)
    summary = {"official_train_rows": len(images), "official_test_rows": len(test_images),
               "train_originals": len(train), "validation_originals": len(validation),
               "excluded_exact_test_duplicates": int((split_manifest.partition == "excluded_exact_test_duplicate").sum()),
               "unique_train_images": int(split_manifest.loc[train, "raw_image_sha256"].nunique()),
               "split_grouping": "identical raw pixels only; original capture/signer IDs unavailable"}
    write_json(output / "split_summary.json", summary)
    print(json.dumps(summary, indent=2))
    print("Output permanen:", output)
    print("Test belum dievaluasi. Pembagian ini tidak menjamin signer/session terpisah.")
    return {"config": config, "dataset": dataset, "signature": signature, "output": output,
            "cache": cache, "images": images, "labels": labels, "train": train,
            "validation": validation, "test_images": test_images, "test_labels": test_labels,
            "summary": summary, "versions": versions}


def gray_image(source, max_side=512):
    if isinstance(source, (str, Path)):
        with Image.open(source) as opened:
            image = ImageOps.exif_transpose(opened).convert("L")
    else:
        image = Image.fromarray(np.asarray(source, dtype=np.uint8)).convert("L")
    image.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    return np.asarray(image, dtype=np.uint8)


def preprocess(source, config):
    p = config["preprocessing"]
    gray = gray_image(source, p["max_source_side"])
    h, w = gray.shape
    result = {"accepted": False, "reason": "", "gray": gray, "bbox": None}
    if min(h, w) < 8:
        result["reason"] = "gambar terlalu kecil"
        return result
    band = max(1, round(min(h, w) * 0.05))
    borders = np.concatenate((gray[:band].ravel(), gray[-band:].ravel(),
                              gray[:, :band].ravel(), gray[:, -band:].ravel()))
    background = float(np.median(borders))
    delta = np.abs(gray.astype(np.float32) - background).astype(np.uint8)
    blurred = cv2.GaussianBlur(delta, (3, 3), 0)
    threshold, _ = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    mask = (blurred > max(threshold, p["minimum_background_difference"])).astype(np.uint8) * 255
    # On 28x28, 3x3 morphology can erase finger details. Only use it at >=128px.
    if min(h, w) >= 128:
        kernel = np.ones((3, 3), np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=1)
    result.update({"difference": delta, "mask": mask, "background": background})
    if p["mode"] == "full_frame":
        x, y, box_w, box_h = 0, 0, w, h
    else:
        count, components, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
        candidates = sorted(range(1, count), key=lambda i: stats[i, cv2.CC_STAT_AREA], reverse=True)
        if not candidates:
            result["reason"] = "foreground tidak ditemukan"
            return result
        largest = candidates[0]
        area = int(stats[largest, cv2.CC_STAT_AREA])
        ratio = area / (w * h)
        if not p["min_foreground_fraction"] <= ratio <= p["max_foreground_fraction"]:
            result["reason"] = "luas foreground tidak memenuhi batas"
            return result
        if len(candidates) > 1 and stats[candidates[1], cv2.CC_STAT_AREA] / area > p["second_component_ratio"]:
            result["reason"] = "lebih dari satu foreground besar"
            return result
        x, y, box_w, box_h = map(int, stats[largest, :4])
    margin = p["margin_per_side"] if p["mode"] == "foreground" else 0
    side = max(2, math.ceil(max(box_w, box_h) * (1 + 2 * margin)))
    left = math.floor(x + box_w / 2 - side / 2)
    top = math.floor(y + box_h / 2 - side / 2)
    canvas = Image.new("L", (side, side), round(background))
    canvas.paste(Image.fromarray(gray), (-left, -top))
    normalized = np.asarray(canvas.resize((config["hog"]["size"],) * 2,
                                          Image.Resampling.BILINEAR), dtype=np.uint8)
    result.update({"accepted": True, "reason": "", "bbox": [left, top, side, side],
                   "crop": np.asarray(canvas), "normalized": normalized})
    return result


def hog_features(normalized, config, visualize=False):
    h = config["hog"]
    return hog(normalized.astype(np.float32) / 255.0,
               orientations=h["orientations"], pixels_per_cell=tuple(h["pixels_per_cell"]),
               cells_per_block=tuple(h["cells_per_block"]), block_norm=h["block_norm"],
               transform_sqrt=h["transform_sqrt"], visualize=visualize,
               feature_vector=True, channel_axis=None)


def augment_image(source, config, seed):
    rng = np.random.default_rng(seed)
    a = config["augmentation"]
    gray = gray_image(source, config["preprocessing"]["max_source_side"])
    h, w = gray.shape
    background = float(np.median(np.concatenate((gray[0], gray[-1], gray[:, 0], gray[:, -1]))))
    angle = float(rng.uniform(-a["rotation_degrees"], a["rotation_degrees"]))
    scale = float(rng.uniform(a["scale_min"], a["scale_max"]))
    matrix = cv2.getRotationMatrix2D(((w - 1) / 2, (h - 1) / 2), angle, scale)
    matrix[:, 2] += rng.uniform(-a["shift_fraction"], a["shift_fraction"], size=2) * [w, h]
    warped = cv2.warpAffine(gray, matrix, (w, h), flags=cv2.INTER_LINEAR,
                            borderMode=cv2.BORDER_CONSTANT, borderValue=background)
    contrast = float(rng.uniform(a["contrast_min"], a["contrast_max"]))
    brightness = float(rng.uniform(-a["brightness"], a["brightness"]))
    values = warped.astype(np.float32) * contrast + brightness
    if rng.random() < 0.25:
        values = cv2.GaussianBlur(values, (3, 3), 0)
    if rng.random() < 0.25:
        values += rng.normal(0, a["noise_std"], values.shape)
    return np.clip(np.rint(values), 0, 255).astype(np.uint8)


def feature_set(ctx, part):
    cfg = ctx["config"]
    if part == "test":
        images, labels = ctx["test_images"], ctx["test_labels"]
        rows = np.arange(len(images))
    else:
        images, labels = ctx["images"], ctx["labels"]
        rows = ctx["validation"] if part == "validation" else ctx["train"]
    if part == "augmentation":
        rng = np.random.default_rng(cfg["seed"])
        picked = []
        for label in LABEL_IDS:
            candidates = rows[labels[rows] == label]
            number = int(round(len(candidates) * cfg["augmentation"]["fraction"]))
            if number:
                picked.extend(rng.choice(candidates, size=number, replace=False).tolist())
        rows = np.array(sorted(picked), dtype=np.int64)
    key = fingerprint({"run": ctx["signature"], "part": part,
                       "rows": hashlib.sha256(rows.tobytes()).hexdigest()})
    path = ctx["cache"] / (part + "_" + key + ".npz")
    if path.exists():
        try:
            with np.load(path, allow_pickle=False) as data:
                if str(data["fingerprint"].item()) != key:
                    raise ValueError("cache fingerprint berbeda")
                result = {name: data[name] for name in ("X", "y", "rows", "rejected_rows", "reasons")}
            if len(result["X"]) != len(result["y"]) or not np.isfinite(result["X"]).all():
                raise ValueError("cache fitur tidak valid")
            print("Cache cocok:", part, len(result["X"]), "diterima")
            return result
        except (OSError, ValueError, EOFError, zipfile.BadZipFile) as error:
            print("Cache tidak valid, dihitung ulang:", error)
    features, accepted, rejected, reasons = [], [], [], []
    for row in tqdm(rows, desc="HOG " + part):
        image = images[row]
        if part == "augmentation":
            image = augment_image(image, cfg, seed=int(cfg["seed"]) + int(row) * 1009)
        processed = preprocess(image, cfg)
        if not processed["accepted"]:
            rejected.append(int(row))
            reasons.append(processed["reason"])
            continue
        features.append(hog_features(processed["normalized"], cfg).astype(np.float32))
        accepted.append(int(row))
    dim = len(hog_features(np.zeros((cfg["hog"]["size"],) * 2, dtype=np.uint8), cfg))
    accepted = np.array(accepted, dtype=np.int64)
    result = {"X": np.array(features, dtype=np.float32).reshape(-1, dim),
              "y": labels[accepted], "rows": accepted,
              "rejected_rows": np.array(rejected, dtype=np.int64),
              "reasons": np.array(reasons, dtype="U128")}
    temporary = path.with_suffix(".npz.part")
    with open(temporary, "wb") as handle:
        np.savez_compressed(handle, fingerprint=key, **result)
    os.replace(temporary, path)
    pd.DataFrame({"source_row": rejected, "reason": reasons}).to_csv(
        ctx["output"] / (part + "_preprocessing_rejections.csv"), index=False)
    return result


def build_features(ctx):
    result = {part: feature_set(ctx, part) for part in ("train", "validation")}
    if ctx["config"]["augmentation"]["enabled"]:
        result["augmentation"] = feature_set(ctx, "augmentation")
    for part in ("train", "validation"):
        if set(result[part]["y"]) != set(LABEL_IDS):
            raise ValueError(part + ": ada kelas yang seluruh gambarnya ditolak. Periksa bukti segmentasi dahulu.")
    if "augmentation" in result:
        if set(result["augmentation"]["rows"]) & set(ctx["validation"]):
            raise AssertionError("Augmentasi masuk validation.")
    print("Dimensi HOG:", result["train"]["X"].shape[1])
    write_json(ctx["output"] / "feature_summary.json", {
        part: {"accepted": len(v["y"]), "rejected": len(v["rejected_rows"]),
               "dimensions": v["X"].shape[1]} for part, v in result.items()})
    return result


def prediction_metrics(truth, prediction):
    accepted = prediction != REJECTED
    report = classification_report(truth, prediction, labels=LABEL_IDS,
                                   target_names=LETTERS, output_dict=True, zero_division=0)
    return {"total": len(truth), "correct": int(np.sum(truth == prediction)),
            "wrong": int(np.sum(accepted & (truth != prediction))),
            "rejected": int(np.sum(~accepted)),
            "accuracy_end_to_end": float(accuracy_score(truth, prediction)),
            "macro_f1": float(f1_score(truth, prediction, labels=LABEL_IDS,
                                        average="macro", zero_division=0)),
            "coverage": float(np.mean(accepted)),
            "accuracy_accepted_only": float(np.mean(truth[accepted] == prediction[accepted])) if accepted.any() else None,
            "per_class": report}


def predict_features(model, data, all_truth):
    predicted = np.full(len(all_truth), REJECTED, dtype=np.int64)
    margins = np.full(len(all_truth), np.nan)
    if len(data["rows"]):
        predicted[data["rows"]] = model.predict(data["X"])
        decisions = model.decision_function(data["X"])
        margins[data["rows"]] = np.max(decisions, axis=1) if decisions.ndim == 2 else np.abs(decisions)
    return predicted, margins


def train_candidates(ctx, features):
    cfg, out = ctx["config"], ctx["output"]
    models_dir = ctx["cache"].parent / "models" / ctx["signature"]
    models_dir.mkdir(parents=True, exist_ok=True)
    records = []
    val_rows = ctx["validation"]
    val_truth = ctx["labels"][val_rows]
    # Convert original source row indices to local validation positions for metrics.
    position = {int(row): pos for pos, row in enumerate(val_rows)}
    validation = dict(features["validation"])
    validation["rows"] = np.array([position[int(row)] for row in validation["rows"]])

    def fit_one(kind, c, gamma="scale", augmented=False):
        spec = {"kind": kind, "C": c, "gamma": gamma, "augmented": augmented}
        key = fingerprint({"run": ctx["signature"], "spec": spec})
        model_path = models_dir / (key[:16] + ".joblib")
        record_path = models_dir / (key[:16] + ".json")
        if model_path.exists() and record_path.exists():
            record = json.loads(record_path.read_text(encoding="utf-8"))
            if record.get("fingerprint") == key and record.get("model_sha256") == sha_file(model_path):
                records.append(record)
                print("Checkpoint cocok:", spec, "val F1:", record["validation_macro_f1"])
                return record
        x, y = features["train"]["X"], features["train"]["y"]
        if augmented:
            x = np.concatenate((x, features["augmentation"]["X"]))
            y = np.concatenate((y, features["augmentation"]["y"]))
        classifier = (LinearSVC(C=c, dual=False, tol=cfg["search"].get("linear_tol", 0.001),
                                max_iter=cfg["search"]["linear_max_iter"],
                                random_state=cfg["seed"]) if kind == "linear" else
                      SVC(C=c, gamma=gamma, kernel="rbf", cache_size=cfg["search"]["svm_cache_mb"],
                          probability=False, decision_function_shape="ovr"))
        model = Pipeline([("scaler", StandardScaler()), ("svm", classifier)])
        print("TRAINING:", spec, "|", len(y), "gambar. SVC belum memberi progres tiap epoch.", flush=True)
        started = time.perf_counter()
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always", ConvergenceWarning)
            model.fit(x, y)
        fit_seconds = time.perf_counter() - started
        warning_text = [str(item.message) for item in caught]
        converged = not any(issubclass(item.category, ConvergenceWarning) for item in caught)
        converged = converged and int(getattr(model["svm"], "fit_status_", 0)) == 0
        prediction, _ = predict_features(model, validation, val_truth)
        metrics = prediction_metrics(val_truth, prediction)
        started = time.perf_counter()
        model.predict(features["validation"]["X"][:min(256, len(features["validation"]["y"]))])
        timing_ms = (time.perf_counter() - started) * 1000 / min(256, len(features["validation"]["y"]))
        temporary = model_path.with_suffix(".joblib.part")
        joblib.dump(model, temporary, compress=3)
        os.replace(temporary, model_path)
        record = {"fingerprint": key, **spec, "train_examples": len(y), "converged": converged,
                  "warnings": warning_text, "fit_seconds": fit_seconds,
                  "validation_macro_f1": metrics["macro_f1"],
                  "validation_accuracy": metrics["accuracy_end_to_end"],
                  "validation_rejected": metrics["rejected"],
                  "model_bytes": model_path.stat().st_size, "prediction_ms_per_sample": timing_ms,
                  "support_vectors": int(np.sum(model["svm"].n_support_)) if kind == "rbf" else None,
                  "model_path": str(model_path), "model_sha256": sha_file(model_path)}
        write_json(record_path, record)
        records.append(record)
        pd.DataFrame(records).to_csv(out / "validation_comparison.csv", index=False)
        print("SELESAI: validation accuracy", round(100 * metrics["accuracy_end_to_end"], 3),
              "%, macro-F1", round(100 * metrics["macro_f1"], 3), "%,", round(fit_seconds, 1), "detik")
        return record

    if cfg["search"].get("include_linear_baseline", False):
        fit_one("linear", 1.0)
    baseline_rbf = []
    for c in cfg["search"]["c_values"]:
        for gamma in cfg["search"]["gamma_values"]:
            baseline_rbf.append(fit_one("rbf", c, gamma))
    if cfg["augmentation"]["enabled"] and len(features["augmentation"]["y"]):
        if cfg["search"].get("train_augmented_linear", False):
            fit_one("linear", 1.0, augmented=True)
        finalists = sorted([r for r in baseline_rbf if r["converged"]],
                            key=lambda r: (-r["validation_macro_f1"], -r["validation_accuracy"], r["model_bytes"]))
        for record in finalists[:cfg["search"]["augmented_rbf_finalists"]]:
            fit_one("rbf", record["C"], record["gamma"], augmented=True)
    eligible = [r for r in records if r["converged"]]
    if not eligible:
        raise RuntimeError("Tidak ada model konvergen. Periksa warnings dan pengaturan.")
    winner = sorted(eligible, key=lambda r: (-r["validation_macro_f1"], -r["validation_accuracy"],
                                             r["model_bytes"], r["fingerprint"]))[0]
    shutil.copy2(winner["model_path"], out / "model_svm_hog.joblib")
    write_json(out / "winner_validation.json", winner)
    table = pd.DataFrame(records).sort_values(["validation_macro_f1", "validation_accuracy"], ascending=False)
    table.to_csv(out / "validation_comparison.csv", index=False)
    fig, ax = plt.subplots(figsize=(11, 5))
    names = [str(i) + ": " + r["kind"] + (" +aug" if r["augmented"] else "") for i, r in enumerate(records)]
    ax.barh(names, [100 * r["validation_macro_f1"] for r in records])
    ax.set(xlabel="Validation macro-F1 (%)", title="Pemilihan model hanya berdasarkan validation")
    fig.tight_layout()
    fig.savefig(out / "validation_comparison.png", dpi=160)
    plt.close(fig)
    print("PEMENANG VALIDATION:", {k: winner[k] for k in ("kind", "C", "gamma", "augmented", "model_bytes")})
    return {"record": winner, "model": joblib.load(out / "model_svm_hog.joblib")}


def prediction_frame(truth, predicted, margins, reasons=None, paths=None):
    reasons = reasons or {}
    return pd.DataFrame({
        "source_row": np.arange(len(truth)),
        "path": paths if paths is not None else [""] * len(truth),
        "true_label": [chr(65 + int(i)) for i in truth],
        "predicted_label": [chr(65 + int(i)) if i != REJECTED else "REJECTED" for i in predicted],
        "correct": truth == predicted,
        "status": ["rejected_preprocessing" if p == REJECTED else "correct" if p == t else "wrong"
                   for t, p in zip(truth, predicted)],
        "decision_score_not_probability": margins,
        "preprocessing_reason": [reasons.get(i, "") for i in range(len(truth))],
    })


def save_confusion(out, truth, predicted, prefix):
    matrix = confusion_matrix(truth, predicted, labels=list(LABEL_IDS) + [REJECTED])[:24]
    pd.DataFrame(matrix, index=LETTERS, columns=LETTERS + ["REJECTED"]).to_csv(out / (prefix + "_confusion_matrix.csv"))
    fig, ax = plt.subplots(figsize=(15, 12))
    image = ax.imshow(matrix, cmap="Blues")
    ax.set_xticks(np.arange(25), LETTERS + ["DITOLAK"], rotation=90)
    ax.set_yticks(np.arange(24), LETTERS)
    ax.set(xlabel="Prediksi", ylabel="Label sebenarnya", title=prefix + ": seluruh gambar termasuk penolakan")
    for row in range(24):
        for col in range(25):
            if matrix[row, col]:
                ax.text(col, row, str(matrix[row, col]), ha="center", va="center", fontsize=7,
                        color="white" if matrix[row, col] > matrix.max() / 2 else "black")
    fig.colorbar(image, ax=ax, shrink=0.8)
    fig.tight_layout()
    fig.savefig(out / (prefix + "_confusion_matrix.png"), dpi=150)
    plt.close(fig)


def save_case_evidence(folder, source, processed, title, config):
    folder.mkdir(parents=True, exist_ok=True)
    if isinstance(source, (str, Path)):
        with Image.open(source) as opened:
            original = ImageOps.exif_transpose(opened).convert("RGB")
            original.thumbnail((512, 512))
    else:
        original = Image.fromarray(np.asarray(source)).convert("RGB")
    original.save(folder / "01_original.png")
    stages = [("original", np.asarray(original)), ("grayscale", processed["gray"])]
    for key, name in (("difference", "03_background_difference"), ("mask", "04_segmentation_mask"),
                       ("crop", "06_square_crop"), ("normalized", "07_input_hog")):
        if key in processed:
            Image.fromarray(processed[key]).save(folder / (name + ".png"))
            stages.append((key, processed[key]))
    Image.fromarray(processed["gray"]).save(folder / "02_grayscale.png")
    overlay = Image.fromarray(processed["gray"]).convert("RGB")
    if processed["bbox"] is not None:
        left, top, width, height = processed["bbox"]
        ImageDraw.Draw(overlay).rectangle((left, top, left + width - 1, top + height - 1), outline="red", width=1)
    overlay.save(folder / "05_crop_box.png")
    stages.insert(4 if len(stages) >= 4 else len(stages), ("crop box", np.asarray(overlay)))
    if processed["accepted"]:
        _, visual = hog_features(processed["normalized"], config, visualize=True)
        visual = np.clip(visual / max(float(visual.max()), 1e-9) * 255, 0, 255).astype(np.uint8)
        Image.fromarray(visual).save(folder / "08_hog_visualization.png")
        stages.append(("HOG visualization", visual))
    fig, axes = plt.subplots(2, 4, figsize=(12, 6))
    for ax in axes.flat:
        ax.axis("off")
    for ax, (label, image) in zip(axes.flat, stages):
        ax.imshow(image, cmap="gray", vmin=0, vmax=255)
        ax.set_title(label, fontsize=9)
    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(folder / "steps.png", dpi=120)
    plt.close(fig)
    write_json(folder / "preprocessing.json", {
        "accepted": processed["accepted"], "reason": processed["reason"],
        "bbox": processed["bbox"], "background": processed.get("background"),
        "mask_is_only_for_localization": True,
    })


def sample_evidence(ctx, images, truth, predicted, margins, prefix, paths=None):
    cfg = ctx["config"]
    entries = []
    for label in LABEL_IDS:
        rows = np.flatnonzero(truth == label)
        correct = rows[predicted[rows] == truth[rows]][:cfg["evidence"]["correct_per_class"]]
        errors = rows[predicted[rows] != truth[rows]]
        # High decision score mistakes first; rejected cases follow. Scores are NOT probabilities.
        errors = sorted(errors, key=lambda r: -float(margins[r]) if np.isfinite(margins[r]) else float("inf"))
        chosen = list(correct) + list(errors[:cfg["evidence"]["errors_per_class"]])
        for row in chosen:
            source = images[row] if paths is None else paths[row]
            processed = preprocess(source, cfg)
            guess = chr(65 + int(predicted[row])) if predicted[row] != REJECTED else "DITOLAK"
            status = "BENAR" if predicted[row] == truth[row] else "SALAH" if predicted[row] != REJECTED else "DITOLAK"
            relative = Path("evidence") / prefix / (chr(65 + int(label)) + "_" + str(row).zfill(5))
            title = "Asli " + chr(65 + int(label)) + " | Prediksi " + guess + " | " + status
            save_case_evidence(ctx["output"] / relative, source, processed, title, cfg)
            entries.append({"row": int(row), "true_label": chr(65 + int(label)), "prediction": guess,
                            "status": status, "reason": processed["reason"],
                            "image": (relative / "steps.png").as_posix()})
    write_json(ctx["output"] / (prefix + "_evidence_index.json"), entries)
    return entries


def evaluate_final(ctx, winner):
    out = ctx["output"]
    key = fingerprint({"run": ctx["signature"], "winner": winner["record"]["model_sha256"]})
    cached = out / "official_test_evaluation.json"
    if cached.exists():
        old = json.loads(cached.read_text(encoding="utf-8"))
        if old.get("evaluation_fingerprint") != key:
            raise RuntimeError("Model berubah setelah test dievaluasi dalam run ini. Jangan memilih ulang berdasarkan test.")
        print("Evaluasi final yang sama sudah tersimpan, memakai laporan sebelumnya.")
        return old
    print("Pilihan model sudah dikunci. Baru sekarang official test dievaluasi.")
    data = feature_set(ctx, "test")
    predicted, margins = predict_features(winner["model"], data, ctx["test_labels"])
    metrics = prediction_metrics(ctx["test_labels"], predicted)
    reasons = dict(zip(map(int, data["rejected_rows"]), map(str, data["reasons"])))
    prediction_frame(ctx["test_labels"], predicted, margins, reasons).to_csv(out / "official_test_predictions.csv", index=False)
    per_class = pd.DataFrame([{"letter": letter, **metrics["per_class"][letter]} for letter in LETTERS])
    per_class.to_csv(out / "official_test_per_class.csv", index=False)
    save_confusion(out, ctx["test_labels"], predicted, "official_test")
    evidence = sample_evidence(ctx, ctx["test_images"], ctx["test_labels"], predicted, margins, "official_test")
    result = {"evaluation_fingerprint": key, "metrics": metrics, "evidence": evidence,
              "model_selection_used_test": False,
              "rejections_count_as_errors_in_end_to_end_accuracy": True,
              "note": "No SVM confidence threshold: decision scores are not calibrated probabilities."}
    write_json(cached, result)
    print("TEST FINAL:", {k: metrics[k] for k in ("total", "correct", "wrong", "rejected", "accuracy_end_to_end", "macro_f1")})
    return result


def evaluate_external(ctx, winner):
    directory = ctx["config"].get("external_test_dir", "")
    if not directory:
        print("Foto eksternal tidak diisi. Jangan menganggap akurasi MNIST sebagai akurasi kamera.")
        return None
    directory = Path(directory)
    if not directory.is_dir():
        raise ValueError("Folder external_test_dir tidak ditemukan: " + str(directory))
    paths, truth, skipped = [], [], []
    allowed = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
    for file in sorted(directory.rglob("*")):
        if not file.is_file() or file.suffix.lower() not in allowed:
            continue
        parts = file.relative_to(directory).parts
        letter = parts[0].upper() if len(parts) >= 2 else ""
        if letter not in LETTERS:
            skipped.append({"path": str(file), "reason": "wajib berada dalam folder label A sampai Y tanpa J/Z"})
            continue
        paths.append(str(file))
        truth.append(ord(letter) - 65)
    pd.DataFrame(skipped, columns=["path", "reason"]).to_csv(ctx["output"] / "external_skipped_files.csv", index=False)
    if not paths:
        raise ValueError("Tidak ada foto eksternal berlabel yang valid. Gunakan folder A, B, C, dan seterusnya.")
    truth = np.array(truth, dtype=np.int64)
    predicted = np.full(len(paths), REJECTED, dtype=np.int64)
    margins = np.full(len(paths), np.nan)
    reasons, timings = {}, []
    for row, file in enumerate(tqdm(paths, desc="Foto eksternal, hanya evaluasi")):
        started = time.perf_counter()
        try:
            processed = preprocess(file, ctx["config"])
            if not processed["accepted"]:
                reasons[row] = processed["reason"]
            else:
                feature = hog_features(processed["normalized"], ctx["config"]).reshape(1, -1)
                predicted[row] = int(winner["model"].predict(feature)[0])
                margins[row] = float(np.max(winner["model"].decision_function(feature)))
        except (OSError, ValueError, cv2.error) as error:
            reasons[row] = str(error)
        timings.append((time.perf_counter() - started) * 1000)
    metrics = prediction_metrics(truth, predicted)
    prediction_frame(truth, predicted, margins, reasons, paths).to_csv(ctx["output"] / "external_predictions.csv", index=False)
    save_confusion(ctx["output"], truth, predicted, "external")
    # Broken images have no useful visualization; their exact errors remain in predictions.csv.
    visual_paths, visual_truth, visual_predicted, visual_margins = [], [], [], []
    for i, file in enumerate(paths):
        try:
            gray_image(file)
        except (OSError, ValueError):
            continue
        visual_paths.append(file)
        visual_truth.append(truth[i])
        visual_predicted.append(predicted[i])
        visual_margins.append(margins[i])
    evidence = sample_evidence(ctx, None, np.array(visual_truth), np.array(visual_predicted),
                               np.array(visual_margins), "external", visual_paths)
    result = {"role": ctx["config"]["external_test_role"], "independence_verified": False,
              "metrics": metrics, "evidence": evidence,
              "median_end_to_end_ms_on_this_runtime": float(np.median(timings)),
              "p95_end_to_end_ms_on_this_runtime": float(np.percentile(timings, 95)),
              "used_for_training_or_selection": False,
              "note": "Photos used in previous debugging are development/regression data, not an independent final test."}
    write_json(ctx["output"] / "external_evaluation.json", result)
    return result


def export_run(ctx, winner, evaluation, source_text, external=None):
    out, cfg = ctx["output"], ctx["config"]
    model_file = out / "model_svm_hog.joblib"
    loaded = joblib.load(model_file)
    probe = feature_set(ctx, "validation")["X"][:128]
    agreement = bool(np.array_equal(loaded.predict(probe), winner["model"].predict(probe)))
    if not agreement:
        raise AssertionError("Prediksi berubah setelah penyimpanan joblib.")
    labels = {"label_ids": LABEL_IDS.tolist(), "letters": LETTERS,
              "classifier_classes": loaded["svm"].classes_.tolist()}
    write_json(out / "labels.json", labels)
    write_json(out / "preprocessing_config.json", {"preprocessing": cfg["preprocessing"], "hog": cfg["hog"],
                                                  "pixel_range_before_hog": [0, 255],
                                                  "hog_internal_input_range": [0, 1],
                                                  "scaler": "StandardScaler fitted inside exported pipeline on training only"})
    metadata = {"implementation_version": VERSION, "model_sha256": sha_file(model_file),
                "model_bytes": model_file.stat().st_size, "model_mib": model_file.stat().st_size / 1024**2,
                "method": winner["record"]["kind"] + " SVM + HOG + StandardScaler",
                "validation_winner": winner["record"], "joblib_prediction_parity": agreement,
                "calibrated_probabilities": False, "inference_ready_for_flutter": False,
                "supported_letters": LETTERS, "supports_J_Z": False}
    write_json(out / "model_metadata.json", metadata)
    (out / "train_svm_hog.py").write_text(source_text, encoding="utf-8")
    freeze = []
    for name in ("numpy", "pandas", "scikit-learn", "scikit-image", "Pillow", "matplotlib", "joblib", "requests", "tqdm"):
        freeze.append(name + "==" + ctx["versions"][name])
    freeze.append("opencv-python-headless==" + cv2.__version__.split("-", 1)[0])
    # OpenCV import version may omit the wheel suffix: record the exact installed distribution.
    for distribution in ("opencv-python-headless", "opencv-python"):
        try:
            freeze[-1] = distribution + "==" + importlib.metadata.version(distribution)
            break
        except importlib.metadata.PackageNotFoundError:
            continue
    (out / "requirements_resolved.txt").write_text("\n".join(freeze) + "\n", encoding="utf-8")
    metrics = evaluation["metrics"]
    card = (
        "# Hasil training HOG + SVM\n\n"
        + "Dataset: Sign Language MNIST, 24 huruf statis tanpa J dan Z.\n"
        + "Model dipilih berdasarkan macro-F1 validation, kemudian accuracy, lalu ukuran terkecil.\n"
        + "Official test tidak dipakai mencari konfigurasi. Model tidak di-refit pada validation setelah pemilihan.\n\n"
        + "Official test: " + str(metrics["total"]) + " gambar.\n"
        + "Benar: " + str(metrics["correct"]) + ", salah klasifikasi: " + str(metrics["wrong"]) + ", ditolak preprocessing: " + str(metrics["rejected"]) + ".\n"
        + "Accuracy seluruh input: " + format(metrics["accuracy_end_to_end"] * 100, ".4f") + "%.\n"
        + "Macro-F1: " + format(metrics["macro_f1"] * 100, ".4f") + "%.\n"
        + "Ukuran joblib: " + str(metadata["model_bytes"]) + " byte.\n\n"
        + "## Batasan\n\n"
        + "Segmentasi foreground bukan pendeteksi tangan semantik. Latar polos kontras, satu objek/tangan, dan cahaya cukup adalah ruang lingkup awal.\n"
        + "Input HOG adalah crop grayscale, bukan mask biner. Memperbesar MNIST 28x28 ke 64x64 tidak menambah detail asli.\n"
        + "Pembagian mengelompokkan gambar identik. Identitas signer/foto asal MNIST tidak tersedia sehingga kemiripan sumber belum bisa dihapus sepenuhnya.\n"
        + "Skor keputusan SVM bukan persen confidence. Belum ada kalibrasi atau ambang penerimaan untuk aplikasi.\n"
        + "Akurasi dataset tidak menjamin akurasi kamera. J/Z membutuhkan pendekatan gerakan terpisah.\n"
        + "Model .joblib tidak bisa langsung dimuat oleh TFLite Flutter. Integrasi serta format inferensi dilakukan pada tahap berikutnya.\n"
        + "Tidak ada training accuracy per epoch: SVM bukan training neural network.\n\n"
        + "## Bukti\n\n"
        + "Seluruh prediksi: official_test_predictions.csv. Per huruf: official_test_per_class.csv.\n"
        + "Confusion matrix mencakup kolom REJECTED. Evidence berisi sampel benar dan salah, bukan gambar seluruh test set.\n"
        + "Cache dataset dan fitur disimpan terpisah di root/cache, tidak diduplikasi ke ZIP hasil.\n"
    )
    (out / "LAPORAN_HASIL.md").write_text(card, encoding="utf-8")
    rows = "".join("<tr><td>" + html.escape(str(k)) + "</td><td>" + html.escape(str(v)) + "</td></tr>"
                   for k, v in metrics.items() if k != "per_class")
    images = "".join('<article><h3>' + html.escape(e["true_label"] + " menjadi " + e["prediction"] + ": " + e["status"])
                     + '</h3><img loading="lazy" src="' + html.escape(e["image"], quote=True)
                     + '"><p>' + html.escape(e["reason"]) + '</p></article>' for e in evaluation["evidence"])
    body = ('<!doctype html><html lang="id"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
            + '<title>Laporan HOG SVM</title><style>body{font:16px system-ui;max-width:1100px;margin:24px auto;padding:16px;line-height:1.6}'
            + 'img{max-width:100%}table{border-collapse:collapse}td{border:1px solid #aaa;padding:6px}article{margin:32px 0}</style>'
            + '<h1>Hasil training HOG + SVM</h1><p>Angka berikut dihitung dari hasil run ini. Penolakan preprocessing masuk sebagai kesalahan pada accuracy seluruh input.</p>'
            + '<table>' + rows + '</table><p>Ukuran model: ' + str(metadata["model_bytes"]) + ' byte.</p>'
            + '<p>Skor SVM bukan probabilitas. Hasil ini belum membuktikan akurasi kamera atau kesiapan integrasi Flutter.</p>'
            + '<h2>Confusion matrix</h2><img src="official_test_confusion_matrix.png">'
            + '<h2>Perbandingan validation</h2><img src="validation_comparison.png">'
            + '<h2>Bukti sampel per tahap</h2><p>Daftar seluruh prediksi tersedia di official_test_predictions.csv. Bukti gambar berikut hanya sampel.</p>'
            + images + '</html>')
    (out / "LAPORAN_HASIL.html").write_text(body, encoding="utf-8")
    hashes = [{"path": p.relative_to(out).as_posix(), "bytes": p.stat().st_size, "sha256": sha_file(p)}
              for p in sorted(out.rglob("*")) if p.is_file() and p.name != "artifact_manifest.json"]
    write_json(out / "artifact_manifest.json", hashes)
    zip_path = out.parent / (out.name + "_LENGKAP.zip")
    temporary = zip_path.with_suffix(".zip.part")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for p in sorted(out.rglob("*")):
            if p.is_file():
                archive.write(p, arcname=out.name + "/" + p.relative_to(out).as_posix())
    os.replace(temporary, zip_path)
    with zipfile.ZipFile(zip_path) as archive:
        if archive.testzip() is not None:
            raise AssertionError("ZIP hasil gagal pemeriksaan CRC.")
    print("MODEL:", model_file)
    print("ACCURACY SEMUA INPUT:", format(100 * metrics["accuracy_end_to_end"], ".4f"), "%")
    print("UKURAN:", metadata["model_bytes"], "byte")
    print("LAPORAN HTML:", out / "LAPORAN_HASIL.html")
    print("ZIP LENGKAP:", zip_path)
    return str(zip_path)


def run_training(config, source_text):
    ctx = prepare_run(config)
    features = build_features(ctx)
    winner = train_candidates(ctx, features)
    evaluation = evaluate_final(ctx, winner)
    external = evaluate_external(ctx, winner)
    return export_run(ctx, winner, evaluation, source_text, external)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Training tradisional ASL24 HOG + SVM")
    parser.add_argument("--config", required=True)
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    source_text = Path(__file__).read_text(encoding="utf-8")
    SOURCE_SHA256 = hashlib.sha256(source_text.encode("utf-8")).hexdigest()
    run_training(config, source_text)
