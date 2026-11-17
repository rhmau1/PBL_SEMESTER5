"""One entry point: preserve/evaluate the current ASL24 model, train temporal J/Z.

This workflow creates new artifacts only. It never modifies the Flutter app.
"""
from __future__ import annotations

import argparse
import contextlib
import json
import os
import shutil
import sys
import traceback
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from training_common import json_write, record_environment, sha256_file, stable_hash, write_csv


DEFAULT_CONFIG = {
    "seed": 42,
    "split_seed": 2026,
    "static_mode": "evaluate_existing",
    "validation_fraction": 0.15,
    "test_fraction": 0.15,
    "dynamic_epochs": 60,
    "batch_size": 256,
    "learning_rate": 0.001,
    "static_real_enabled": True,
    "sequence_length": 48,
    "dynamic_sample_fps": 15,
    "min_confidence": 0.60,
    "target_dynamic_accuracy": 0.995,
    "max_model_mib": 10,
    "require_gpu": True,
    "use_drive": True,
    "drive_dir": "/content/drive/MyDrive/LatihIsyarat_Training_J_Z",
    "auto_download": True,
}

HAND_TASK_URL = (
    "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
    "hand_landmarker/float16/1/hand_landmarker.task"
)


class _Tee:
    def __init__(self, original, file):
        self.original, self.file = original, file

    def write(self, text):
        self.original.write(text)
        self.file.write(text)
        self.file.flush()
        return len(text)

    def flush(self):
        self.original.flush()
        self.file.flush()

    def isatty(self):
        return False


def _prepare_paths(cfg):
    if cfg["use_drive"]:
        if not Path("/content/drive/MyDrive").is_dir():
            from google.colab import drive
            drive.mount("/content/drive")
        root = Path(cfg["drive_dir"])
        if not Path("/content/drive/MyDrive").is_dir():
            raise RuntimeError("Google Drive belum terpasang. Jalankan kembali mount Drive.")
    else:
        root = Path(cfg.get("work_dir", "/content/LatihIsyarat_Training_J_Z"))
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f_utc")
    run = root / "hasil" / f"training_{timestamp}_{stable_hash(cfg)[:8]}"
    paths = {"root": root, "data": root / "datasets", "cache": root / "cache_v2",
             "negative_videos": root / "negative_videos", "run": run}
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)
    paths["hand_task"] = paths["data"] / "mediapipe" / "hand_landmarker_v1.task"
    paths["existing_static_model"] = Path(cfg.get("existing_static_model_path") or
        Path(__file__).resolve().parent / "baseline_model" / "model_float16.tflite")
    os.environ["KAGGLEHUB_CACHE"] = str(paths["data"] / "kagglehub")
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    return paths


def _preflight(cfg, paths):
    import tensorflow as tf
    import mediapipe as mp
    gpus = tf.config.list_physical_devices("GPU")
    print("TensorFlow:", tf.__version__, "MediaPipe:", mp.__version__, "GPU:", gpus)
    if cfg["require_gpu"] and not gpus:
        raise RuntimeError("Pilih Runtime > Change runtime type > T4 GPU, kemudian Run all.")
    for gpu in gpus:
        try:
            tf.config.experimental.set_memory_growth(gpu, True)
        except RuntimeError:
            pass
    if not hasattr(mp.tasks.vision, "HandLandmarker"):
        raise RuntimeError("MediaPipe Tasks HandLandmarker tidak tersedia. Jalankan sel instalasi.")
    target = paths["hand_task"]
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        temporary = target.with_suffix(".part")
        print("Mengunduh model MediaPipe resmi (sekali, disimpan di Drive).")
        urllib.request.urlretrieve(HAND_TASK_URL, temporary)
        temporary.replace(target)
    if target.stat().st_size < 1_000_000:
        raise RuntimeError("File hand_landmarker.task tidak lengkap. Hapus file tersebut lalu jalankan ulang.")
    json_write(paths["run"] / "mediapipe_asset.json", {
        "url": HAND_TASK_URL, "sha256": sha256_file(target), "size_bytes": target.stat().st_size,
        "mode_static": "IMAGE", "mode_dynamic": "VIDEO", "trainable_in_this_workflow": False,
    })


def _package(paths, summary):
    run = paths["run"]
    json_write(run / "RINGKASAN_HASIL.json", summary)
    inventory = []
    for path in sorted(run.rglob("*")):
        if path.is_file() and path.name != "SHA256SUMS.csv":
            inventory.append({"path": path.relative_to(run).as_posix(),
                              "size_bytes": path.stat().st_size, "sha256": sha256_file(path)})
    write_csv(run / "SHA256SUMS.csv", inventory)
    archive = run.parent / f"{run.name}_LENGKAP.zip"
    temporary = archive.with_suffix(".zip.partial")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for path in sorted(run.rglob("*")):
            if path.is_file():
                output.write(path, Path(run.name) / path.relative_to(run))
    temporary.replace(archive)
    print("\nFOLDER HASIL PERMANEN:", run)
    print("SATU ZIP LENGKAP:", archive)
    print("Ukuran ZIP:", round(archive.stat().st_size / 1024**2, 2), "MiB")
    return archive


