"""Train a small, separate temporal J/Z classifier for the Colab workflow.

The existing 24-letter CNN is not replaced here.  J and Z are movements, so
this module learns sequences of MediaPipe landmarks, including wrist motion.
Run this through train_all.py/the generated notebook, not in Flutter.
"""

from __future__ import annotations

import importlib.metadata
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

from training_common import (
    cached_npz,
    classification_report_artifacts,
    export_tflite,
    json_write,
    seed_everything,
    sha256_file,
    split_records,
    stable_hash,
    write_csv,
)


LABELS = ["J", "Z", "OTHER"]
VIDEO_EXTENSIONS = {".avi", ".mp4", ".mov", ".mkv", ".webm", ".m4v"}
FEATURE_VERSION = "jz_fixed_clip_anchor_palm_scale_v1"


def _package_version(name: str) -> str:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "unknown"


def _download_and_manifest(cfg: dict, paths: dict, out: Path) -> tuple[list, dict]:
    """Hash actual videos. Exact duplicate clips never become independent rows."""
    source = "signnteam/asl-sign-language-alphabet-videos-j-z"
    if cfg.get("dynamic_dataset_path"):
        dataset_dir = Path(cfg["dynamic_dataset_path"])
    else:
        import kagglehub

        # KAGGLEHUB_CACHE is configured on persistent Drive by the main runner.
        dataset_dir = Path(kagglehub.dataset_download(source))
    if not dataset_dir.is_dir():
        raise FileNotFoundError(f"Folder dataset video tidak ditemukan: {dataset_dir}")

    files = sorted(p for p in dataset_dir.rglob("*") if p.suffix.lower() in VIDEO_EXTENSIONS)
    rows = []
    for p in files:
        rel = p.relative_to(dataset_dir)
        classes = [part.upper() for part in rel.parts[:-1] if part.upper() in {"J", "Z"}]
        if not classes:
            continue
        label = classes[-1]
        rows.append(
            {
                "source_path": str(p),
                "relative_path": rel.as_posix(),
                "label": label,
                "label_index": LABELS.index(label),
                "source": "SigNN",
                "sha256": sha256_file(p),
                "size_bytes": p.stat().st_size,
                "session_hint": "",
                "signer_id": "unknown",
            }
        )

    negative_dir = Path(paths["negative_videos"])
    if negative_dir.is_dir():
        negatives = sorted(p for p in negative_dir.rglob("*") if p.suffix.lower() in VIDEO_EXTENSIONS)
        for p in negatives:
            rel = p.relative_to(negative_dir)
            # Put recordings of the same person/session in one folder. A flat
            # folder has unknown identity, so only exact hashes can be grouped.
            session = rel.parts[0] if len(rel.parts) > 1 else ""
            rows.append(
                {
                    "source_path": str(p),
                    "relative_path": rel.as_posix(),
                    "label": "OTHER",
                    "label_index": 2,
                    "source": "user_real_negative",
                    "sha256": sha256_file(p),
                    "size_bytes": p.stat().st_size,
                    "session_hint": session,
                    "signer_id": "unknown" if not session else "grouped_by_supplied_folder",
                }
            )

    if not {"J", "Z"}.issubset({r["label"] for r in rows}):
        raise RuntimeError("Dataset harus berisi video J dan Z dalam folder J/ dan Z/.")
    unique: dict[str, dict] = {}
    duplicate_rows = []
    for r in rows:
        if r["sha256"] in unique:
            original = unique[r["sha256"]]
            if original["label"] != r["label"]:
                raise RuntimeError(
                    "Video identik mempunyai label berbeda. Periksa "
                    f"{original['source_path']} dan {r['source_path']}."
                )
            duplicate_rows.append({**r, "duplicate_of": original["source_path"]})
            if r["session_hint"] and original["session_hint"] != r["session_hint"]:
                original.setdefault("extra_sessions", []).append(r["session_hint"])
            continue
        unique[r["sha256"]] = r

    # Union session groups as well as exact duplicates. This also handles the
    # same negative video copied between two session folders.
    records = list(unique.values())
    parent = list(range(len(records)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a, b):
        a, b = find(a), find(b)
        if a != b:
            parent[max(a, b)] = min(a, b)

    sessions = {}
    for i, r in enumerate(records):
        session_keys = [r["session_hint"], *r.get("extra_sessions", [])]
        for session in session_keys:
            if not session or r["source"] != "user_real_negative":
                continue
            if session in sessions:
                union(i, sessions[session])
            else:
                sessions[session] = i
    for i, r in enumerate(records):
        root = find(i)
        r["group_id"] = "video_group_" + records[root]["sha256"]

    records = split_records(
        records,
        float(cfg.get("validation_fraction", 0.15)),
        float(cfg.get("test_fraction", 0.15)),
        int(cfg.get("split_seed", 2026)),
    )
    assignments = {r["sha256"]: r["split"] for r in records}
    for r in duplicate_rows:
        r["split"] = assignments[r["sha256"]]
    write_csv(out / "source_video_split_manifest.csv", records)
    write_csv(out / "exact_duplicate_videos.csv", duplicate_rows)

    groups = defaultdict(set)
    for r in records:
        groups[r["group_id"]].add(r["split"])
    if any(len(s) > 1 for s in groups.values()):
        raise AssertionError("Satu group video masuk ke lebih dari satu split.")
    info = {
        "source": source,
        "source_url": "https://www.kaggle.com/datasets/" + source,
        "provider_license": "CC0 Public Domain (according to Kaggle metadata)",
        "dataset_dir": str(dataset_dir),
        "raw_files_found": len(rows),
        "unique_videos": len(records),
        "exact_duplicate_files_removed": len(duplicate_rows),
        "unique_video_classes": dict(Counter(r["label"] for r in records)),
        "split_counts": {
            s: dict(Counter(r["label"] for r in records if r["split"] == s))
            for s in ("train", "validation", "test")
        },
        "split_seed": int(cfg.get("split_seed", 2026)),
        "split_unit": "original video group, before extraction/augmentation",
        "signer_independence": False,
        "signer_limitation": (
            "SigNN manifest does not provide verified signer IDs. Byte-identical videos "
            "are grouped, but different recordings/re-encodings of one signer may cross splits. "
            "Real negative session folders are grouped when provided."
        ),
        "manifest_fingerprint": stable_hash(
            [{k: r[k] for k in ("sha256", "label", "group_id", "split")} for r in records]
        ),
    }
    json_write(out / "dataset_provenance.json", info)
    return records, info


def _feature_contract(cfg: dict, hand_task: Path) -> dict:
    import cv2

    return {
        "version": FEATURE_VERSION,
        "extractor_source_sha256": sha256_file(Path(__file__)),
        "sequence_length": int(cfg.get("sequence_length", 48)),
        "sample_fps": float(cfg.get("dynamic_sample_fps", 15)),
        "feature_count": 64,
        "feature_order": "landmark0_x,y,z,...,landmark20_x,y,z,presence",
        "landmark_order": "MediaPipe HandLandmarker standard 21 landmarks",
        "rgb_input": True,
        "image_mirror": False,
        "handedness_canonicalization": False,
        "max_image_side": int(cfg.get("dynamic_max_image_side", 640)),
        "timestamps": "decoded video milliseconds, fps fallback only if unavailable/non-monotonic",
        "sampling": "first decoded frame at/after each requested real-time sample, no repeated stale frames",
        "normalization": {
            "aspect_ratio": "x and z multiplied by image_width/image_height; y unchanged",
            "fixed_anchor": "median wrist of first at most 3 detected samples",
            "fixed_palm_scale": "median Euclidean wrist-to-middle-MCP distance over detected samples",
            "formula": "(all_landmark_xyz - one_clip_anchor_xyz) / one_clip_palm_scale",
            "preserves_wrist_trajectory": True,
            "per_frame_wrist_recentering": False,
            "left_right": "no inference mirroring; training optionally mirrors whole trajectories",
        },
        "missing_detection": {
            "minimum_detected_fraction": float(cfg.get("dynamic_min_detected_fraction", 0.60)),
            "minimum_detected_samples": int(cfg.get("dynamic_min_detected_samples", 6)),
            "maximum_missing_gap_seconds": float(cfg.get("dynamic_max_missing_gap_seconds", 0.55)),
            "coordinates": "interpolate short gaps; nearest detected coordinate at short clip edges",
            "presence": "observed=1, missing=0; temporally resampled to 0..1",
            "failed_clips": "rejected and reported, never relabeled as OTHER",
        },
        "no_hand_policy": (
            "Reject before temporal classification when no usable landmarks exist. "
            "Synthetic OTHER does not train a no-hand image detector."
        ),
        "temporal_resampling": (
            "linear interpolation to a fixed length over the complete sampled clip timeline; "
            "no automatic trimming of gesture starts/ends"
        ),
        "clip_duration_min_seconds": float(cfg.get("dynamic_min_clip_seconds", 0.25)),
        "mediapipe_version": _package_version("mediapipe"),
        "numpy_version": np.__version__,
        "opencv_version": cv2.__version__,
        "hand_landmarker_task_sha256": sha256_file(hand_task),
        "detector_options": {
            "running_mode": "VIDEO",
            "num_hands": 2,
            "min_hand_detection_confidence": 0.50,
            "min_hand_presence_confidence": 0.50,
            "min_tracking_confidence": 0.50,
        },
        "hand_selection": "largest hand initially, then nearest wrist for temporal continuity",
        "integration_warning": (
            "Future Flutter implementation must use this sequence contract and actual frame timestamps. "
            "The existing approximately 320 ms detector interval is not the requested 15 fps. "
            "A repeated old landmark must not be treated as a new observation."
        ),
    }


def _extract_raw_video(video: Path, hand_task: Path, contract: dict) -> dict:
    """One fresh MediaPipe VIDEO tracker per original clip, with true timestamps."""
    import cv2
    import mediapipe as mp
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision

    cap = cv2.VideoCapture(str(video))
    if not cap.isOpened():
        return {"landmarks": np.empty((0, 21, 3), np.float32),
                "timestamps": np.empty(0, np.float64), "presence": np.empty(0, np.float32),
                "handedness": np.empty(0, np.int8), "video_info": np.array(json.dumps({"error": "cannot_open_video"}))}
    fps = float(cap.get(cv2.CAP_PROP_FPS))
    fps_is_fallback = not math.isfinite(fps) or fps <= 0
    if fps_is_fallback:
        fps = 30.0
    reported_frames = int(max(0, cap.get(cv2.CAP_PROP_FRAME_COUNT)))
    opts = contract["detector_options"]
    options = vision.HandLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(hand_task)),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=opts["num_hands"],
        min_hand_detection_confidence=opts["min_hand_detection_confidence"],
        min_hand_presence_confidence=opts["min_hand_presence_confidence"],
        min_tracking_confidence=opts["min_tracking_confidence"],
    )
    raw_points, times, present, handedness = [], [], [], []
    frame_index = 0
    previous_raw_time = -1.0
    previous_task_ms = -1
    next_sample = 0.0
    sample_period = 1.0 / max(1.0, float(contract["sample_fps"]))
    last_wrist = None
    timestamp_fallbacks = 0
    width = height = 0
    extraction_error = ""
    try:
        with vision.HandLandmarker.create_from_options(options) as detector:
            while True:
                ok, bgr = cap.read()
                if not ok:
                    break
                source_time = float(cap.get(cv2.CAP_PROP_POS_MSEC)) / 1000.0
                expected_time = frame_index / fps
                if not math.isfinite(source_time) or source_time <= previous_raw_time:
                    source_time = expected_time
                    timestamp_fallbacks += 1
                if source_time <= previous_raw_time:
                    source_time = previous_raw_time + 1.0 / fps
                previous_raw_time = source_time
                frame_index += 1
                if source_time + 1e-6 < next_sample:
                    continue
                # Scheduling by time skips redundant frames if source fps is high.
                while next_sample <= source_time + 1e-6:
                    next_sample += sample_period
                height, width = bgr.shape[:2]
                scale = min(1.0, contract["max_image_side"] / max(width, height))
                if scale < 1.0:
                    bgr = cv2.resize(bgr, (round(width * scale), round(height * scale)), interpolation=cv2.INTER_AREA)
                rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
                task_ms = max(previous_task_ms + 1, int(round(source_time * 1000)))
                previous_task_ms = task_ms
                result = detector.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), task_ms)
                chosen = None
                chosen_i = -1
                if result.hand_landmarks:
                    choices = [np.asarray([[p.x, p.y, p.z] for p in hand], np.float32)
                               for hand in result.hand_landmarks]
                    if last_wrist is None:
                        chosen_i = int(np.argmax([np.prod(np.ptp(hand[:, :2], axis=0)) for hand in choices]))
                    else:
                        chosen_i = int(np.argmin([np.linalg.norm(hand[0, :2] - last_wrist) for hand in choices]))
                    chosen = choices[chosen_i]
                    last_wrist = chosen[0, :2].copy()
                times.append(source_time)
                if chosen is None:
                    raw_points.append(np.full((21, 3), np.nan, np.float32))
                    present.append(0.0)
                    handedness.append(-1)
                else:
                    # Convert normalized x/z into image-height units. Downscale
                    # preserves aspect ratio, so coordinates remain consistent.
                    chosen[:, [0, 2]] *= width / height
                    raw_points.append(chosen)
                    present.append(1.0)
                    category = result.handedness[chosen_i][0].category_name if result.handedness else ""
                    handedness.append(1 if category.lower() == "right" else 0)
    except Exception as exc:
        extraction_error = f"{type(exc).__name__}: {exc}"
    finally:
        cap.release()
    info = {
        "decoded_frames": frame_index,
        "reported_frames": reported_frames,
        "reported_or_fallback_fps": fps,
        "fps_fallback_used": fps_is_fallback,
        "timestamp_fallback_frames": timestamp_fallbacks,
        "width": width,
        "height": height,
        "error": extraction_error or ("decoder_returned_no_frames" if frame_index == 0 else ""),
    }
    return {
        "landmarks": np.asarray(raw_points, np.float32).reshape((-1, 21, 3)),
        "timestamps": np.asarray(times, np.float64),
        "presence": np.asarray(present, np.float32),
        "handedness": np.asarray(handedness, np.int8),
        "video_info": np.array(json.dumps(info)),
    }


