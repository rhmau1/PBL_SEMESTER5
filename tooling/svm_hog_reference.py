"""Generate an inference parity fixture using local Sign Language MNIST evidence."""
import argparse
import json
from pathlib import Path
import sys

import joblib
import numpy as np

from export_svm_hog import MODEL, ROOT

sys.path.insert(0, str(ROOT / "training/SVM_HOG"))
from train_svm_hog import hog_features, preprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    config = json.loads((args.run / "config.json").read_text(encoding="utf-8"))
    pipeline = joblib.load(MODEL)
    cases = []
    for sample in sorted((args.run / "evidence/official_test").glob("*/01_original.png")):
        pixels = preprocess(sample, config)["normalized"]
        features = hog_features(pixels, config).astype(np.float32)
        cases.append({
            "name": sample.parent.name,
            "label": chr(65 + int(pipeline.predict([features])[0])),
            "scores": pipeline.decision_function([features])[0].tolist(),
            "pixels": bytes(pixels).hex(),
        })
    if len(cases) < 24:
        raise ValueError("Expected evidence for at least 24 images.")
    args.output.write_text(json.dumps(cases, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{len(cases)} reference predictions")


if __name__ == "__main__":
    main()
