"""Evaluate the existing 24-letter model with camera-like MediaPipe crops.

This module is called by train_all.py in Google Colab. It never edits the app.
By default, it preserves the current model weights and performs diagnostics.
An accuracy target is a reported experiment outcome, not a stopping guarantee.
"""

from __future__ import annotations

import hashlib
import importlib.metadata
import io
import json
import math
import shutil
from collections import Counter
from pathlib import Path

import numpy as np

from training_common import (
    cached_npz,
    classification_report_artifacts,
    json_write,
    record_environment,
    sha256_file,
    stable_hash,
    write_csv,
)


LABELS = list("ABCDEFGHIKLMNOPQRSTUVWXY")
HF_DATASET = "Marxulia/asl_sign_languages_alphabets_v03"
PREPROCESS_VERSION = "static_mediapipe_square_v2"
FUSION_VERSION = "app_context090_blend055_045_disagree059_v1"


def _implementation_identity():
    versions = {}
    for name in ("mediapipe", "opencv-contrib-python", "opencv-contrib-python-headless",
                 "opencv-python", "opencv-python-headless", "Pillow", "numpy"):
        try:
            versions[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            versions[name] = None
    return {"static_training_sha256": sha256_file(Path(__file__)), "dependencies": versions}


def _download(url, destination):
    """Reuse persistent downloads, and do not leave a partial file as valid."""
    import requests

    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and destination.stat().st_size:
        return destination
    partial = destination.with_suffix(destination.suffix + ".part")
    with requests.get(url, stream=True, timeout=(30, 180)) as response:
        response.raise_for_status()
        with partial.open("wb") as stream:
            for chunk in response.iter_content(1024 * 1024):
                if chunk:
                    stream.write(chunk)
    if not partial.stat().st_size:
        raise RuntimeError(f"Download kosong: {url}")
    partial.replace(destination)
    return destination


def _read_mnist(data_dir):
    import pandas as pd

    base = Path(data_dir) / "sign_mnist"
    base.mkdir(parents=True, exist_ok=True)
    found = {}
    for kind in ("train", "test"):
        options = list(base.rglob(f"sign_mnist_{kind}.csv"))
        if options:
            found[kind] = options[0]
    if len(found) != 2:
        try:
            import kagglehub

            source = Path(kagglehub.dataset_download("datamunge/sign-language-mnist"))
            for kind in ("train", "test"):
                matches = list(source.rglob(f"sign_mnist_{kind}.csv"))
                if not matches:
                    raise FileNotFoundError(f"CSV {kind} tidak ditemukan di Kaggle")
                target = base / f"sign_mnist_{kind}.csv"
                shutil.copy2(matches[0], target)
                found[kind] = target
        except Exception as exc:
            import zipfile

            print(f"Kagglehub MNIST tidak tersedia ({type(exc).__name__}). Mencoba ZIP Kaggle publik.", flush=True)
            try:
                archive_path = _download(
                    "https://www.kaggle.com/api/v1/datasets/download/datamunge/sign-language-mnist",
                    base / "sign-language-mnist.zip")
                with zipfile.ZipFile(archive_path) as archive:
                    for kind in ("train", "test"):
                        basename = f"sign_mnist_{kind}.csv"
                        candidates = [name for name in archive.namelist() if Path(name).name == basename]
                        if not candidates:
                            raise FileNotFoundError(f"ZIP Kaggle tidak mengandung {basename}")
                        target = base / basename
                        # Copy only explicitly named CSVs. Never extract arbitrary
                        # archive paths into the filesystem.
                        with archive.open(candidates[0]) as source, target.open("wb") as destination:
                            shutil.copyfileobj(source, destination)
                        found[kind] = target
            except Exception as download_exc:
                raise RuntimeError(
                    "Dataset MNIST gagal diunduh. Unggah sign_mnist_train.csv dan "
                    f"sign_mnist_test.csv ke {base}, lalu jalankan ulang."
                ) from download_exc
    result = {}
    manifest = []
    lookup = {ord(letter) - ord("A"): index for index, letter in enumerate(LABELS)}
    for kind, source in found.items():
        frame = pd.read_csv(source)
        if "label" not in frame or len(frame.columns) != 785:
            raise ValueError(f"Kontrak Sign Language MNIST tidak sesuai: {source}")
        raw_labels = frame["label"].to_numpy(dtype=np.int32)
        if not set(np.unique(raw_labels)).issubset(lookup):
            raise ValueError("MNIST memiliki label di luar 24 huruf yang didukung")
        pixels = frame.drop(columns="label").to_numpy()
        if not np.isfinite(pixels).all() or pixels.min() < 0 or pixels.max() > 255:
            raise ValueError("Piksel MNIST harus berada di 0..255")
        images = pixels.astype(np.uint8).reshape(-1, 28, 28, 1)
        labels = np.array([lookup[int(value)] for value in raw_labels], dtype=np.int64)
        result[kind] = (images, labels)
        manifest.append({"split": kind, "path": str(source), "rows": len(frame),
                         "sha256": sha256_file(source)})
    return result, manifest


def _image_digest(image):
    array = np.asarray(image.convert("RGB"), dtype=np.uint8)
    return hashlib.sha256(str(array.shape).encode() + array.tobytes()).hexdigest()


def _fetch_real_records(data_dir, dataset=HF_DATASET):
    """Download parquet once, extract upright photos, dedupe identical pixels.

    No signer/session metadata is asserted. Content hash protects exact
    duplicates only, not different photos of the same person or session.
    """
    import pyarrow.parquet as pq
    import requests
    from PIL import Image, ImageOps

    base = Path(data_dir) / "hf_real_photos"
    base.mkdir(parents=True, exist_ok=True)
    info_response = requests.get(f"https://huggingface.co/api/datasets/{dataset}", timeout=60)
    info_response.raise_for_status()
    source_info = info_response.json()
    response = requests.get("https://datasets-server.huggingface.co/parquet",
                            params={"dataset": dataset}, timeout=120)
    response.raise_for_status()
    parquet_files = response.json().get("parquet_files", [])
    if not parquet_files:
        raise RuntimeError(f"Hugging Face tidak menyediakan parquet untuk {dataset}")
    configs = sorted({item.get("config", "default") for item in parquet_files})
    config = "default" if "default" in configs else configs[0]
    chosen = [item for item in parquet_files if item.get("config", "default") == config]
    records, duplicates, files = [], [], []
    by_digest = {}
    for file_index, item in enumerate(chosen):
        url = item["url"]
        target = base / "parquet" / f"{stable_hash(url)[:16]}.parquet"
        _download(url, target)
        files.append({"url": url, "path": str(target), "sha256": sha256_file(target),
                      "source_split": item.get("split", "unknown")})
        parquet = pq.ParquetFile(target)
        schema_metadata = parquet.schema_arrow.metadata or {}
        features = json.loads(schema_metadata.get(b"huggingface", b"{}")).get("info", {}).get("features", {})
        label_field = next((key for key in ("label", "labels", "class") if key in parquet.schema_arrow.names), None)
        image_field = next((key for key in ("image", "img", "photo") if key in parquet.schema_arrow.names), None)
        if not image_field or not label_field:
            raise ValueError(f"Kolom image/label tidak ditemukan di {target}")
        names = features.get(label_field, {}).get("names")
        if not names:
            # Resolve declared names through the dataset server, never assume
            # that numeric labels have the same order as our 24 outputs.
            details = requests.get("https://datasets-server.huggingface.co/info",
                                   params={"dataset": dataset, "config": config}, timeout=60)
            details.raise_for_status()
            dataset_info = details.json().get("dataset_info", {})
            names = dataset_info.get("features", {}).get(label_field, {}).get("names")
        row_index = 0
        for batch in parquet.iter_batches(batch_size=128, columns=[image_field, label_field]):
            for row in batch.to_pylist():
                raw_label = row[label_field]
                if isinstance(raw_label, str):
                    letter = raw_label.strip().upper()
                elif names and 0 <= int(raw_label) < len(names):
                    letter = str(names[int(raw_label)]).strip().upper()
                else:
                    raise ValueError("Nama label HF tidak tersedia. Pemetaan numerik tidak boleh ditebak.")
                identity = f"hf_{file_index}_{row_index}"
                row_index += 1
                if letter not in LABELS:
                    continue
                encoded = row[image_field]
                encoded = encoded.get("bytes") if isinstance(encoded, dict) else encoded
                if not isinstance(encoded, (bytes, bytearray)):
                    raise ValueError(f"Foto parquet {identity} tidak menyertakan bytes")
                try:
                    with Image.open(io.BytesIO(encoded)) as raw_image:
                        image = ImageOps.exif_transpose(raw_image).convert("RGB")
                        digest = _image_digest(image)
                        image.load()
                except Exception as exc:
                    raise ValueError(f"Foto HF tidak dapat dibaca: {identity}") from exc
                if digest in by_digest:
                    previous = by_digest[digest]
                    if previous["label"] != letter:
                        raise ValueError(f"Foto identik memiliki label bertentangan: {identity}")
                    duplicates.append({"duplicate_id": identity, "retained_id": previous["id"], "sha256": digest})
                    continue
                path = base / "images" / f"{digest}.png"
                path.parent.mkdir(parents=True, exist_ok=True)
                if not path.exists():
                    image.save(path)
                record = {"id": identity, "label": letter, "label_index": LABELS.index(letter),
                          "group_id": digest, "content_sha256": digest, "image_path": str(path),
                          "source": dataset, "source_split": item.get("split", "unknown")}
                by_digest[digest] = record
                records.append(record)
    if set(record["label"] for record in records) != set(LABELS):
        raise ValueError("Dataset foto tidak mencakup semua 24 huruf statis")
    provenance = {"dataset": dataset, "revision_reported": source_info.get("sha"),
                  "files": files, "exact_duplicates_removed": len(duplicates),
                  "deduplicated_photos": len(records),
                  "split_limit": "No signer/session identity. Exact-content-disjoint, not person-independent."}
    return records, duplicates, provenance


def _dart_round(value):
    return int(math.floor(value + 0.5)) if value >= 0 else int(math.ceil(value - 0.5))


def square_hand_crop(image, points, padding_scale=1.60, minimum_side_fraction=0.28):
    """App square geometry, border padding, no aspect-ratio stretching.

    OpenCV INTER_AREA approximates Dart image.Interpolation.average. Exact
    byte-for-byte Flutter resize equivalence requires a separate device check.
    """
    import cv2

    rgb = np.asarray(image, dtype=np.uint8)
    height, width = rgb.shape[:2]
    points = np.asarray(points, dtype=np.float64)
    if points.shape != (21, 2) or not np.isfinite(points).all():
        raise ValueError("Crop membutuhkan 21 landmark x/y yang valid")
    bounded = np.clip(points, 0, 1)
    left, top = bounded.min(axis=0) * [width, height]
    right, bottom = bounded.max(axis=0) * [width, height]
    minimum_side = np.clip(min(width, height) * minimum_side_fraction, 1, min(width, height))
    side = float(np.clip(max(right - left, bottom - top) * padding_scale,
                         minimum_side, max(width, height)))
    start_x = _dart_round((left + right - side) / 2)
    start_y = _dart_round((top + bottom - side) / 2)
    side_px = max(1, _dart_round(side))
    gray = (rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114)
    border = [gray[0, 0], gray[0, (width - 1) // 2], gray[0, -1],
              gray[(height - 1) // 2, 0], gray[(height - 1) // 2, -1],
              gray[-1, 0], gray[-1, (width - 1) // 2], gray[-1, -1]]
    output = np.full((side_px, side_px), np.median(border), dtype=np.float32)
    x0, y0 = max(0, start_x), max(0, start_y)
    x1, y1 = min(width, start_x + side_px), min(height, start_y + side_px)
    if x1 > x0 and y1 > y0:
        output[y0 - start_y:y1 - start_y, x0 - start_x:x1 - start_x] = gray[y0:y1, x0:x1]
    resized = cv2.resize(output, (28, 28), interpolation=cv2.INTER_AREA)
    return np.clip(np.rint(resized), 0, 255).astype(np.uint8)[..., None]


def _prepare_real_crops(records, cfg, paths, reports):
    signature = {"version": PREPROCESS_VERSION, "implementation": _implementation_identity(),
                 "task_sha256": sha256_file(paths["hand_task"]),
                 "detector_confidence": 0.35, "max_hands": 2, "max_photo_side": 1024,
                 "detector_image": "JPEG quality95 RGB roundtrip; crop uses original resized RGB",
                 "records": [{k: row[k] for k in ("id", "group_id", "label", "split")} for row in records],
                 "crop": {"context": [1.60, 0.28], "tight": [1.40, 0.22]},
                 "rgb_to_gray": [0.299, 0.587, 0.114], "resize": "OpenCV INTER_AREA"}
    key = "static_crops_" + stable_hash(signature)

    def build():
        import mediapipe as mp
        from mediapipe.tasks import python as mp_python
        from mediapipe.tasks.python import vision
        from PIL import Image, ImageOps

        options = vision.HandLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=str(paths["hand_task"])),
            running_mode=vision.RunningMode.IMAGE, num_hands=2,
            min_hand_detection_confidence=0.35, min_hand_presence_confidence=0.35,
            min_tracking_confidence=0.35)
        count = len(records)
        contexts = np.zeros((count, 28, 28, 1), dtype=np.uint8)
        tights = np.zeros_like(contexts)
        valid = np.zeros(count, dtype=bool)
        status = np.full(count, "not_processed", dtype="U160")
        landmarks = np.full((count, 21, 2), np.nan, dtype=np.float32)
        with vision.HandLandmarker.create_from_options(options) as detector:
            for index, row in enumerate(records):
                if index % 500 == 0:
                    print(f"MediaPipe foto {index}/{count}", flush=True)
                try:
                    with Image.open(row["image_path"]) as raw:
                        image = ImageOps.exif_transpose(raw).convert("RGB")
                        if max(image.size) > 1024:
                            ratio = 1024 / max(image.size)
                            image = image.resize((max(1, _dart_round(image.width * ratio)),
                                                  max(1, _dart_round(image.height * ratio))),
                                                 Image.Resampling.BOX)
                        array = np.asarray(image, dtype=np.uint8).copy()
                        encoded = io.BytesIO()
                        image.save(encoded, format="JPEG", quality=95)
                    with Image.open(io.BytesIO(encoded.getvalue())) as detector_image:
                        detection_array = np.asarray(detector_image.convert("RGB"), dtype=np.uint8).copy()
                    result = detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=detection_array))
                except Exception as exc:
                    # Runtime/decoder failures are not silently mislabeled as
                    # a valid no-hand result. Stop so environment issues surface.
                    raise RuntimeError(f"MediaPipe gagal pada {row['id']}") from exc
                if len(result.hand_landmarks) != 1:
                    status[index] = "no_hand" if not result.hand_landmarks else "multiple_hands"
                    continue
                points = np.array([[point.x, point.y] for point in result.hand_landmarks[0]], dtype=np.float32)
                if points.shape != (21, 2) or not np.isfinite(points).all():
                    status[index] = "invalid_landmarks"
                    continue
                landmarks[index] = np.clip(points, 0, 1)
                contexts[index] = square_hand_crop(array, points, 1.60, 0.28)
                tights[index] = square_hand_crop(array, points, 1.40, 0.22)
                valid[index] = True
                status[index] = "detected_one_hand"
        return {"context": contexts, "tight": tights, "valid": valid,
                "status": status, "landmarks": landmarks}

    values = cached_npz(paths["cache"], key, build)
    if len(values["valid"]) != len(records):
        raise RuntimeError("Cache crop memiliki panjang yang tidak sesuai manifest")
    json_write(reports / "crop_cache_signature.json", signature)
    diagnostic = [{**row, "detector_status": str(values["status"][index]),
                   "usable_for_cnn": bool(values["valid"][index])}
                  for index, row in enumerate(records)]
    write_csv(reports / "real_photo_detection_manifest.csv", diagnostic)
    _save_crop_examples(records, values, reports / "preprocessing_examples.png")
    return values


def _save_crop_examples(records, crops, path):
    import matplotlib.pyplot as plt
    from PIL import Image

    selected = []
    for label in LABELS:
        candidates = [i for i, row in enumerate(records) if row["label"] == label and crops["valid"][i]]
        if candidates:
            selected.append(candidates[0])
    if not selected:
        raise RuntimeError("MediaPipe tidak menemukan tangan pada seluruh foto")
    fig, axes = plt.subplots(len(selected), 3, figsize=(8, 2.1 * len(selected)), squeeze=False)
    for row_index, photo_index in enumerate(selected):
        record = records[photo_index]
        with Image.open(record["image_path"]) as image:
            axes[row_index, 0].imshow(image.convert("RGB"))
        axes[row_index, 0].set_title(f"{record['label']} | {record['split']}")
        axes[row_index, 1].imshow(crops["context"][photo_index, ..., 0], cmap="gray", vmin=0, vmax=255)
        axes[row_index, 1].set_title("Context 1.60")
        axes[row_index, 2].imshow(crops["tight"][photo_index, ..., 0], cmap="gray", vmin=0, vmax=255)
        axes[row_index, 2].set_title("Tight 1.40")
        for axis in axes[row_index]:
            axis.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=110, bbox_inches="tight")
    plt.close(fig)