def _missing_gap_seconds(t: np.ndarray, mask: np.ndarray) -> float:
    if len(t) == 0:
        return 0.0
    step = float(np.median(np.diff(t))) if len(t) > 1 else 0.0
    longest, i = 0.0, 0
    while i < len(mask):
        if mask[i]:
            i += 1
            continue
        start = i
        while i < len(mask) and not mask[i]:
            i += 1
        # Include the sample spacing, including missing boundary samples.
        longest = max(longest, float(t[i - 1] - t[start] + step))
    return longest


def _extract_cacheable_video(video: Path, hand_task: Path, contract: dict) -> dict:
    """Cache legitimate observations, not temporary decoder/detector failures."""
    raw = _extract_raw_video(video, hand_task, contract)
    info = json.loads(str(np.asarray(raw["video_info"]).item()))
    if info.get("error"):
        raise RuntimeError(f"Ekstraksi video gagal, cache tidak disimpan: {info['error']}")
    # No-hand observations are genuine data and remain cacheable. They will be
    # rejected transparently by _make_features rather than retried as errors.
    return raw


def _make_features(raw: dict, contract: dict) -> tuple[np.ndarray | None, dict]:
    t = np.asarray(raw["timestamps"], np.float64)
    points = np.asarray(raw["landmarks"], np.float32)
    mask = np.asarray(raw["presence"], np.float32) > 0.5
    video_info = json.loads(str(np.asarray(raw["video_info"]).item()))
    stats = {
        **video_info,
        "sampled_frames": len(t),
        "detected_frames": int(mask.sum()),
        "detection_fraction": float(mask.mean()) if len(mask) else 0.0,
        "sampled_duration_seconds": float(t[-1] - t[0]) if len(t) > 1 else 0.0,
        "longest_missing_gap_seconds": _missing_gap_seconds(t, mask),
        "accepted": False,
        "rejection_reason": "",
    }
    limits = contract["missing_detection"]
    if video_info.get("error"):
        stats["rejection_reason"] = "video_or_detector_error"
    elif len(t) < 2 or stats["sampled_duration_seconds"] < contract["clip_duration_min_seconds"]:
        stats["rejection_reason"] = "clip_too_short"
    elif mask.sum() < limits["minimum_detected_samples"]:
        stats["rejection_reason"] = "too_few_detected_samples"
    elif stats["detection_fraction"] < limits["minimum_detected_fraction"]:
        stats["rejection_reason"] = "too_many_missing_detections"
    elif stats["longest_missing_gap_seconds"] > limits["maximum_missing_gap_seconds"]:
        stats["rejection_reason"] = "missing_gap_too_long"
    if stats["rejection_reason"]:
        return None, stats

    observed = points[mask]
    palm = np.linalg.norm(observed[:, 9] - observed[:, 0], axis=1)
    scale = float(np.median(palm))
    if not math.isfinite(scale) or scale < 0.005:
        stats["rejection_reason"] = "invalid_palm_scale"
        return None, stats
    anchor = np.median(observed[:3, 0], axis=0)
    # ONE anchor and ONE scale for the entire clip retain the wrist path.
    detected_flat = ((observed - anchor) / scale).reshape((-1, 63))
    query = np.linspace(t[0], t[-1], contract["sequence_length"])
    features = np.stack([np.interp(query, t[mask], detected_flat[:, j]) for j in range(63)], axis=-1)
    presence = np.interp(query, t, mask.astype(np.float32))[:, None]
    features = np.concatenate([features, presence], axis=-1).astype(np.float32)
    if not np.isfinite(features).all():
        stats["rejection_reason"] = "nonfinite_features"
        return None, stats
    stats.update(accepted=True, palm_scale=scale, anchor_xyz=anchor.tolist())
    return features, stats


