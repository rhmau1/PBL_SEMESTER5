import 'dart:io';
import 'dart:typed_data';

import 'hog_feature_extractor.dart';

class RandomForestHogModel {
  RandomForestHogModel(Uint8List asset) {
    final bytes = gzip.decode(asset) as Uint8List;
    if (bytes.length < 120 ||
        bytes[0] != 0x52 ||
        bytes[1] != 0x46 ||
        bytes[2] != 0x48 ||
        bytes[3] != 0x31) {
      throw const FormatException('Aset Random Forest HOG tidak valid.');
    }
    final data = ByteData.sublistView(bytes);
    var offset = 4;

    int nextInt() {
      if (offset + 4 > data.lengthInBytes) {
        throw const FormatException('Aset Random Forest HOG terpotong.');
      }
      final result = data.getInt32(offset, Endian.little);
      offset += 4;
      return result;
    }

    double nextDouble() {
      if (offset + 8 > data.lengthInBytes) {
        throw const FormatException('Aset Random Forest HOG terpotong.');
      }
      final result = data.getFloat64(offset, Endian.little);
      offset += 8;
      return result;
    }

    if (nextInt() != 1) {
      throw const FormatException(
        'Versi aset Random Forest HOG tidak didukung.',
      );
    }
    final featureCount = nextInt();
    final classCount = nextInt();
    final treeCount = nextInt();
    if (featureCount != HogFeatureExtractor.featureCount ||
        classCount != _expectedClasses.length ||
        treeCount < 1 ||
        treeCount > 10000) {
      throw const FormatException(
        'Dimensi aset Random Forest HOG tidak sesuai.',
      );
    }
    _classes = Int32List(classCount);
    for (var i = 0; i < classCount; i++) {
      _classes[i] = nextInt();
      if (_classes[i] != _expectedClasses[i]) {
        throw const FormatException(
          'Urutan kelas aset Random Forest HOG tidak sesuai.',
        );
      }
    }
    _trees = List.generate(treeCount, (_) {
      final nodeCount = nextInt();
      final leafCount = nextInt();
      if (nodeCount < 1 ||
          nodeCount > 1000000 ||
          leafCount < 1 ||
          leafCount > nodeCount) {
        throw const FormatException('Pohon Random Forest HOG tidak valid.');
      }

      final left = Int32List(nodeCount);
      final right = Int32List(nodeCount);
      final features = Int32List(nodeCount);
      for (var i = 0; i < nodeCount; i++) {
        left[i] = nextInt();
      }
      for (var i = 0; i < nodeCount; i++) {
        right[i] = nextInt();
      }
      for (var i = 0; i < nodeCount; i++) {
        features[i] = nextInt();
      }
      final thresholds = Float64List(nodeCount);
      for (var i = 0; i < nodeCount; i++) {
        thresholds[i] = nextDouble();
      }
      final leafIndices = Int32List(nodeCount);
      final seenLeaves = List<bool>.filled(leafCount, false);
      var foundLeaves = 0;
      for (var i = 0; i < nodeCount; i++) {
        final leafIndex = nextInt();
        leafIndices[i] = leafIndex;
        if (left[i] == -1 && right[i] == -1) {
          if (leafIndex < 0 ||
              leafIndex >= leafCount ||
              seenLeaves[leafIndex] ||
              features[i] != -2) {
            throw const FormatException(
              'Daun pohon Random Forest tidak valid.',
            );
          }
          seenLeaves[leafIndex] = true;
          foundLeaves++;
        } else if (left[i] < 0 ||
            right[i] < 0 ||
            left[i] >= nodeCount ||
            right[i] >= nodeCount ||
            leafIndex != -1 ||
            features[i] < 0 ||
            features[i] >= featureCount ||
            !thresholds[i].isFinite) {
          throw const FormatException(
            'Simpul pohon Random Forest tidak valid.',
          );
        }
      }
      if (foundLeaves != leafCount || seenLeaves.contains(false)) {
        throw const FormatException(
          'Jumlah daun pohon Random Forest tidak sesuai.',
        );
      }

      final values = Float64List(leafCount * classCount);
      for (var i = 0; i < values.length; i++) {
        values[i] = nextDouble();
        if (!values[i].isFinite || values[i] < 0) {
          throw const FormatException('Nilai daun Random Forest tidak valid.');
        }
      }
      return _RandomForestTree(
        left: left,
        right: right,
        features: features,
        thresholds: thresholds,
        leafIndices: leafIndices,
        values: values,
      );
    }, growable: false);
    if (offset != data.lengthInBytes) {
      throw const FormatException(
        'Aset Random Forest HOG memiliki data ekstra.',
      );
    }
  }

  static const _expectedClasses = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
  ];

  late final Int32List _classes;
  late final List<_RandomForestTree> _trees;

  ({String label, List<double> scores, bool accepted}) predictCrops(
    List<Uint8List> crops,
  ) {
    if (crops.length != 2 && crops.length != 4 && crops.length != 5) {
      throw ArgumentError.value(crops.length, 'crops.length');
    }
    if (crops.length > 2) {
      final inverted = predict(HogFeatureExtractor.extract(crops[1]));
      final finer = predict(HogFeatureExtractor.extract(crops[2]));
      if (inverted.label == finer.label) {
        return (label: finer.label, scores: finer.scores, accepted: true);
      }
      final tight = predict(HogFeatureExtractor.extract(crops.first));
      final wide = predict(HogFeatureExtractor.extract(crops.last));
      final accepted = tight.label == wide.label;
      if (accepted && crops.length == 5 && finer.label != tight.label) {
        final direct = predict(HogFeatureExtractor.extract(crops[3]));
        if (direct.label == finer.label) {
          return (label: finer.label, scores: direct.scores, accepted: true);
        }
      }
      return (label: tight.label, scores: tight.scores, accepted: accepted);
    }
    final tight = predict(HogFeatureExtractor.extract(crops.first));
    final wide = predict(HogFeatureExtractor.extract(crops.last));
    return (
      label: tight.label,
      scores: tight.scores,
      accepted: tight.label == wide.label,
    );
  }

  ({String label, List<double> scores}) predict(Float32List features) {
    if (features.length != HogFeatureExtractor.featureCount) {
      throw ArgumentError.value(features.length, 'features');
    }
    final scores = Float64List(_classes.length);
    for (final tree in _trees) {
      var node = 0;
      var steps = 0;
      while (tree.left[node] != -1) {
        if (++steps > tree.left.length) {
          throw StateError('Siklus ditemukan pada pohon Random Forest.');
        }
        final feature = tree.features[node];
        node = features[feature] <= tree.thresholds[node]
            ? tree.left[node]
            : tree.right[node];
      }
      final leafOffset = tree.leafIndices[node] * _classes.length;
      for (var i = 0; i < scores.length; i++) {
        scores[i] += tree.values[leafOffset + i];
      }
    }
    var winner = 0;
    for (var i = 0; i < scores.length; i++) {
      scores[i] /= _trees.length;
      if (scores[i] > scores[winner]) winner = i;
    }
    return (label: String.fromCharCode(65 + _classes[winner]), scores: scores);
  }
}

class _RandomForestTree {
  const _RandomForestTree({
    required this.left,
    required this.right,
    required this.features,
    required this.thresholds,
    required this.leafIndices,
    required this.values,
  });

  final Int32List left;
  final Int32List right;
  final Int32List features;
  final Float64List thresholds;
  final Int32List leafIndices;
  final Float64List values;
}