def run_all(config=None):
    cfg = {**DEFAULT_CONFIG, **(config or {})}
    if cfg["sequence_length"] < 8 or cfg["dynamic_sample_fps"] <= 0:
        raise ValueError("sequence_length >= 8 dan dynamic_sample_fps > 0 diperlukan.")
    paths = _prepare_paths(cfg)
    summary = {"status": "RUNNING", "run_directory": str(paths["run"]),
               "started_utc": datetime.now(timezone.utc).isoformat(), "config": cfg,
               "claims": {
                   "perfect_accuracy_guaranteed": False,
                   "mobile_integration_performed": False,
                   "static_and_dynamic_are_separate_models": True,
                   "test_results_are_not_used_for_model_selection": True,
                   "static24_weights_preserved": True,
                   "HF_static_scores_are_diagnostic_not_independent_test": True,
               }}
    error = None
    log_path = paths["run"] / "console.log"
    with log_path.open("w", encoding="utf-8") as log:
        with contextlib.redirect_stdout(_Tee(sys.stdout, log)), contextlib.redirect_stderr(_Tee(sys.stderr, log)):
            try:
                print("Output permanen:", paths["run"])
                print("Target akurasi adalah sasaran eksperimen, bukan jaminan.")
                json_write(paths["run"] / "config.json", cfg)
                source_dir = Path(__file__).resolve().parent
                snapshot = paths["run"] / "source_code"
                snapshot.mkdir()
                for name in ("train_all.py", "training_common.py", "static_training.py", "dynamic_training.py",
                             "requirements_colab.txt", "README.md", "LAPORAN_MODEL_DAN_RENCANA_INTEGRASI.md"):
                    source = source_dir / name
                    if source.exists():
                        shutil.copy2(source, snapshot / name)
                _preflight(cfg, paths)
                record_environment(paths["run"])
                from static_training import run_static
                from dynamic_training import run_dynamic
                print("\n[1/2] PERTAHANKAN MODEL 24 HURUF DAN EVALUASI CROP MEDIAPIPE")
                summary["static24"] = run_static(cfg, paths)
                json_write(paths["run"] / "RINGKASAN_HASIL.json", summary)
                # Free the static training graph before creating the temporal model.
                import gc
                import tensorflow as tf
                tf.keras.backend.clear_session()
                gc.collect()
                print("\n[2/2] TRAINING GERAKAN J/Z + OTHER")
                summary["dynamic_jz"] = run_dynamic(cfg, paths, summary["static24"])
                sizes = [{"path": p.relative_to(paths["run"]).as_posix(),
                          "size_bytes": p.stat().st_size, "size_mib": p.stat().st_size / 1024**2}
                         for p in sorted(paths["run"].rglob("*.tflite"))]
                summary["exported_model_sizes"] = sizes
                summary["size_budget_mib_per_model"] = cfg["max_model_mib"]
                summary["all_exports_within_size_budget"] = all(
                    item["size_mib"] <= cfg["max_model_mib"] for item in sizes)
                summary["status"] = "COMPLETED"
            except Exception as exc:
                error = exc
                summary["status"] = "FAILED"
                summary["error"] = {"type": type(exc).__name__, "message": str(exc)}
                traceback.print_exc()
                (paths["run"] / "failure_traceback.txt").write_text(traceback.format_exc(), encoding="utf-8")
            finally:
                summary["finished_utc"] = datetime.now(timezone.utc).isoformat()
                print("\nSTATUS:", summary["status"])
    archive = _package(paths, summary)
    if cfg.get("result_pointer"):
        json_write(cfg["result_pointer"], {"status": summary["status"], "zip_path": str(archive),
                                          "run_directory": str(paths["run"])})
    if cfg["auto_download"]:
        try:
            from google.colab import files
            files.download(str(archive))
        except Exception as download_error:
            print("Unduh ZIP secara manual dari Drive:", archive, "|", download_error)
    if error is not None:
        raise RuntimeError(f"Training belum selesai. Bukti dan hasil sementara ada di {archive}") from error
    print("Selesai. Periksa RINGKASAN_HASIL.json dan model_card sebelum memilih model.")
    return {**summary, "zip_path": str(archive)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, help="JSON konfigurasi opsional")
    args = parser.parse_args()
    run_all(json.loads(args.config.read_text(encoding="utf-8")) if args.config else None)