def fuse_app_scores(context_scores, tight_scores):
    """Mirror current Flutter decision logic, before UI confidence acceptance."""
    context = np.asarray(context_scores, dtype=np.float64)
    tight = np.asarray(tight_scores, dtype=np.float64)
    if context.shape != tight.shape or context.ndim != 2 or context.shape[1] != 24:
        raise ValueError("Fusion membutuhkan dua score array [N,24]")
    output = context.copy()
    need_tight = context.max(axis=1) < 0.90
    output[need_tight] = context[need_tight] * 0.55 + tight[need_tight] * 0.45
    disagreement = need_tight & (context.argmax(axis=1) != tight.argmax(axis=1))
    cap_rows = disagreement & (output.max(axis=1) > 0.59)
    uniform = 1 / 24
    scale = (0.59 - uniform) / (output[cap_rows].max(axis=1) - uniform)
    output[cap_rows] = uniform + (output[cap_rows] - uniform) * scale[:, None]
    return output.astype(np.float32)


def _predict(model, images, batch_size=256):
    if len(images) == 0:
        return np.empty((0, len(LABELS)), dtype=np.float32)
    return np.asarray(model.predict(images, batch_size=batch_size, verbose=0), dtype=np.float32)


def _evaluate_photos(model, records, crops, subset, output_dir, cfg):
    import matplotlib.pyplot as plt
    from sklearn.metrics import precision_recall_fscore_support

    output_dir.mkdir(parents=True, exist_ok=True)
    ids = np.array([index for index, row in enumerate(records) if row["split"] == subset], dtype=np.int64)
    if len(ids) == 0:
        raise ValueError(f"Tidak ada foto di split {subset}")
    valid_ids = ids[crops["valid"][ids]]
    context_scores = _predict(model, crops["context"][valid_ids], int(cfg["batch_size"]))
    tight_scores = _predict(model, crops["tight"][valid_ids], int(cfg["batch_size"]))
    fused = fuse_app_scores(context_scores, tight_scores)
    by_id = {int(photo_id): local for local, photo_id in enumerate(valid_ids)}
    predictions, y_true, rows = [], [], []
    for photo_id in ids:
        row = records[int(photo_id)]
        y_true.append(row["label_index"])
        if int(photo_id) in by_id:
            local = by_id[int(photo_id)]
            scores = fused[local]
            raw_pred = int(scores.argmax())
            confidence = float(scores[raw_pred])
            accepted = confidence >= float(cfg.get("min_confidence", 0.60))
            final_pred = raw_pred if accepted else -1
            context_label = LABELS[int(context_scores[local].argmax())]
            tight_label = LABELS[int(tight_scores[local].argmax())]
            score_data = {f"score_{letter}": float(scores[i]) for i, letter in enumerate(LABELS)}
        else:
            raw_pred, final_pred, confidence, accepted = -1, -1, 0.0, False
            context_label = tight_label = ""
            score_data = {f"score_{letter}": "" for letter in LABELS}
        predictions.append(final_pred)
        rows.append({"id": row["id"], "content_sha256": row["content_sha256"],
                     "true_label": row["label"], "detector_status": str(crops["status"][photo_id]),
                     "raw_fused_label": LABELS[raw_pred] if raw_pred >= 0 else "REJECT",
                     "final_label": LABELS[final_pred] if final_pred >= 0 else "REJECT",
                     "confidence": confidence, "accepted": accepted,
                     "correct": final_pred == row["label_index"],
                     "context_label": context_label, "tight_label": tight_label, **score_data})
    y_true = np.asarray(y_true)
    predictions = np.asarray(predictions)
    accepted_mask = predictions >= 0
    accepted_correct = int(np.sum((predictions == y_true) & accepted_mask))
    detected_true = np.array([records[int(index)]["label_index"] for index in valid_ids], dtype=np.int64)
    detected_report = None
    if len(valid_ids):
        detected_report = classification_report_artifacts(detected_true, fused, LABELS,
                                                          output_dir, "detected_only_fused")
        classification_report_artifacts(detected_true, context_scores, LABELS,
                                        output_dir, "detected_only_context")
    precision, recall, f1, support = precision_recall_fscore_support(
        y_true, predictions, labels=np.arange(len(LABELS)), zero_division=0)
    per_class = [{"label": letter, "precision": float(precision[i]), "recall": float(recall[i]),
                  "f1": float(f1[i]), "support": int(support[i])} for i, letter in enumerate(LABELS)]
    matrix = np.zeros((24, 25), dtype=np.int64)
    for truth, prediction in zip(y_true, predictions):
        matrix[int(truth), int(prediction) if prediction >= 0 else 24] += 1
    fig, axis = plt.subplots(figsize=(14, 11))
    image = axis.imshow(matrix, cmap="Blues")
    axis.set_xticks(range(25), LABELS + ["REJECT"], rotation=60)
    axis.set_yticks(range(24), LABELS)
    axis.set_xlabel("Predicted (includes no-hand / multiple / low confidence rejection)")
    axis.set_ylabel("Actual")
    axis.set_title(f"{subset}: one decision per original photo, ALL photos in denominator")
    fig.colorbar(image, ax=axis)
    fig.tight_layout()
    fig.savefig(output_dir / "end_to_end_confusion_matrix.png", dpi=160)
    plt.close(fig)
    write_csv(output_dir / "per_photo_predictions.csv", rows)
    write_csv(output_dir / "incorrect_or_rejected.csv", [row for row in rows if not row["correct"]])
    write_csv(output_dir / "per_letter_metrics_including_rejections.csv", per_class)
    write_csv(output_dir / "end_to_end_confusion_matrix.csv",
              [{"actual": letter, **{(LABELS + ["REJECT"])[j]: int(matrix[i, j]) for j in range(25)}}
               for i, letter in enumerate(LABELS)])
    summary = {"photos_total": len(ids), "detected_one_hand": len(valid_ids),
               "detector_coverage": len(valid_ids) / len(ids),
               "accepted": int(accepted_mask.sum()), "accepted_coverage": float(accepted_mask.mean()),
               "accepted_correct": accepted_correct,
               "accepted_accuracy": accepted_correct / int(accepted_mask.sum()) if accepted_mask.any() else None,
               "end_to_end_correct_over_all_photos": accepted_correct / len(ids),
               "raw_fused_accuracy_among_detected": float(np.mean(fused.argmax(axis=1) == detected_true)) if len(valid_ids) else None,
               "macro_f1_including_rejections": float(f1.mean()),
               "rejection_counts": dict(Counter(row["detector_status"] if row["detector_status"] != "detected_one_hand"
                                               else "low_confidence" for row in rows if not row["accepted"])),
               "min_confidence": float(cfg.get("min_confidence", 0.60)),
               "fusion_version": FUSION_VERSION,
               "detected_only_report": detected_report,
               "limitation": "Photo-level benchmark. No temporal stability or unseen-signer guarantee."}
    json_write(output_dir / "evaluation.json", summary)
    return summary


