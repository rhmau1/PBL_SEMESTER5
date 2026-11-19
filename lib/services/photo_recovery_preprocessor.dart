import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import 'image_preprocessor.dart';

class PhotoRecoveryRequest {
  const PhotoRecoveryRequest(this.image, this.landmarks);

  final img.Image image;
  final List<Offset> landmarks;
}

class PhotoRecoveryInputs {
  const PhotoRecoveryInputs({
    required this.context,
    required this.tight,
    required this.full,
    required this.foregroundBounds,
  });

  final img.Image context;
  final img.Image tight;
  final img.Image full;
  final Rect foregroundBounds;
}

/// Additional still-image views for an inconclusive prediction on a plain
/// background. MediaPipe must already have validated exactly one hand.
class PhotoRecoveryPreprocessor {
  const PhotoRecoveryPreprocessor._();

  static PhotoRecoveryInputs? prepare(PhotoRecoveryRequest request) {
    final image = request.image;
    final points = request.landmarks;
    if (image.width < 28 ||
        image.height < 28 ||
        points.length != 21 ||
        points.any(
          (p) =>
              !p.dx.isFinite ||
              !p.dy.isFinite ||
              p.dx < 0 ||
              p.dx > 1 ||
              p.dy < 0 ||
              p.dy > 1,
        )) {
      return null;
    }
    int luminance(int x, int y) => image.numChannels == 1
        ? image.getPixel(x, y).r.toInt()
        : image.getPixel(x, y).luminance.round();
    final border = <int>[];
    for (var x = 0; x < image.width; x++) {
      border.add(luminance(x, 0));
      border.add(luminance(x, image.height - 1));
    }
    for (var y = 0; y < image.height; y++) {
      border.add(luminance(0, y));
      border.add(luminance(image.width - 1, y));
    }
    border.sort();
    final background =
        (border[(border.length - 1) ~/ 2] + border[border.length ~/ 2]) / 2;
    final deviations = border.map((v) => (v - background).abs()).toList()
      ..sort();
    // A color-contrast box is unsuitable for a room, clothing or a textured
    // background. Do not run that fallback on such images.
    if (deviations[((deviations.length - 1) * .90).ceil()] > 8) return null;

    final width = image.width, height = image.height;
    final gray = Uint8List(width * height);
    final mask = Uint8List(gray.length);
    final threshold = math.max(18.0, .16 * background.abs());
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        final value = luminance(x, y);
        gray[index] = value;
        if ((value - background).abs() > threshold) mask[index] = 1;
      }
    }
    final queue = Uint32List(gray.length);
    var largestArea = 0;
    Rect? foreground;
    for (var start = 0; start < mask.length; start++) {
      if (mask[start] == 0) continue;
      mask[start] = 0;
      var head = 0, tail = 1;
      queue[0] = start;
      var minX = width, minY = height, maxX = 0, maxY = 0;
      while (head < tail) {
        final index = queue[head++];
        final x = index % width, y = index ~/ width;
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
        for (
          var yy = math.max(0, y - 1);
          yy <= math.min(height - 1, y + 1);
          yy++
        ) {
          for (
            var xx = math.max(0, x - 1);
            xx <= math.min(width - 1, x + 1);
            xx++
          ) {
            final neighbor = yy * width + xx;
            if (mask[neighbor] == 0) continue;
            mask[neighbor] = 0;
            queue[tail++] = neighbor;
          }
        }
      }
      if (tail > largestArea) {
        largestArea = tail;
        foreground = Rect.fromLTWH(
          minX.toDouble(),
          minY.toDouble(),
          (maxX - minX + 1).toDouble(),
          (maxY - minY + 1).toDouble(),
        );
      }
    }
    if (foreground == null ||
        largestArea < gray.length * .01 ||
        largestArea > gray.length * .70) {
      return null;
    }
    final tolerance = math.max(foreground.width, foreground.height) * .02;
    final verified = foreground.inflate(tolerance);
    if (points.any(
      (p) => !verified.contains(Offset(p.dx * width, p.dy * height)),
    )) {
      return null;
    }
    // Match the saved notebook's square hand box, including its integer
    // centering. The two views include more wrist context than landmark bounds.
    final boxSide = math.max(foreground.width, foreground.height).toInt();
    final boxX =
        foreground.left.toInt() + foreground.width.toInt() ~/ 2 - boxSide ~/ 2;
    final boxY =
        foreground.top.toInt() + foreground.height.toInt() ~/ 2 - boxSide ~/ 2;
    img.Image crop(double padding, double minimumFraction) {
      final side = (boxSide * padding).clamp(
        math.min(width, height) * minimumFraction,
        math.max(width, height).toDouble(),
      );
      final left = boxX + boxSide / 2 - side / 2;
      final top = boxY + boxSide / 2 - side / 2;
      final output = img.Image(width: 28, height: 28, numChannels: 1);
      // Bilinear affine sampling is a deliberate additional view, not a change
      // to the established grid4 input used by the camera and primary crops.
      for (var y = 0; y < 28; y++) {
        final sy = (top + y * side / 28).clamp(0.0, height - 1.0);
        final y0 = sy.floor(), y1 = math.min(y0 + 1, height - 1);
        final fy = sy - y0;
        for (var x = 0; x < 28; x++) {
          final sx = (left + x * side / 28).clamp(0.0, width - 1.0);
          final x0 = sx.floor(), x1 = math.min(x0 + 1, width - 1);
          final fx = sx - x0;
          final a =
              gray[y0 * width + x0] * (1 - fx) + gray[y0 * width + x1] * fx;
          final b =
              gray[y1 * width + x0] * (1 - fx) + gray[y1 * width + x1] * fx;
          output.setPixelR(x, y, (a * (1 - fy) + b * fy).round().clamp(0, 255));
        }
      }
      return output;
    }

    final fullImage = ImagePreprocessor.toModelImage(image);
    final fullGray = img.Image(width: 28, height: 28, numChannels: 1);
    for (var y = 0; y < 28; y++) {
      for (var x = 0; x < 28; x++) {
        fullGray.setPixelR(
          x,
          y,
          fullImage.numChannels == 1
              ? fullImage.getPixel(x, y).r
              : fullImage.getPixel(x, y).luminance.round(),
        );
      }
    }
    return PhotoRecoveryInputs(
      context: crop(1.6, .28),
      tight: crop(1.4, .22),
      full: fullGray,
      foregroundBounds: foreground,
    );
  }
}
