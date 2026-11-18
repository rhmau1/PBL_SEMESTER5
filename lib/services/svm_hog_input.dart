import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Prepare a grayscale hand crop for the 28x28 -> 64x64 training pipeline.
/// Foreground segmentation assumes a plain background and one visible object.
class SvmHogInput {
  static img.Image? decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    return decoded == null ? null : img.bakeOrientation(decoded);
  }

  static img.Image? fromLuma(
    Uint8List bytes,
    int width,
    int height,
    int stride,
    int pixelStride,
    int rotation,
  ) {
    if (width < 1 ||
        height < 1 ||
        pixelStride < 1 ||
        stride < (width - 1) * pixelStride + 1 ||
        bytes.length <= (height - 1) * stride + (width - 1) * pixelStride ||
        !const [0, 90, 180, 270].contains(rotation)) {
      return null;
    }
    final sample = math.max(1, (math.max(width, height) / 384).ceil());
    final source = img.Image(
      width: (width + sample - 1) ~/ sample,
      height: (height + sample - 1) ~/ sample,
      numChannels: 1,
    );
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelR(
          x,
          y,
          bytes[y * sample * stride + x * sample * pixelStride],
        );
      }
    }
    return rotation == 0 ? source : img.copyRotate(source, angle: rotation);
  }

  static ({List<Uint8List> crops, String? rejection}) prepareHandCrops(
    img.Image image, {
    bool tightFraming = true,
    bool includePhotoChecks = false,
    bool correctUnevenLighting = true,
  }) {
    if (math.min(image.width, image.height) < 28) {
      return (crops: [], rejection: 'Resolusi foto terlalu kecil.');
    }
    final longest = math.max(image.width, image.height);
    final ratio = math.min(1.0, 384 / longest);
    final resized = ratio < 1
        ? img.copyResize(
            image,
            width: (image.width * ratio).round(),
            height: (image.height * ratio).round(),
            interpolation: img.Interpolation.average,
          )
        : image;
    final w = resized.width, h = resized.height;
    final band = math.max(1, (math.min(w, h) * 0.05).round());
    final histogram = List<int>.filled(256, 0);
    final gray = Uint8List(w * h);
    var borderCount = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pixel = resized.getPixel(x, y);
        final luma = resized.numChannels == 1
            ? pixel.rNormalized
            : 0.299 * pixel.rNormalized +
                  0.587 * pixel.gNormalized +
                  0.114 * pixel.bNormalized;
        final value = (255 * luma).round().clamp(0, 255);
        gray[y * w + x] = value;
        if (x < band || x >= w - band || y < band || y >= h - band) {
          histogram[value]++;
          borderCount++;
        }
      }
    }
    int percentile(double fraction) {
      var sum = 0;
      for (var i = 0; i < histogram.length; i++) {
        sum += histogram[i];
        if (sum >= borderCount * fraction) return i;
      }
      return 255;
    }

    final background = percentile(0.5);
    final spread = percentile(0.9) - percentile(0.1);
    if (spread > 55) {
      if (!includePhotoChecks ||
          !correctUnevenLighting ||
          !_flattenLighting(gray, w, h, band, background)) {
        return (
          crops: [],
          rejection: 'Tepi foto terlalu bervariasi. Gunakan latar polos.',
        );
      }
    }
    final threshold = spread > 55 ? 18 : math.max(18, (spread * 1.25).round());
    final mask = Uint8List(gray.length);
    for (var i = 0; i < gray.length; i++) {
      if ((gray[i] - background).abs() >= threshold) mask[i] = 1;
    }

    // Keep the largest connected component. Ignore isolated noisy pixels.
    final queue = Int32List(mask.length);
    var largest = 0, second = 0;
    var left = w, right = 0, top = h, bottom = 0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0) continue;
      var end = 1;
      queue[0] = i;
      mask[i] = 0;
      var xMin = w, xMax = 0, yMin = h, yMax = 0;
      void visit(int index) {
        if (mask[index] != 0) {
          mask[index] = 0;
          queue[end++] = index;
        }
      }

      for (var head = 0; head < end; head++) {
        final index = queue[head];
        final x = index % w, y = index ~/ w;
        xMin = math.min(x, xMin);
        xMax = math.max(x, xMax);
        yMin = math.min(y, yMin);
        yMax = math.max(y, yMax);
        if (x > 0) visit(index - 1);
        if (x < w - 1) visit(index + 1);
        if (y > 0) visit(index - w);
        if (y < h - 1) visit(index + w);
      }
      if (end > largest) {
        second = largest;
        largest = end;
        left = xMin;
        right = xMax;
        top = yMin;
        bottom = yMax;
      } else {
        second = math.max(second, end);
      }
    }
    final side = math.max(right - left + 1, bottom - top + 1);
    if (largest < w * h * 0.02 || side < 20) {
      return (
        crops: [],
        rejection: 'Area objek terlalu kecil atau kurang kontras.',
      );
    }
    if (largest > w * h * 0.85) {
      return (crops: [], rejection: 'Area objek memenuhi hampir seluruh foto.');
    }
    if (second > largest * 0.35) {
      return (crops: [], rejection: 'Ada beberapa area objek besar.');
    }
    if (left == 0 || right == w - 1 || top == 0 || bottom == h - 1) {
      return (crops: [], rejection: 'Area objek menyentuh tepi foto.');
    }

    // Keep more of the hand in the 28x28 photo input before computing HOG.
    final scales = tightFraming ? const [1.05, 1.12] : const [1.2, 1.4];
    final crops = <Uint8List>[];
    Uint8List resizeForHog(img.Image crop, int size) {
      final small = img.copyResize(
        crop,
        width: size,
        height: size,
        interpolation: img.Interpolation.average,
      );
      final input = img.copyResize(
        small,
        width: 64,
        height: 64,
        interpolation: img.Interpolation.linear,
      );
      return Uint8List.fromList(input.getBytes());
    }

    for (final margin in scales) {
      final size = (side * margin).ceil();
      final x0 = (left + right + 1 - size) ~/ 2;
      final y0 = (top + bottom + 1 - size) ~/ 2;
      final crop = img.Image(width: size, height: size, numChannels: 1);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final sx = x0 + x, sy = y0 + y;
          final value = sx >= 0 && sx < w && sy >= 0 && sy < h
              ? gray[sy * w + sx]
              : background;
          crop.setPixelR(x, y, value);
        }
      }
      final standard = resizeForHog(crop, 28);
      crops.add(standard);
      if (includePhotoChecks && margin == scales.first) {
        crops.add(
          Uint8List.fromList(standard.map((pixel) => 255 - pixel).toList()),
        );
        crops.add(resizeForHog(crop, 40));
      }
    }
    return (crops: crops, rejection: null);
  }

  static bool _flattenLighting(
    Uint8List gray,
    int width,
    int height,
    int band,
    int reference,
  ) {
    int cornerMedian(int x, int y) {
      final patch = <int>[
        for (var dy = 0; dy < band; dy++)
          for (var dx = 0; dx < band; dx++) gray[(y + dy) * width + x + dx],
      ]..sort();
      return patch[patch.length ~/ 2];
    }

    final topLeft = cornerMedian(0, 0);
    final topRight = cornerMedian(width - band, 0);
    final bottomLeft = cornerMedian(0, height - band);
    final bottomRight = cornerMedian(width - band, height - band);
    if ([
      topLeft,
      topRight,
      bottomLeft,
      bottomRight,
    ].any((value) => value < 55)) {
      return false;
    }

    double expected(int x, int y) {
      final fx = (x - (band - 1) / 2) / (width - band);
      final fy = (y - (band - 1) / 2) / (height - band);
      final top = topLeft + fx * (topRight - topLeft);
      final bottom = bottomLeft + fx * (bottomRight - bottomLeft);
      return top + fy * (bottom - top);
    }

    // Treat every side as evidence for the illumination estimate.
    bool edgeMatches({
      required int xStart,
      required int yStart,
      required int xEnd,
      required int yEnd,
    }) {
      var matches = 0;
      for (var y = yStart; y < yEnd; y++) {
        for (var x = xStart; x < xEnd; x++) {
          if ((gray[y * width + x] - expected(x, y)).abs() <= 12) matches++;
        }
      }
      return matches >= (xEnd - xStart) * (yEnd - yStart) * 0.9;
    }

    if (!edgeMatches(xStart: 0, yStart: 0, xEnd: width, yEnd: band) ||
        !edgeMatches(
          xStart: 0,
          yStart: height - band,
          xEnd: width,
          yEnd: height,
        ) ||
        !edgeMatches(xStart: 0, yStart: 0, xEnd: band, yEnd: height) ||
        !edgeMatches(
          xStart: width - band,
          yStart: 0,
          xEnd: width,
          yEnd: height,
        )) {
      return false;
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        final local = expected(x, y).clamp(40.0, 255.0);
        gray[index] = (gray[index] * reference / local).round().clamp(0, 255);
      }
    }
    return true;
  }
}