class _ExistingTFLitePredictor:
    """Minimal Keras-like predict interface, preserving the deployed model."""

    def __init__(self, path):
        import tensorflow as tf

        self.interpreter = tf.lite.Interpreter(model_path=str(path), num_threads=2)
        self.interpreter.allocate_tensors()
        self.input_info = self.interpreter.get_input_details()[0]
        self.output_info = self.interpreter.get_output_details()[0]
        if list(self.input_info["shape"]) != [1, 28, 28, 1]:
            raise ValueError("Baseline model input harus [1,28,28,1]")
        if list(self.output_info["shape"]) != [1, 24]:
            raise ValueError("Baseline model output harus [1,24]")
        if self.input_info["dtype"] != np.float32 or self.output_info["dtype"] != np.float32:
            raise ValueError("Baseline model harus memakai input/output float32")

    def predict(self, images, batch_size=None, verbose=0):
        del batch_size, verbose
        values = np.asarray(images)
        if values.shape[1:] != (28, 28, 1):
            raise ValueError("Evaluasi baseline membutuhkan [N,28,28,1]")
        scores = np.empty((len(values), 24), dtype=np.float32)
        for index, image in enumerate(values):
            self.interpreter.set_tensor(self.input_info["index"], image[None].astype(np.float32))
            self.interpreter.invoke()
            scores[index] = self.interpreter.get_tensor(self.output_info["index"])[0]
        if not np.isfinite(scores).all():
            raise RuntimeError("Model baseline mengeluarkan score tidak valid")
        return scores


