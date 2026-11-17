"""Shared, auditable utilities for the Colab training workflow."""
from __future__ import annotations

import csv
import hashlib
import importlib.metadata
import json
import os
import platform
import random
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import numpy as np


def _serializable(value):
    if isinstance(value, dict):
        return {str(k): _serializable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_serializable(v) for v in value]
    if isinstance(value, np.ndarray):
        return _serializable(value.tolist())
    if isinstance(value, np.generic):
        return _serializable(value.item())
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, float) and not np.isfinite(value):
        return None
    return value


def json_write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(_serializable(value), ensure_ascii=False, indent=2, allow_nan=False)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     suffix=".partial", delete=False) as stream:
        stream.write(text + "\n")
        temporary = Path(stream.name)
    temporary.replace(path)
    return path


def stable_hash(value):
    payload = json.dumps(_serializable(value), sort_keys=True, separators=(",", ":"),
                         ensure_ascii=False, allow_nan=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_csv(path, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = list(rows)
    columns = list(dict.fromkeys(key for row in rows for key in row))
    with path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: json.dumps(_serializable(v), ensure_ascii=False)
                             if isinstance(v, (dict, list, tuple, np.ndarray))
                             else _serializable(v) for k, v in row.items()})
    return path


def seed_everything(seed):
    random.seed(seed)
    np.random.seed(seed)
    import tensorflow as tf
    tf.keras.utils.set_random_seed(seed)
    try:
        tf.config.experimental.enable_op_determinism()
    except (AttributeError, RuntimeError):
        pass


def split_records(records, validation_fraction, test_fraction, seed):
    """Split original groups, never derived images/windows. Requires >=3 groups/class.

    A group can contain several classes (e.g. a complete negative recording session).
    Its most frequent label determines the stratification bucket; group integrity wins
    over exact fractions. Fractions and realized counts are retained in manifests.
    """
    if not 0 <= validation_fraction < 1 or not 0 <= test_fraction < 1:
        raise ValueError("Split fractions must be in [0,1).")
    if validation_fraction + test_fraction >= 1:
        raise ValueError("Training fraction must be positive.")
    groups = defaultdict(list)
    for record in records:
        if not record.get("group_id") or "label" not in record:
            raise ValueError("Each source record needs group_id and label.")
        groups[str(record["group_id"])].append(dict(record))
    buckets = defaultdict(list)
    for group, members in groups.items():
        labels = [str(item["label"]) for item in members]
        primary = sorted(set(labels), key=lambda x: (-labels.count(x), x))[0]
        buckets[primary].append(group)
    assignment = {}
    for label, ids in sorted(buckets.items()):
        ids = sorted(ids)
        required = 1 + int(validation_fraction > 0) + int(test_fraction > 0)
        if len(ids) < required:
            raise ValueError(f"Class {label}: need >= {required} distinct source groups, got {len(ids)}.")
        rng = np.random.default_rng(int(stable_hash([int(seed), label])[:16], 16))
        ids = [ids[i] for i in rng.permutation(len(ids))]
        n_test = max(1, round(len(ids) * test_fraction)) if test_fraction else 0
        n_val = max(1, round(len(ids) * validation_fraction)) if validation_fraction else 0
        while n_test + n_val >= len(ids):
            if n_test > 1 and n_test >= n_val:
                n_test -= 1
            elif n_val > 1:
                n_val -= 1
            else:
                raise ValueError(f"Cannot reserve training groups for {label}.")
        for i, group in enumerate(ids):
            assignment[group] = ("test" if i < n_test else "validation"
                                 if i < n_test + n_val else "train")
    output = [{**record, "split": assignment[str(record["group_id"])]} for record in records]
    seen = defaultdict(set)
    for record in output:
        seen[record["split"]].add(str(record["group_id"]))
    assert not (seen["train"] & seen["validation"] or seen["train"] & seen["test"]
                or seen["validation"] & seen["test"])
    return output


