import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Prepare a grayscale hand crop for the 28x28 -> 64x64 pipeline.
/// Supports:
/// 1. Optional MediaPipe ROI helper (`prepareHandCropFromRoi`) when hand bbox is provided.
/// 2. Tuned contour / skin-color segmentation (`prepareHandCrops`) for diverse backgrounds
///    (filters out beige/wood tables and trims excess wrist/forearm at bottom edge).
class HogImageInput {
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

  /// Direct ROI cropper from normalized MediaPipe coordinates (0.0..1.0).
  static List<Uint8List> prepareHandCropFromNormalizedRoi(
    img.Image image, {
    required double normLeft,
    required double normTop,
    required double normRight,
    required double normBottom,
    bool tightFraming = true,
  }) {
    final w = image.width;
    final h = image.height;
    return prepareHandCropFromRoi(
      image,
      left: (normLeft.clamp(0.0, 1.0) * (w - 1)).round(),
      top: (normTop.clamp(0.0, 1.0) * (h - 1)).round(),
      right: (normRight.clamp(0.0, 1.0) * (w - 1)).round(),
      bottom: (normBottom.clamp(0.0, 1.0) * (h - 1)).round(),
      tightFraming: tightFraming,
    );
  }

  /// Direct ROI cropper when MediaPipe Hands bounding box is already available.
  static List<Uint8List> prepareHandCropFromRoi(
    img.Image image, {
    required int left,
    required int top,
    required int right,
    required int bottom,
    bool tightFraming = true,
  }) {
    final w = image.width, h = image.height;
    final boxL = left.clamp(0, w - 1);
    final boxT = top.clamp(0, h - 1);
    final boxR = right.clamp(boxL, w - 1);
    final boxB = bottom.clamp(boxT, h - 1);
    final side = math.max(boxR - boxL + 1, boxB - boxT + 1);
    final scales = tightFraming ? const [1.05, 1.12] : const [1.2, 1.4];

    final gray = Uint8List(w * h);
    var sum = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pixel = image.getPixel(x, y);
        final v = image.numChannels == 1
            ? (255 * pixel.rNormalized).round().clamp(0, 255)
            : (0.299 * 255 * pixel.rNormalized +
                      0.587 * 255 * pixel.gNormalized +
                      0.114 * 255 * pixel.bNormalized)
                  .round()
                  .clamp(0, 255);
        gray[y * w + x] = v;
        sum += v;
      }
    }
    final fill = (sum / gray.length).round().clamp(0, 255);

    final crops = <Uint8List>[];
    for (final margin in scales) {
      final size = (side * margin).ceil();
      final x0 = (boxL + boxR + 1 - size) ~/ 2;
      final y0 = (boxT + boxB + 1 - size) ~/ 2;
      final crop = img.Image(width: size, height: size, numChannels: 1);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final sx = x0 + x, sy = y0 + y;
          final v = (sx >= 0 && sx < w && sy >= 0 && sy < h)
              ? gray[sy * w + sx]
              : fill;
          crop.setPixelR(x, y, v);
        }
      }
      final small = img.copyResize(
        crop,
        width: 28,
        height: 28,
        interpolation: img.Interpolation.average,
      );
      final input = img.copyResize(
        small,
        width: 64,
        height: 64,
        interpolation: img.Interpolation.linear,
      );
      crops.add(Uint8List.fromList(input.getBytes()));
    }
    return crops;
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
    final hasColor = resized.numChannels >= 3;
    final skinMask = hasColor ? Uint8List(w * h) : null;
    var borderCount = 0;
    var skinCount = 0;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pixel = resized.getPixel(x, y);
        final idx = y * w + x;
        final int value;
        if (!hasColor) {
          value = (255 * pixel.rNormalized).round().clamp(0, 255);
        } else {
          final r = 255.0 * pixel.rNormalized;
          final g = 255.0 * pixel.gNormalized;
          final b = 255.0 * pixel.bNormalized;
          final luma = 0.299 * r + 0.587 * g + 0.114 * b;
          value = luma.round().clamp(0, 255);

          // Combined YCrCb + RGB skin rule to reject beige/wood/gray surfaces
          final cr = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b;
          final cb = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b;
          final maxRgb = math.max(r, math.max(g, b));
          final minRgb = math.min(r, math.min(g, b));
          if (luma >= 40 &&
              cr >= 133 &&
              cr <= 173 &&
              cb >= 77 &&
              cb <= 127 &&
              r > g &&
              r > b &&
              (maxRgb - minRgb) > 15 &&
              (r - g) > 8) {
            skinMask![idx] = 1;
            skinCount++;
          }
        }
        gray[idx] = value;
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

    var lightingFlattened = false;
    if (spread > 55 && includePhotoChecks && correctUnevenLighting) {
      lightingFlattened = _flattenLighting(gray, w, h, band, background);
    }

    _ComponentResult? selected;
    Uint8List? activeMask;
    if (skinMask != null &&
        skinCount >= w * h * 0.015 &&
        skinCount <= w * h * 0.65) {
      final cleaned = _morphCloseOpen(skinMask, w, h);
      final skinComp = _findBestComponent(cleaned, w, h);
      if (skinComp != null &&
          _isValidComponent(skinComp, w, h) &&
          !(skinComp.left == 0 && skinComp.right == w - 1)) {
        selected = skinComp;
        activeMask = cleaned;
      }
    }

    if (selected == null) {
      final threshold = (spread > 55 && !lightingFlattened)
          ? _otsuThreshold(gray)
          : math.max(18, (spread * 1.25).round());

      final contrastMask = Uint8List(gray.length);
      final deltaTh = (spread > 55 && !lightingFlattened)
          ? math.max(20, (threshold * 0.35).round())
          : threshold;
      for (var i = 0; i < gray.length; i++) {
        if ((gray[i] - background).abs() >= deltaTh) {
          contrastMask[i] = 1;
        }
      }

      final cleanedContrast = _morphCloseOpen(contrastMask, w, h);
      final contrastComp = _findBestComponent(cleanedContrast, w, h);
      if (contrastComp != null && _isValidComponent(contrastComp, w, h)) {
        selected = contrastComp;
        activeMask = cleanedContrast;
      }
    }

    if (selected == null || activeMask == null) {
      return (
        crops: [],
        rejection: 'Area tangan tidak terdeteksi dengan jelas.',
      );
    }

    final fgMask = _extractComponentMask(activeMask, w, h, selected.seedIndex);
    final dilatedFg = _dilateMask(fgMask, w, h, radius: 2);
    final fillValue = background;

    final left = selected.left;
    final right = selected.right;
    final top = selected.top;
    var bottom = selected.bottom;

    // Trim excess forearm/wrist if hand enters from bottom and bbox is very tall
    final bw = right - left + 1;
    final bh = bottom - top + 1;
    if (bottom >= h - 2 && bh > bw * 1.45) {
      bottom = top + (bw * 1.35).round().clamp(20, bh);
    }

    final side = math.max(bw, bottom - top + 1);

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

    final suppressBackground = spread > 40 || hasColor;

    for (final margin in scales) {
      final size = (side * margin).ceil();
      final x0 = (left + right + 1 - size) ~/ 2;
      final y0 = (top + bottom + 1 - size) ~/ 2;
      final crop = img.Image(width: size, height: size, numChannels: 1);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final sx = x0 + x, sy = y0 + y;
          int value = fillValue;
          if (sx >= 0 && sx < w && sy >= 0 && sy < h) {
            final idx = sy * w + sx;
            if (!suppressBackground || dilatedFg[idx] != 0) {
              value = gray[idx];
            }
          }
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
        if (spread <= 55) {
          final direct = img.copyResize(
            crop,
            width: 64,
            height: 64,
            interpolation: img.Interpolation.average,
          );
          crops.add(Uint8List.fromList(direct.getBytes()));
        }
      }
    }
    return (crops: crops, rejection: null);
  }

  static bool _isValidComponent(_ComponentResult comp, int w, int h) {
    final side = math.max(
      comp.right - comp.left + 1,
      comp.bottom - comp.top + 1,
    );
    if (comp.area < w * h * 0.015 || side < 20) return false;
    if (comp.area > w * h * 0.85) return false;
    if (comp.left == 0 &&
        comp.right == w - 1 &&
        comp.top == 0 &&
        comp.bottom == h - 1) {
      return false;
    }
    return true;
  }

  static _ComponentResult? _findBestComponent(Uint8List mask, int w, int h) {
    final visited = Uint8List.fromList(mask);
    final queue = Int32List(visited.length);
    _ComponentResult? best;
    var bestScore = -1.0;

    final cxFrame = w / 2.0;
    final cyFrame = h / 2.0;
    final maxDist = math.sqrt(cxFrame * cxFrame + cyFrame * cyFrame);

    for (var i = 0; i < visited.length; i++) {
      if (visited[i] == 0) continue;
      var end = 1;
      queue[0] = i;
      visited[i] = 0;
      var xMin = w, xMax = 0, yMin = h, yMax = 0;
      var sumX = 0.0, sumY = 0.0;

      void visit(int index) {
        if (visited[index] != 0) {
          visited[index] = 0;
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
        sumX += x;
        sumY += y;
        if (x > 0) visit(index - 1);
        if (x < w - 1) visit(index + 1);
        if (y > 0) visit(index - w);
        if (y < h - 1) visit(index + w);
      }

      if (end < 40) continue;
      final cx = sumX / end;
      final cy = sumY / end;
      final dist = math.sqrt(
        (cx - cxFrame) * (cx - cxFrame) + (cy - cyFrame) * (cy - cyFrame),
      );
      final centerWeight = 1.0 - 0.5 * (dist / math.max(1.0, maxDist));
      final score = end * centerWeight;
      if (score > bestScore) {
        bestScore = score;
        best = _ComponentResult(
          seedIndex: i,
          area: end,
          left: xMin,
          right: xMax,
          top: yMin,
          bottom: yMax,
        );
      }
    }
    return best;
  }

  static Uint8List _extractComponentMask(
    Uint8List mask,
    int w,
    int h,
    int seedIndex,
  ) {
    final out = Uint8List(mask.length);
    final work = Uint8List.fromList(mask);
    if (work[seedIndex] == 0) return out;
    final queue = Int32List(mask.length);
    var end = 1;
    queue[0] = seedIndex;
    work[seedIndex] = 0;
    out[seedIndex] = 1;

    void visit(int index) {
      if (work[index] != 0) {
        work[index] = 0;
        out[index] = 1;
        queue[end++] = index;
      }
    }

    for (var head = 0; head < end; head++) {
      final index = queue[head];
      final x = index % w, y = index ~/ w;
      if (x > 0) visit(index - 1);
      if (x < w - 1) visit(index + 1);
      if (y > 0) visit(index - w);
      if (y < h - 1) visit(index + w);
    }
    return out;
  }

  static Uint8List _dilateMask(Uint8List mask, int w, int h, {int radius = 1}) {
    final out = Uint8List(mask.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (mask[y * w + x] == 0) continue;
        final y0 = math.max(0, y - radius);
        final y1 = math.min(h - 1, y + radius);
        final x0 = math.max(0, x - radius);
        final x1 = math.min(w - 1, x + radius);
        for (var ny = y0; ny <= y1; ny++) {
          for (var nx = x0; nx <= x1; nx++) {
            out[ny * w + nx] = 1;
          }
        }
      }
    }
    return out;
  }

  static Uint8List _erodeMask(Uint8List mask, int w, int h) {
    final out = Uint8List(mask.length);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final idx = y * w + x;
        if (mask[idx] != 0 &&
            mask[idx - 1] != 0 &&
            mask[idx + 1] != 0 &&
            mask[idx - w] != 0 &&
            mask[idx + w] != 0) {
          out[idx] = 1;
        }
      }
    }
    return out;
  }

  static Uint8List _morphCloseOpen(Uint8List mask, int w, int h) {
    final closed = _erodeMask(_dilateMask(mask, w, h, radius: 1), w, h);
    return _dilateMask(_erodeMask(closed, w, h), w, h, radius: 1);
  }

  static int _otsuThreshold(Uint8List gray) {
    final hist = List<int>.filled(256, 0);
    for (final v in gray) {
      hist[v]++;
    }
    final total = gray.length;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0;
    var wB = 0;
    var maxVar = 0.0;
    var threshold = 0;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final between = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
      if (between > maxVar) {
        maxVar = between;
        threshold = t;
      }
    }
    return threshold;
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

    double smoothLight(int x, int y) {
      final fx = (x - (band - 1) / 2) / (width - band);
      final fy = (y - (band - 1) / 2) / (height - band);
      final top = topLeft + fx * (topRight - topLeft);
      final bottom = bottomLeft + fx * (bottomRight - bottomLeft);
      return top + fy * (bottom - top);
    }

    bool edgeMatches(
      double Function(int, int) expected, {
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

    bool matchesBorder(double Function(int, int) expected) =>
        edgeMatches(expected, xStart: 0, yStart: 0, xEnd: width, yEnd: band) &&
        edgeMatches(
          expected,
          xStart: 0,
          yStart: height - band,
          xEnd: width,
          yEnd: height,
        ) &&
        edgeMatches(expected, xStart: 0, yStart: 0, xEnd: band, yEnd: height) &&
        edgeMatches(
          expected,
          xStart: width - band,
          yStart: 0,
          xEnd: width,
          yEnd: height,
        );

    double Function(int, int)? lighting = matchesBorder(smoothLight)
        ? smoothLight
        : null;
    if (lighting == null) {
      double Function(int, int)? stepLight({required bool acrossX}) {
        final a = acrossX ? bottomLeft : topRight;
        final b = acrossX ? topRight : bottomLeft;
        if ((topLeft - a).abs() > 12 || (b - bottomRight).abs() > 12) {
          return null;
        }
        final first = (topLeft + a) / 2;
        final second = (b + bottomRight) / 2;
        if ((first - second).abs() < 56) return null;
        final length = acrossX ? width : height;
        final perpendicular = acrossX ? height : width;
        double edgeAverage(int axis, int offset) {
          var sum = 0;
          for (var i = offset; i < offset + band; i++) {
            sum += acrossX ? gray[i * width + axis] : gray[axis * width + i];
          }
          return sum / band;
        }

        int transition(int offset) {
          final middle = (first + second) / 2;
          final goesUp = second > first;
          for (var i = length ~/ 8; i < 7 * length ~/ 8; i++) {
            if ((edgeAverage(i, offset) > middle) == goesUp) return i;
          }
          return -1;
        }

        final near = transition(0);
        final far = transition(perpendicular - band);
        if (near < 0 || far < 0 || (near - far).abs() > 1) return null;
        final split = (near + far) / 2;
        double expected(int x, int y) =>
            (acrossX ? x : y) < split ? first : second;
        return matchesBorder(expected) ? expected : null;
      }

      lighting = stepLight(acrossX: true) ?? stepLight(acrossX: false);
      if (lighting == null) return false;
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        final local = lighting(x, y).clamp(40.0, 255.0);
        gray[index] = (gray[index] * reference / local).round().clamp(0, 255);
      }
    }
    return true;
  }
}

class _ComponentResult {
  const _ComponentResult({
    required this.seedIndex,
    required this.area,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  final int seedIndex;
  final int area;
  final int left;
  final int right;
  final int top;
  final int bottom;
}
