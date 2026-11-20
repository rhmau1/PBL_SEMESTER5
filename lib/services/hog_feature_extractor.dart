import 'dart:math' as math;
import 'dart:typed_data';

class HogFeatureExtractor {
  static const featureCount = 1764;

  static Float32List extract(Uint8List pixels) {
    const size = 64, cells = 8, bins = 9;
    if (pixels.length != size * size) {
      throw ArgumentError('Gambar HOG harus 64x64.');
    }
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