def cached_npz(cache_dir, key, builder):
    """Content-addressed NPZ cache, including a validated embedded signature."""
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    signature = stable_hash(key)
    path = cache_dir / f"{signature}.npz"
    if path.exists():
        try:
            with np.load(path, allow_pickle=False) as archive:
                if str(archive["_cache_signature"].item()) != signature:
                    raise ValueError("Cache signature mismatch.")
                return {name: archive[name] for name in archive.files if name != "_cache_signature"}
        except (OSError, ValueError, KeyError, EOFError):
            print("Cache invalid, rebuilding:", path.name)
    arrays = {name: np.asarray(value) for name, value in builder().items()}
    if any(value.dtype.hasobject for value in arrays.values()):
        raise ValueError("Object arrays are forbidden in reproducible caches.")
    with tempfile.NamedTemporaryFile(dir=cache_dir, suffix=".npz", delete=False) as stream:
        temporary = Path(stream.name)
    try:
        np.savez_compressed(temporary, _cache_signature=np.array(signature), **arrays)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    json_write(cache_dir / f"{signature}.json", {"signature": signature, "key": key,
               "arrays": {k: {"shape": list(v.shape), "dtype": str(v.dtype)} for k, v in arrays.items()}})
    return arrays


def classification_report_artifacts(y_true, scores, labels, out_dir, prefix):
    from sklearn.metrics import (accuracy_score, classification_report, confusion_matrix,
                                 precision_recall_fscore_support)
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    y_true = np.asarray(y_true, dtype=np.int64)
    scores = np.asarray(scores)
    if len(y_true) == 0:
        report = {"samples": 0, "accuracy": None, "reason": "No evaluable samples."}
        json_write(out_dir / f"{prefix}_metrics.json", report)
        return report
    if scores.shape != (len(y_true), len(labels)) or not np.isfinite(scores).all():
        raise ValueError("Prediction scores have invalid shape or nonfinite values.")
    predicted = scores.argmax(axis=1)
    indices = list(range(len(labels)))
    detail = classification_report(y_true, predicted, labels=indices, target_names=labels,
                                   zero_division=0, output_dict=True)
    precision, recall, f1, _ = precision_recall_fscore_support(
        y_true, predicted, labels=indices, average="macro", zero_division=0)
    present = sorted(set(y_true.tolist()))
    present_precision, present_recall, present_f1, _ = precision_recall_fscore_support(
        y_true, predicted, labels=present, average="macro", zero_division=0)
    matrix = confusion_matrix(y_true, predicted, labels=indices)
    report = {"samples": len(y_true), "accuracy": float(accuracy_score(y_true, predicted)),
              "macro_precision": float(precision), "macro_recall": float(recall),
              "macro_f1": float(f1), "macro_average_definition": "all declared output classes",
              "evaluated_true_labels": [labels[i] for i in present],
              "macro_precision_present_classes": float(present_precision),
              "macro_recall_present_classes": float(present_recall),
              "macro_f1_present_classes": float(present_f1), "per_class": detail}
    json_write(out_dir / f"{prefix}_metrics.json", report)
    write_csv(out_dir / f"{prefix}_per_class.csv", [
        {"label": label, **detail[label]} for label in labels])
    write_csv(out_dir / f"{prefix}_predictions.csv", [
        {"row": i, "true_label": labels[int(y_true[i])], "predicted_label": labels[int(predicted[i])],
         "confidence": float(scores[i].max()), "correct": bool(y_true[i] == predicted[i])}
        for i in range(len(y_true))])
    write_csv(out_dir / f"{prefix}_confusion_matrix.csv", [
        {"true_label": label, **dict(zip(labels, matrix[i].tolist()))} for i, label in enumerate(labels)])
    size = max(5, min(13, len(labels) * .43))
    fig, ax = plt.subplots(figsize=(size, size))
    im = ax.imshow(matrix, cmap="Blues")
    ax.set(xticks=indices, yticks=indices, xticklabels=labels, yticklabels=labels,
           xlabel="Prediksi", ylabel="Label asli", title=f"{prefix} | accuracy {report['accuracy']:.2%}")
    fig.colorbar(im, ax=ax, fraction=.046)
    fig.tight_layout()
    fig.savefig(out_dir / f"{prefix}_confusion_matrix.png", dpi=160)
    plt.close(fig)
    return report