def _evaluate_existing_static(cfg, paths):
    """Retain the proven model and diagnose preprocessing, without training.

    Existing training used MNIST and part of this HF source. Its exact old
    cached membership is unavailable, so no new random split can establish an
    independent HF test for these pretrained weights.
    """
    source = Path(paths["existing_static_model"])
    if not source.is_file():
        raise FileNotFoundError(f"Model 24 huruf yang sekarang tidak ditemukan: {source}")
    output = Path(paths["run"]) / "static24"
    reports, models = output / "reports", output / "models"
    reports.mkdir(parents=True, exist_ok=True)
    models.mkdir(parents=True, exist_ok=True)
    record_environment(output)
    json_write(output / "configuration.json", cfg)
    copied_model = models / "existing_static24_UNCHANGED.tflite"
    shutil.copy2(source, copied_model)
    original_sha = sha256_file(source)
    copied_sha = sha256_file(copied_model)
    if original_sha != copied_sha:
        raise RuntimeError("Salinan baseline tidak identik dengan model saat ini")
    labels_source = source.parent / "labels.json"
    if labels_source.is_file():
        recorded_labels = json.loads(labels_source.read_text(encoding="utf-8"))
        recorded_labels = recorded_labels.get("labels") if isinstance(recorded_labels, dict) else recorded_labels
        if recorded_labels != LABELS:
            raise ValueError("Urutan labels.json baseline berbeda dari 24 huruf yang diharapkan")
    json_write(models / "labels.json", {"labels": LABELS})
    baseline_metadata = None
    metadata_source = source.parent / "model_metadata.json"
    if metadata_source.is_file():
        baseline_metadata = json.loads(metadata_source.read_text(encoding="utf-8"))
        json_write(models / "original_model_metadata.json", baseline_metadata)
    predictor = _ExistingTFLitePredictor(copied_model)
    print("Static24: model saat ini DIPERTAHANKAN. Tidak ada CNN baru atau training ulang.", flush=True)
    print(f"Baseline {source.name}: {source.stat().st_size:,} byte, SHA256={original_sha}", flush=True)
    mnist, mnist_files = _read_mnist(paths["data"])
    test_images, test_labels = mnist["test"]
    mnist_scores = _predict(predictor, test_images, int(cfg.get("batch_size", 256)))
    mnist_report = classification_report_artifacts(test_labels, mnist_scores, LABELS,
                                                  reports / "mnist_existing_benchmark", "official_mnist")
    mnist_report["evaluation_role"] = "Repeated diagnostic of the existing model, not new model selection."
    mnist_report["independent_new_test"] = False
    mnist_report["prior_use"] = "Original notebook monitored this benchmark during training epochs."
    json_write(reports / "mnist_existing_benchmark" / "benchmark_context.json", mnist_report)
    write_csv(reports / "mnist_existing_benchmark" / "source_predictions.csv",
              [{"id": f"mnist_test_{i}", "true_label": LABELS[int(test_labels[i])],
                "predicted_label": LABELS[int(scores.argmax())], "confidence": float(scores.max()),
                "correct": bool(scores.argmax() == test_labels[i]),
                "image_sha256": hashlib.sha256(test_images[i].tobytes()).hexdigest()}
               for i, scores in enumerate(mnist_scores)])
    real_report = None
    hf_provenance = None
    if cfg.get("static_real_enabled", True):
        real_records, duplicate_rows, hf_provenance = _fetch_real_records(
            paths["data"], cfg.get("real_dataset", HF_DATASET))
        # All supported photos are diagnostic. Do not invent an untouched test
        # split after loading weights trained on unknown old HF membership.
        real_records = [{**row, "split": "diagnostic_all",
                         "prior_training_membership": "unknown"} for row in real_records]
        write_csv(reports / "real_photo_diagnostic_manifest.csv", real_records)
        write_csv(reports / "real_photo_exact_duplicates_removed.csv", duplicate_rows)
        crops = _prepare_real_crops(real_records, cfg, paths, reports)
        real_report = _evaluate_photos(predictor, real_records, crops, "diagnostic_all",
                                       reports / "hf_existing_model_diagnostic", cfg)
        real_report.update({
            "evaluation_role": "Preprocessing diagnostic on ALL deduplicated supported HF photos.",
            "training_membership_unknown": True,
            "independent_new_test": False,
            "original_notebook_hf_counts": {"reported_training_photos": 7633, "reported_test_photos": 2400},
            "historical_44pct_comparison": "Old result used 2400 photos/7200 heuristic crops. This all-photo MediaPipe diagnostic has a different denominator and is not a direct improvement claim.",
            "purpose": "Inspect crop failures, confusion, coverage and accepted decisions before considering fine-tuning.",
        })
        json_write(reports / "hf_existing_model_diagnostic" / "evaluation.json", real_report)
    summary = {
        "status": "evaluated_existing_model", "mode": "evaluate_existing",
        "output_dir": str(output), "models_dir": str(models),
        "baseline_model": str(copied_model), "baseline_source": str(source),
        "model_sha256": copied_sha, "source_sha256": original_sha,
        "model_preserved_byte_for_byte": True,
        "size_bytes": copied_model.stat().st_size,
        "size_kib": copied_model.stat().st_size / 1024,
        "weights_updated": False, "new_cnn_trained": False,
        "new_static_training_curves_generated": False,
        "mnist_diagnostic": mnist_report, "hf_diagnostic": real_report,
        "original_metadata": baseline_metadata,
        "source_provenance": {"mnist": mnist_files, "hf": hf_provenance},
        "input_contract": {"shape": [1, 28, 28, 1], "dtype": "float32", "range": [0, 255],
                           "rescaling_inside_model": True},
        "preprocessing": {"version": PREPROCESS_VERSION, "fusion": FUSION_VERSION,
                          "hand_task_sha256": sha256_file(paths["hand_task"]),
                          "detector": "MediaPipe IMAGE, JPEG95 detection; square context+tight crops",
                          "resize_limit": "OpenCV area approximation; no byte-identical Flutter resize claim."},
        "independent_new_static_test": False,
        "claim": "Current 24-letter model is preserved. Only J/Z temporal model is trained in the default workflow.",
    }
    json_write(output / "summary.json", summary)
    json_write(models / "baseline_preservation.json", {
        "source_sha256": original_sha, "copied_sha256": copied_sha,
        "byte_identical": True, "weights_updated": False})
    (output / "MODEL_CARD.md").write_text(
        "# Existing Static24 baseline, unchanged\n\n"
        f"The current TFLite model is copied byte-for-byte. SHA256: {original_sha}. "
        f"Size: {copied_model.stat().st_size:,} bytes. No CNN fit, fine-tuning or re-export is performed.\n\n"
        "## What is evaluated\n\n"
        "The official MNIST benchmark is repeated as a diagnostic. The original notebook already monitored "
        "it during training, so it is not a new independent test. All deduplicated supported HF photos are "
        "evaluated with MediaPipe context/tight crops and current app fusion. Existing training used part "
        "of this HF source, but exact old cache membership is unavailable. These results are diagnostics, "
        "not an untouched external-test score. A random new split cannot undo previous model exposure.\n\n"
        "Detector failures and low-confidence rejections remain in the all-photo denominator. "
        "Accepted-only accuracy and detected-only CNN accuracy are also shown with their own denominators. "
        "OpenCV area resizing approximates Flutter average resizing; exact device parity remains unverified.\n\n"
        "## Next step\n\n"
        "Keep this baseline. Train J/Z as a separate temporal model. Consider static fine-tuning only "
        "after inspecting actual failures and obtaining the original trainable .keras checkpoint. "
        "Do not train a fresh CNN merely to add J and Z.\n",
        encoding="utf-8")
    return summary


def run_static(cfg, paths):
    """Default preserves current24; no implicit retraining from scratch."""
    mode = cfg.get("static_mode", "evaluate_existing")
    if mode == "evaluate_existing":
        return _evaluate_existing_static(cfg, paths)
    raise ValueError(
        f"static_mode={mode!r} tidak didukung oleh workflow ini. Gunakan evaluate_existing "
        "untuk mempertahankan model 24 huruf. Fine-tuning memerlukan checkpoint .keras asli "
        "dan rencana data terpisah, bukan training CNN baru secara diam-diam.")