def _synthetic_idle(sequence: np.ndarray, rng: np.random.Generator, endpoint: int) -> np.ndarray:
    """A held pose is only a synthetic idle surrogate, not a real motion dataset."""
    result = np.repeat(sequence[[endpoint]], len(sequence), axis=0).copy()
    # Tiny rigid global jitter keeps anatomy intact, with no J/Z trajectory.
    jitter = rng.normal(0, 0.006, (len(result), 1, 3)).astype(np.float32)
    result[:, :63] = (result[:, :63].reshape((-1, 21, 3)) + jitter).reshape((-1, 63))
    result[:, 63] = 1.0
    return result


def _augment_sequence(sequence: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    result = sequence.copy()
    n = len(result)
    # Strictly monotonic temporal warp. Never shuffle/reverse J/Z and assign a
    # false OTHER label: a reversed or partial gesture may still be meaningful.
    increments = rng.uniform(0.70, 1.30, n - 1)
    source_t = np.concatenate([[0.0], np.cumsum(increments)])
    source_t /= source_t[-1]
    target_t = np.linspace(0.0, 1.0, n)
    result = np.stack([np.interp(target_t, source_t, result[:, i]) for i in range(64)], axis=-1).astype(np.float32)
    xyz = result[:, :63].reshape((n, 21, 3))
    angle = rng.uniform(-0.14, 0.14)
    c, s = np.cos(angle), np.sin(angle)
    x, y = xyz[:, :, 0].copy(), xyz[:, :, 1].copy()
    xyz[:, :, 0] = c * x - s * y
    xyz[:, :, 1] = s * x + c * y
    if rng.random() < 0.5:
        xyz[:, :, 0] *= -1.0  # Entire clip, to represent left/right signing.
    xyz *= rng.uniform(0.90, 1.10)
    xyz += rng.normal(0, 0.004, xyz.shape).astype(np.float32)
    result[:, :63] = xyz.reshape((n, 63))
    return result


def _plot_training(history: dict, out: Path, best_epoch: int) -> None:
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(1, 2, figsize=(11, 4))
    epochs = np.arange(1, len(history["loss"]) + 1)
    for ax, metric in zip(axes, ("loss", "accuracy")):
        ax.plot(epochs, history[metric], label="Training")
        ax.plot(epochs, history["val_" + metric], label="Validation")
        ax.axvline(best_epoch, linestyle="--", color="grey", label="Best validation checkpoint")
        ax.set(xlabel="Epoch", ylabel=metric, title="Dynamic GRU " + metric)
        ax.legend(fontsize=8)
        ax.grid(alpha=0.2)
    fig.tight_layout()
    fig.savefig(out / "training_curves.png", dpi=180)
    plt.close(fig)


def _plot_paths(x: np.ndarray, examples: list, out: Path) -> None:
    import matplotlib.pyplot as plt

    selected = []
    for label in LABELS:
        choices = [i for i, e in enumerate(examples) if e["label"] == label and e["split"] == "train"]
        selected.extend(choices[:2])
    if not selected:
        return
    fig, axes = plt.subplots(1, len(selected), figsize=(3.2 * len(selected), 3.5), squeeze=False)
    for ax, i in zip(axes[0], selected):
        sequence = x[i]
        # Wrist trajectory is visible because no per-frame centering is used.
        ax.plot(sequence[:, 0], sequence[:, 1], color="grey", linewidth=1)
        ax.scatter(sequence[:, 0], sequence[:, 1], c=np.arange(len(sequence)), cmap="viridis", s=12)
        ax.scatter(sequence[0, 0], sequence[0, 1], marker="s", color="green", label="Start")
        ax.scatter(sequence[-1, 0], sequence[-1, 1], marker="x", color="red", label="End")
        ax.invert_yaxis()
        ax.set_aspect("equal", adjustable="datalim")
        ax.set_title(examples[i]["label"] + (" synthetic idle" if examples[i]["synthetic"] else " source video"))
        ax.set(xlabel="Wrist x / palm size", ylabel="Wrist y / palm size")
        ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(out / "training_wrist_trajectory_examples.png", dpi=160)
    plt.close(fig)


def _build_model(cfg: dict):
    import tensorflow as tf

    inputs = tf.keras.Input((int(cfg.get("sequence_length", 48)), 64), name="landmark_sequence")
    # unroll=True avoids TensorList/SELECT_TF_OPS for this fixed, short window.
    x = tf.keras.layers.GRU(64, unroll=True, reset_after=True, name="temporal_gru")(inputs)
    x = tf.keras.layers.Dropout(0.20)(x)
    x = tf.keras.layers.Dense(32, activation="relu")(x)
    outputs = tf.keras.layers.Dense(3, activation="softmax", name="gesture_scores")(x)
    model = tf.keras.Model(inputs, outputs, name="jz_landmark_gru")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(float(cfg.get("learning_rate", 0.001)), clipnorm=1.0),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def run_dynamic(cfg: dict, paths: dict, static_result: dict | None = None) -> dict:
    """Download/cache source clips, train on validation, evaluate final test once.

    Returns a JSON-safe report. Test source clips are untouched by training
    augmentation. Synthetic idle results are explicitly separated from real
    recorded negative clips and never establish mobile readiness on their own.
    """
    import tensorflow as tf

    del static_result  # Independent feature stream; do not mix static labels into video truth.
    seed = int(cfg.get("seed", 42))
    seed_everything(seed)
    out = Path(paths["run"]) / "dynamic_JZ"
    out.mkdir(parents=True, exist_ok=True)
    model_dir = out / "models"
    model_dir.mkdir(exist_ok=True)
    hand_task = Path(paths["hand_task"])
    if not hand_task.is_file():
        raise FileNotFoundError("MediaPipe hand_landmarker.task belum tersedia. Jalankan setup utama.")
    contract = _feature_contract(cfg, hand_task)
    json_write(out / "preprocessing_contract.json", contract)
    json_write(out / "labels.json", LABELS)
    records, source_info = _download_and_manifest(cfg, paths, out)
    print("[J/Z] Video unik:", source_info["unique_video_classes"])
    print("[J/Z] Ekstraksi MediaPipe pertama dapat lama; cache landmark disimpan permanen.")
    cache_dir = Path(paths["cache"]) / "dynamic_landmarks"
    cache_dir.mkdir(parents=True, exist_ok=True)
    raw_evidence_dir = out / "timestamped_landmarks"
    raw_evidence_dir.mkdir(exist_ok=True)
    samples, examples, coverage = [], [], []
    for i, r in enumerate(records):
        cache_signature = {"source_sha256": r["sha256"], "contract": contract}
        cache_key = stable_hash(cache_signature)
        raw_evidence_path = raw_evidence_dir / (r["sha256"] + ".npz")
        try:
            raw = cached_npz(cache_dir, cache_signature,
                             lambda r=r: _extract_cacheable_video(Path(r["source_path"]), hand_task, contract))
            # Small landmark evidence belongs in the downloadable run folder;
            # the multi-gigabyte original dataset remains in persistent cache.
            np.savez_compressed(raw_evidence_path, **raw,
                                source_sha256=np.array(r["sha256"]),
                                feature_contract_hash=np.array(stable_hash(contract)))
            features, stats = _make_features(raw, contract)
        except Exception as exc:
            features = None
            stats = {"accepted": False, "rejection_reason": "cache_or_extraction_error",
                     "error": f"{type(exc).__name__}: {exc}", "sampled_frames": 0,
                     "detected_frames": 0, "detection_fraction": 0.0}
        coverage.append({**r, **stats, "landmark_cache_key": cache_key,
                         "landmark_evidence_file": str(raw_evidence_path.relative_to(out))
                         if raw_evidence_path.is_file() else ""})
        if features is not None:
            samples.append(features)
            examples.append({**r, "synthetic": False, "synthetic_method": "", "parent_sha256": r["sha256"]})
            # Derived negatives stay in their parent source split. The video is
            # split BEFORE this step; no held-out source enters training.
            if r["label"] != "OTHER":
                idle_rng = np.random.default_rng(int(r["sha256"][:16], 16) ^ seed)
                endpoint = 0 if idle_rng.random() < 0.5 else -1
                samples.append(_synthetic_idle(features, idle_rng, endpoint))
                examples.append({**r, "label": "OTHER", "label_index": 2, "synthetic": True,
                                 "synthetic_method": "held_endpoint_pose_with_tiny_rigid_jitter",
                                 "parent_sha256": r["sha256"]})
        if (i + 1) % 20 == 0 or i + 1 == len(records):
            print(f"[J/Z] Landmark {i + 1}/{len(records)} video, diterima "
                  f"{sum(bool(c['accepted']) for c in coverage)}")

    write_csv(out / "video_detection_coverage.csv", coverage)
    write_csv(out / "failed_video_extraction.csv", [r for r in coverage if not r["accepted"]])
    write_csv(out / "sequence_split_manifest.csv", examples)
    coverage_summary = []
    for split in ("train", "validation", "test"):
        for label in LABELS:
            subset = [r for r in coverage if r["split"] == split and r["label"] == label]
            accepted = sum(bool(r["accepted"]) for r in subset)
            coverage_summary.append({"split": split, "label": label, "original_videos": len(subset),
                                     "accepted_videos": accepted, "rejected_videos": len(subset) - accepted,
                                     "coverage": accepted / len(subset) if subset else None,
                                     "mean_detection_fraction": float(np.mean([r["detection_fraction"] for r in subset])) if subset else None})
    write_csv(out / "coverage_by_class_and_split.csv", coverage_summary)
    if not samples:
        raise RuntimeError(f"Tidak ada video lolos deteksi tangan. Lihat {out / 'video_detection_coverage.csv'}")
    x = np.asarray(samples, np.float32)
    y = np.asarray([r["label_index"] for r in examples], np.int32)
    indices = {s: np.asarray([i for i, r in enumerate(examples) if r["split"] == s], np.int32)
               for s in ("train", "validation", "test")}
    for split, idx in indices.items():
        missing_classes = set(range(3)) - set(y[idx].tolist())
        if missing_classes:
            raise RuntimeError(
                f"Split {split} tidak mempunyai sequence untuk {[LABELS[i] for i in missing_classes]}. "
                "Periksa coverage deteksi, jumlah group sesi, dan rasio split. Jangan memindahkan test ke train."
            )
    _plot_paths(x, examples, out)
    # Save numeric features separately from raw timestamped cache so experiment
    # evidence remains reusable without parsing the videos a second time.
    np.savez_compressed(out / "sequence_features_and_labels.npz", x=x, y=y,
                        split=np.asarray([r["split"] for r in examples]),
                        synthetic=np.asarray([r["synthetic"] for r in examples], np.bool_))

    batch_size = min(int(cfg.get("batch_size", 256)), len(indices["train"]))

    class AugmentedSequences(tf.keras.utils.Sequence):
        def __init__(self):
            super().__init__()
            self.rng = np.random.default_rng(seed)
            self.order = indices["train"].copy()
            self.rng.shuffle(self.order)

        def __len__(self):
            return math.ceil(len(self.order) / batch_size)

        def __getitem__(self, item):
            selected = self.order[item * batch_size:(item + 1) * batch_size]
            return np.asarray([_augment_sequence(x[j], self.rng) for j in selected]), y[selected]

        def on_epoch_end(self):
            self.rng.shuffle(self.order)

    train_counts = Counter(y[indices["train"]].tolist())
    class_weight = {c: len(indices["train"]) / (3 * train_counts[c]) for c in range(3)}
    model = _build_model(cfg)
    summary_lines = []
    model.summary(print_fn=lambda line, **kwargs: summary_lines.append(line))
    (out / "model_architecture.txt").write_text("\n".join(summary_lines), encoding="utf-8")
    json_write(out / "training_configuration.json", {
        "seed": seed, "split_seed": int(cfg.get("split_seed", 2026)),
        "epochs_max": int(cfg.get("dynamic_epochs", 60)), "batch_size": batch_size,
        "learning_rate": float(cfg.get("learning_rate", 0.001)),
        "class_weight": class_weight, "parameter_count": int(model.count_params()),
        "training_augmentation_only": ["monotonic time warp", "whole-clip small rotation",
                                       "whole-clip x mirroring", "small scale/jitter"],
        "synthetic_other": "one held endpoint per accepted J/Z source, same parent split",
        "tensorflow_version": tf.__version__, "numpy_version": np.__version__,
        "selection": "minimum validation loss; no test-based architecture/seed selection",
    })
    checkpoint = model_dir / "best_model.keras"
    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(str(checkpoint), monitor="val_loss", save_best_only=True),
        tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=12, restore_best_weights=True),
        tf.keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=5, min_lr=1e-6),
        tf.keras.callbacks.CSVLogger(str(out / "training_history.csv")),
        tf.keras.callbacks.TerminateOnNaN(),
    ]
    validation_idx = indices["validation"]
    history_obj = model.fit(AugmentedSequences(), validation_data=(x[validation_idx], y[validation_idx]),
                            epochs=int(cfg.get("dynamic_epochs", 60)), class_weight=class_weight,
                            callbacks=callbacks, verbose=2)
    history = {k: [float(v) for v in values] for k, values in history_obj.history.items()}
    if not checkpoint.is_file() or not history.get("val_loss"):
        raise RuntimeError("Training dinamis tidak menghasilkan checkpoint validation yang valid.")
    model = tf.keras.models.load_model(checkpoint)
    best_epoch = int(np.argmin(history["val_loss"])) + 1
    json_write(out / "training_history.json", history)
    _plot_training(history, out, best_epoch)

    # Export parity is inspected on VALIDATION. Conversion must not choose or
    # tune a model using the held-out test labels.
    export = export_tflite(
        model, model_dir, "model", x[indices["train"][:128]],
        x[validation_idx[:128]], y[validation_idx[:128]],
    )
    test_idx = indices["test"]
    test_scores = model.predict(x[test_idx], batch_size=batch_size, verbose=0)
    metrics_all = classification_report_artifacts(y[test_idx], test_scores, LABELS, out, "test_with_synthetic_idle")
    real_mask = np.asarray([not examples[i]["synthetic"] for i in test_idx])
    synthetic_mask = ~real_mask
    metrics_real = classification_report_artifacts(y[test_idx][real_mask], test_scores[real_mask],
                                                  LABELS, out, "test_real_source_videos")
    # A source-only split may have no real OTHER examples. Report J/Z macro
    # metrics over those two supported positive classes explicitly rather than
    # quietly treating the absent third class as evidence of rejection quality.
    from sklearn.metrics import precision_recall_fscore_support

    positive_mask = real_mask & (y[test_idx] < 2)
    positive_true = y[test_idx][positive_mask]
    positive_predicted = np.argmax(test_scores[positive_mask], axis=1)
    precision_jz, recall_jz, f1_jz, _ = precision_recall_fscore_support(
        positive_true, positive_predicted, labels=[0, 1], average="macro", zero_division=0)
    metrics_positive = {
        "samples": int(positive_mask.sum()),
        "accuracy": float(np.mean(positive_predicted == positive_true)),
        "macro_precision_JZ": float(precision_jz),
        "macro_recall_JZ": float(recall_jz),
        "macro_f1_JZ": float(f1_jz),
        "OTHER_predictions_count_as_incorrect": True,
        "scope": "detected, original J/Z videos only; does not measure real negative rejection",
    }
    json_write(out / "test_JZ_positive_metrics.json", metrics_positive)
    if synthetic_mask.any():
        metrics_synthetic = classification_report_artifacts(y[test_idx][synthetic_mask], test_scores[synthetic_mask],
                                                           LABELS, out, "test_synthetic_idle_only")
    else:
        metrics_synthetic = None
    confidence_threshold = float(cfg.get("min_confidence", 0.60))
    test_predictions = []
    for i, score in zip(test_idx, test_scores):
        label_i = int(np.argmax(score))
        confidence = float(score[label_i])
        test_predictions.append({**examples[i], "predicted": LABELS[label_i],
                                 "confidence": confidence, "correct": bool(label_i == y[i]),
                                 "accepted_at_configured_threshold": bool(confidence >= confidence_threshold),
                                 **{"score_" + label: float(score[j]) for j, label in enumerate(LABELS)}})
    write_csv(out / "test_predictions.csv", test_predictions)
    # Count detector failures as unsuccessful pipeline outcomes instead of
    # silently reporting only the easier videos where a hand was found.
    original_test = [r for r in coverage if r["split"] == "test"]
    original_predictions = [r for r in test_predictions if not r["synthetic"]]
    real_negative_test = [r for r in original_test if r["label"] == "OTHER"]
    real_negative_predictions = [r for r in original_predictions if r["label"] == "OTHER"]
    correct_source = sum(p["correct"] for p in original_predictions)
    source_coverage = len(original_predictions) / len(original_test) if original_test else 0.0
    real_negative_false_trigger_rate = (
        sum(p["predicted"] in {"J", "Z"} and p["accepted_at_configured_threshold"] for p in real_negative_predictions)
        / len(real_negative_predictions) if real_negative_predictions else None
    )
    confidence_accepted = [p for p in original_predictions if p["accepted_at_configured_threshold"]]
    target = float(cfg.get("target_dynamic_accuracy", 0.995))
    measured_accuracy = float(np.mean(np.argmax(test_scores, axis=1) == y[test_idx]))
    qualified_accuracy = correct_source / len(original_test) if original_test else 0.0
    readiness = (
        "PROVISIONAL_REQUIRES_REAL_NEGATIVE_AND_PHONE_TESTS"
        if not real_negative_predictions else "RESEARCH_EVALUATED_REQUIRES_PHONE_AND_UNSEEN_SIGNER_TESTS"
    )
    report = {
        "task": "temporal_J_Z_OTHER", "architecture": "GRU64_Dense32",
        "parameter_count": int(model.count_params()), "seed": seed,
        "best_epoch": best_epoch, "epochs_completed": len(history["loss"]),
        "best_validation_loss": float(min(history["val_loss"])),
        "dataset": source_info,
        "source_video_coverage": coverage_summary,
        "test_with_synthetic_idle": metrics_all,
        "test_real_source_videos_detected_only": metrics_real,
        "test_JZ_positive_videos_detected_only": metrics_positive,
        "three_class_macro_note": (
            "Reports using all three labels assign zero precision/recall/F1 to an absent class. "
            "Use test_JZ_positive_videos_detected_only for J/Z-only macro scores, and separate "
            "real_negative_false_JZ_trigger_rate_at_threshold for recorded negative rejection."
        ),
        "test_synthetic_idle_only": metrics_synthetic,
        "test_original_video_count": len(original_test),
        "test_original_video_detection_coverage": source_coverage,
        "test_original_video_accuracy_with_detection_failures_as_incorrect": qualified_accuracy,
        "confidence_threshold": confidence_threshold,
        "test_source_decision_coverage_at_threshold": len(confidence_accepted) / len(original_test) if original_test else 0.0,
        "test_source_accuracy_among_confident_detected_decisions":
            sum(p["correct"] for p in confidence_accepted) / len(confidence_accepted) if confidence_accepted else None,
        "real_negative_test_original_videos": len(real_negative_test),
        "real_negative_test_detected_videos": len(real_negative_predictions),
        "real_negative_false_JZ_trigger_rate_at_threshold": real_negative_false_trigger_rate,
        "target_accuracy": target,
        "target_met_on_test_with_synthetic_idle": measured_accuracy >= target,
        "target_met_on_original_test_counting_detection_failures": qualified_accuracy >= target,
        "target_does_not_establish_mobile_readiness": True,
        "mobile_ready": False,
        "readiness": readiness,
        "synthetic_other_warning": (
            "Synthetic held poses only teach idle rejection. They are not evidence of rejection of "
            "real unrelated movements, transitions, occlusions, or empty camera frames. "
            "Record held-out real negatives and unseen users/sessions before mobile integration."
        ),
        "tflite": export,
        "preprocessing_contract": str(out / "preprocessing_contract.json"),
        "best_model_path": str(checkpoint),
        "no_application_changes": True,
        "limitations": [
            "No guaranteed 99.5% or 100%; targets are reported after one final test.",
            "Public SigNN signer IDs unavailable, so this is not a signer-independent benchmark.",
            "Clip-level training is not a full streaming gesture start/end detector.",
            "Single still images cannot establish the temporal motion of J/Z.",
            "Live sampling and arbitration with the static 24-letter CNN remain future implementation work.",
            "The supplied .task model is pretrained MediaPipe; this workflow trains the new GRU, not MediaPipe.",
        ],
    }
    json_write(out / "evaluation.json", report)
    card = f"""# Model card: temporal J / Z / OTHER

This is a separate research model, not a replacement for the 24-letter CNN.

Training: GRU64, fixed {contract['sequence_length']} x 64 landmark inputs, seed {seed}.
Source: {source_info['source_url']}. Unique source videos: {source_info['unique_videos']}.
Best checkpoint: epoch {best_epoch}, selected by validation loss only.
Final test accuracy including synthetic idle examples: {100 * measured_accuracy:.3f}%.
Original-video accuracy counting hand detection failures as unsuccessful: {100 * qualified_accuracy:.3f}%.
Original test hand detection coverage: {100 * source_coverage:.3f}%.
Real recorded OTHER clips in the final test: {len(real_negative_test)}.
Status: {readiness}. Mobile ready: false.

The OTHER class includes synthetic held-pose surrogates, explicitly marked in every
manifest. A high aggregate score on these surrogates does not prove that unrelated
real movement will be rejected. Real negative clips are optional input; record
them under negative_videos/person_session/ before a final deployment experiment.
Do not put J or Z in those folders. Group all recordings of one person in one
folder for stricter held-out-user negative testing.

All originals are split before augmentation. Exact duplicate video bytes are
removed. The public positive clips have no verified signer IDs, so different
recordings of the same signer can still cross splits. No signer-independent
accuracy is claimed. Detection failures and per-class coverage are retained.

Wrist translation is preserved: one fixed anchor and palm scale are applied to
the entire clip. Do not normalize each video frame around its own wrist. Read
preprocessing_contract.json before implementing inference. The feature extractor
uses unmirrored RGB, actual frame timestamps, MediaPipe VIDEO mode, short-gap
interpolation with a presence feature, and no automatic gesture trimming.

Saved evidence includes provenance hashes, original/synthetic split manifests,
timestamped extraction caches on Drive, per-video detection failures, feature
arrays, training history, architecture, checkpoint, TFLite exports/parity,
confusion matrices and per-class reports, and per-video final predictions.
No inference integration or app installation is performed by this script.
"""
    (out / "model_card.md").write_text(card, encoding="utf-8")
    print(f"[J/Z] Selesai. Test gabungan (termasuk idle sintetis): {100 * measured_accuracy:.3f}%")
    print(f"[J/Z] Coverage video uji asli: {100 * source_coverage:.3f}%. Status: {readiness}")
    print(f"[J/Z] Bukti dan model: {out}")
    return report
