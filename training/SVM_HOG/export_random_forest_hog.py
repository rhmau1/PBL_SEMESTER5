#!/usr/bin/env python3
"""Export a trusted scikit-learn RandomForestClassifier to the Flutter RFH1 format."""

import argparse
import gzip
import pathlib
import struct

import joblib
import numpy as np
from sklearn.ensemble import RandomForestClassifier


EXPECTED_CLASSES = np.array([*range(9), *range(10, 25)], dtype=np.int64)
FEATURE_COUNT = 1764


def _write_array(stream, values, dtype):
    stream.write(np.asarray(values, dtype=dtype, order="C").tobytes())


def export_model(source, destination):
    model = joblib.load(source)
    if type(model) is not RandomForestClassifier:
        raise TypeError("Model harus berupa RandomForestClassifier tanpa pipeline.")
    if model.n_features_in_ != FEATURE_COUNT:
        raise ValueError(f"Model harus memiliki {FEATURE_COUNT} fitur HOG.")
    if not np.array_equal(model.classes_, EXPECTED_CLASSES):
        raise ValueError("Urutan kelas model harus berupa A-Y tanpa J.")
    if not model.estimators_:
        raise ValueError("Model tidak memiliki pohon.")

    destination = pathlib.Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as raw:
        with gzip.GzipFile(
            fileobj=raw,
            mode="wb",
            compresslevel=9,
            mtime=0,
        ) as stream:
            stream.write(b"RFH1")
            stream.write(
                struct.pack(
                    "<IIII",
                    1,
                    FEATURE_COUNT,
                    len(EXPECTED_CLASSES),
                    len(model.estimators_),
                )
            )
            _write_array(stream, model.classes_, "<i4")

            for estimator in model.estimators_:
                tree = estimator.tree_
                left = np.asarray(tree.children_left, dtype=np.int32)
                right = np.asarray(tree.children_right, dtype=np.int32)
                feature = np.asarray(tree.feature, dtype=np.int32)
                threshold = np.asarray(tree.threshold, dtype="<f8")
                leaf_mask = left == -1
                if not np.array_equal(leaf_mask, right == -1):
                    raise ValueError("Model memiliki daun yang tidak valid.")
                if np.any((~leaf_mask) & ((feature < 0) | (feature >= FEATURE_COUNT))):
                    raise ValueError("Indeks fitur pohon berada di luar rentang HOG.")

                leaf_indices = np.full(tree.node_count, -1, dtype=np.int32)
                leaf_indices[leaf_mask] = np.arange(
                    int(np.count_nonzero(leaf_mask)),
                    dtype=np.int32,
                )
                values = np.asarray(
                    tree.value[leaf_mask, 0, :],
                    dtype="<f8",
                    order="C",
                )
                if values.shape != (
                    int(np.count_nonzero(leaf_mask)),
                    len(EXPECTED_CLASSES),
                ):
                    raise ValueError("Dimensi nilai daun model tidak sesuai.")

                stream.write(
                    struct.pack(
                        "<II",
                        tree.node_count,
                        int(np.count_nonzero(leaf_mask)),
                    )
                )
                _write_array(stream, left, "<i4")
                _write_array(stream, right, "<i4")
                _write_array(stream, feature, "<i4")
                _write_array(stream, threshold, "<f8")
                _write_array(stream, leaf_indices, "<i4")
                _write_array(stream, values, "<f8")

    print(
        f"Exported {len(model.estimators_)} trees "
        f"({FEATURE_COUNT} features) to {destination} "
        f"({destination.stat().st_size} bytes)."
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    export_model(args.source, args.destination)


if __name__ == "__main__":
    main()
