"""Export the selected, trusted joblib to a compact Flutter asset."""
import gzip
import hashlib
from pathlib import Path
import struct

import joblib
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "training/SVM_HOG_FINAL_AUGMENTED/model_svm_hog_augmented_C100_gamma_scale.joblib"
SHA256 = "9c7995850bff5283b7f1ad0d6c0509a2fe64ea4762be4146ab14704e84820821"
ASSET = ROOT / "assets/models/svm_hog.bin.gz"


def main():
    with MODEL.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != SHA256:
            raise ValueError("Unexpected Joblib checksum")
    pipeline = joblib.load(MODEL)
    scaler, svm = pipeline["scaler"], pipeline["svm"]
    count, width = svm.support_vectors_.shape
    if (width, svm.kernel, svm.C, svm.gamma) != (1764, "rbf", 100, "scale"):
        raise ValueError("Unexpected SVM configuration")

    ASSET.parent.mkdir(parents=True, exist_ok=True)
    with ASSET.open("wb") as raw, gzip.GzipFile(
        filename="", fileobj=raw, mode="wb", compresslevel=3, mtime=0
    ) as output:
        output.write(struct.pack("<4sIIId", b"SHG1", width, count, len(svm.classes_), svm._gamma))
        for array in (svm.classes_, svm.n_support_):
            output.write(np.asarray(array, dtype="<i4").tobytes())
        for array in (scaler.mean_, scaler.scale_, svm.intercept_, svm.dual_coef_, svm.support_vectors_):
            output.write(np.asarray(array, dtype="<f4").tobytes())
    print(f"{ASSET}: {ASSET.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
