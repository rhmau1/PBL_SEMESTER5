import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class SvmHogModel {
  SvmHogModel(Uint8List asset) {
    final bytes = gzip.decode(asset) as Uint8List;
    final header = ByteData.sublistView(bytes);
    if (bytes.length < 24 || header.getUint32(0, Endian.big) != 0x53484731) {
      throw const FormatException('Aset SVM tidak valid.');
    }
    final width = header.getUint32(4, Endian.little);
    final count = header.getUint32(8, Endian.little);
    final classes = header.getUint32(12, Endian.little);
    if (width != featureCount || count != 10446 || classes != 24) {
      throw const FormatException('Dimensi aset SVM tidak sesuai.');
    }
    final pairs = classes * (classes - 1) ~/ 2;
    if (bytes.length !=
        24 +
            4 *
                (2 * classes +
                    2 * width +
                    pairs +
                    (classes - 1 + width) * count)) {
      throw const FormatException('Ukuran aset SVM tidak sesuai.');
    }
    _gamma = header.getFloat64(16, Endian.little);
    var offset = 24;
    int nextInt() {
      final value = header.getInt32(offset, Endian.little);
      offset += 4;
      return value;
    }

    _labels = List.generate(
      classes,
      (_) => String.fromCharCode(65 + nextInt()),
    );
    if (_labels.join() != 'ABCDEFGHIKLMNOPQRSTUVWXY') {
      throw const FormatException('Urutan kelas aset SVM tidak sesuai.');
    }
    _starts = [0];
    for (var i = 0; i < classes; i++) {
      final size = nextInt();
      if (size < 1) throw const FormatException('Kelas SVM kosong.');
      _starts.add(_starts.last + size);
    }
    if (_starts.last != count || !_gamma.isFinite || _gamma <= 0) {
      throw const FormatException('Parameter aset SVM tidak sesuai.');
    }

    Float32List nextFloats(int length) {
      final result = Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes + offset,
        length,
      );
      offset += length * 4;
      return result;
    }

    _mean = nextFloats(width);
    _scale = nextFloats(width);
    _intercepts = nextFloats(pairs);
    _coefficients = nextFloats((classes - 1) * count);
    _vectors = nextFloats(width * count);
  }

  static const featureCount = 1764;
  late final double _gamma;
  late final List<String> _labels;
  late final List<int> _starts;
  late final Float32List _mean, _scale, _intercepts, _coefficients, _vectors;

  ({String label, List<double> scores}) predict(Float32List features) {
    if (features.length != featureCount) {
      throw ArgumentError.value(features.length, 'features');
    }
    final input = Float32List(featureCount);
    for (var j = 0; j < input.length; j++) {
      input[j] = (features[j] - _mean[j]) / _scale[j];
    }
    final count = _starts.last;
    final kernels = Float64List(count);
    var vectorOffset = 0;
    for (var i = 0; i < count; i++) {
      var distance = 0.0;
      for (var j = 0; j < input.length; j++) {
        final difference = input[j] - _vectors[vectorOffset++];
        distance += difference * difference;
      }
      kernels[i] = math.exp(-_gamma * distance);
    }

    // LIBSVM stores coefficients for the i/j classifier in rows j-1 and i.
    final votes = Int32List(_labels.length);
    final margins = Float64List(_labels.length);
    var pair = 0;
    for (var i = 0; i < _labels.length; i++) {
      for (var j = i + 1; j < _labels.length; j++) {
        var margin = _intercepts[pair++];
        for (var k = _starts[i]; k < _starts[i + 1]; k++) {
          margin += _coefficients[(j - 1) * count + k] * kernels[k];
        }
        for (var k = _starts[j]; k < _starts[j + 1]; k++) {
          margin += _coefficients[i * count + k] * kernels[k];
        }
        votes[margin > 0 ? i : j]++;
        margins[i] += margin;
        margins[j] -= margin;
      }
    }
    var winner = 0;
    for (var i = 1; i < votes.length; i++) {
      if (votes[i] > votes[winner]) winner = i;
    }
    final scores = List.generate(votes.length, (i) {
      final margin = margins[i];
      return votes[i] + margin / (3 * (margin.abs() + 1));
    });
    return (label: _labels[winner], scores: scores);
  }

  // skimage HOG: signed central differences, unsigned angles, and L2-Hys.
  static Float32List hog(Uint8List pixels) {
    const size = 64, cells = 8, bins = 9;
    if (pixels.length != size * size)
      throw ArgumentError('Gambar HOG harus 64x64.');
    final values = Float32List.fromList(
      pixels.map((pixel) => math.sqrt(pixel / 255)).toList(),
    );
    final histogram = Float32List(cells * cells * bins);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final index = y * size + x;
        final dx = x == 0 || x == size - 1
            ? 0.0
            : values[index + 1] - values[index - 1];
        final dy = y == 0 || y == size - 1
            ? 0.0
            : values[index + size] - values[index - size];
        final angle = (math.atan2(dy, dx) * 180 / math.pi) % 180;
        final bin = (angle / 20).floor();
        histogram[((y ~/ 8) * cells + x ~/ 8) * bins + bin] += math.sqrt(
          dx * dx + dy * dy,
        );
      }
    }
    final features = Float32List(featureCount);
    var output = 0;
    final block = Float32List(4 * bins);
    for (var y = 0; y < cells - 1; y++) {
      for (var x = 0; x < cells - 1; x++) {
        var index = 0;
        var norm = 0.0;
        for (var dy = 0; dy < 2; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            for (var bin = 0; bin < bins; bin++) {
              final value =
                  histogram[((y + dy) * cells + x + dx) * bins + bin] / 64;
              block[index++] = value;
              norm += value * value;
            }
          }
        }
        final denominator = math.sqrt(norm + 1e-10);
        norm = 0;
        for (var j = 0; j < block.length; j++) {
          final value = math.min(0.2, block[j] / denominator);
          block[j] = value;
          norm += value * value;
        }
        final clippedDenominator = math.sqrt(norm + 1e-10);
        for (final value in block) {
          features[output++] = value / clippedDenominator;
        }
      }
    }
    return features;
  }
}