def export_tflite(model, out_dir, name, representative_inputs=None,
                  validation_inputs=None, validation_labels=None):
    """Export builtin-only models and check parity on VALIDATION, not final test."""
    import tensorflow as tf
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    samples = validation_inputs if validation_inputs is not None else representative_inputs
    if samples is None or len(samples) == 0:
        raise ValueError("Export parity needs nonempty validation inputs.")
    samples = np.asarray(samples[:128], dtype=np.float32)
    keras_scores = model.predict(samples, batch_size=min(64, len(samples)), verbose=0)
    summaries = {}
    for variant in ("float32", "float16"):
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
        if variant == "float16":
            converter.optimizations = [tf.lite.Optimize.DEFAULT]
            converter.target_spec.supported_types = [tf.float16]
        payload = converter.convert()
        path = out_dir / f"{name}_{variant}.tflite"
        path.write_bytes(payload)
        interpreter = tf.lite.Interpreter(model_content=payload, num_threads=2)
        interpreter.allocate_tensors()
        input_info = interpreter.get_input_details()[0]
        output_info = interpreter.get_output_details()[0]
        expected = [1, *samples.shape[1:]]
        if input_info["dtype"] != np.float32 or output_info["dtype"] != np.float32:
            raise RuntimeError("Expected float32 input/output tensors.")
        if list(input_info["shape"]) != expected:
            raise RuntimeError(f"Unexpected TFLite input: {input_info['shape']} != {expected}.")
        lite_scores = []
        for row in samples:
            interpreter.set_tensor(input_info["index"], row[None])
            interpreter.invoke()
            lite_scores.append(interpreter.get_tensor(output_info["index"])[0].copy())
        lite_scores = np.asarray(lite_scores)
        if not np.isfinite(lite_scores).all():
            raise RuntimeError("Nonfinite TFLite predictions.")
        agreement = float(np.mean(keras_scores.argmax(1) == lite_scores.argmax(1)))
        difference = float(np.max(np.abs(keras_scores - lite_scores)))
        operators = sorted({op["op_name"] for op in interpreter._get_ops_details()})
        if any(op.startswith("Flex") for op in operators):
            raise RuntimeError("Export requires Select TF Ops, not ready for the current Flutter interpreter.")
        report = {"path": str(path), "size_bytes": len(payload), "size_mib": len(payload) / 1024**2,
                  "sha256": hashlib.sha256(payload).hexdigest(), "input_shape": input_info["shape"].tolist(),
                  "output_shape": output_info["shape"].tolist(), "input_dtype": "float32",
                  "output_dtype": "float32", "operators": operators, "parity_samples": len(samples),
                  "label_agreement": agreement, "maximum_absolute_score_difference": difference,
                  "parity_passed": agreement >= .99 and difference <= .05,
                  "parity_split": "validation"}
        if validation_labels is not None:
            labels = np.asarray(validation_labels[:len(samples)])
            report["validation_sample_accuracy"] = float(np.mean(lite_scores.argmax(1) == labels))
        json_write(out_dir / f"{name}_{variant}_export.json", report)
        summaries[variant] = report
        if not report["parity_passed"]:
            raise RuntimeError(f"{name}/{variant}: TFLite parity failed. See export report.")
    return summaries


def record_environment(out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    names = ["tensorflow", "keras", "numpy", "mediapipe", "opencv-contrib-python",
             "pandas", "pyarrow", "scikit-learn", "matplotlib", "Pillow", "kagglehub"]
    packages = {}
    for name in names:
        try:
            packages[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            packages[name] = None
    report = {"python": sys.version, "platform": platform.platform(), "packages": packages,
              "recorded_at_utc": datetime.now(timezone.utc).isoformat()}
    json_write(out_dir / "environment.json", report)
    result = subprocess.run([sys.executable, "-m", "pip", "freeze"], capture_output=True, text=True)
    (out_dir / "requirements_actual.txt").write_text(result.stdout, encoding="utf-8")
    return report
