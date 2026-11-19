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
    if ((width != hogFeatureCount && width != multimodalFeatureCount && width != landmarkFeatureCount && width != hybridFeatureCount) ||
        count < classes ||
        classes != 24) {
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
    _featureCount = width;
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

  static const landmarkFeatureCount = 52;
  static const hogFeatureCount = 1764;
  // 1764 (HOG) + 40 (LBP 2x2 uniform) + 7 (Hu Moments) + 4 (Contour Geometry)
  static const multimodalFeatureCount = 1815;
  // 1815 (HOG + LBP + Hu + Contour) + 52 (MediaPipe Landmarks)
  static const hybridFeatureCount = 1867;

  late final int _featureCount;
  late final double _gamma;
  late final List<String> _labels;
  late final List<int> _starts;
  late final Float32List _mean, _scale, _intercepts, _coefficients, _vectors;

  int get featureCount => _featureCount;



  ({String label, List<double> scores, bool accepted}) predictCropsWithLandmarks(
    List<Uint8List> crops,
    List<({double x, double y})> landmarks,
  ) {
    final tight = predict(extractHybridFeatures(crops.first, landmarks));
    final wide = predict(extractHybridFeatures(crops.last, landmarks));
    return (
      label: tight.label,
      scores: tight.scores,
      accepted: tight.label == wide.label,
    );
  }

  /// Hybrid 1867-dim vector: 1815 multimodal image/contour features + 52 MediaPipe landmark features.
  static Float32List extractHybridFeatures(
    Uint8List pixels,
    List<({double x, double y})> landmarks,
  ) {
    final mm = multimodalFeatures(pixels);
    final lm = extractLandmarkFeatures(landmarks);
    final out = Float32List(hybridFeatureCount);
    out.setRange(0, mm.length, mm);
    out.setRange(mm.length, hybridFeatureCount, lm);
    return out;
  }

  ({String label, List<double> scores, bool accepted}) predictLandmarks(
    List<({double x, double y})> landmarks,
  ) {
    final features = extractLandmarkFeatures(landmarks);
    final res = predict(features);
    return (label: res.label, scores: res.scores, accepted: true);
  }

  /// 52-dim MediaPipe 21-landmark geometric features (42 normalized x,y + 10 distances).
  static Float32List extractLandmarkFeatures(
    List<({double x, double y})> landmarks,
  ) {
    if (landmarks.length != 21) {
      throw ArgumentError.value(landmarks.length, 'landmarks.length');
    }
    final wx = landmarks[0].x;
    final wy = landmarks[0].y;
    final shiftedX = List<double>.filled(21, 0.0);
    final shiftedY = List<double>.filled(21, 0.0);
    var scale = 0.0;
    for (var i = 0; i < 21; i++) {
      final dx = landmarks[i].x - wx;
      final dy = landmarks[i].y - wy;
      shiftedX[i] = dx;
      shiftedY[i] = dy;
      if (i > 0) {
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > scale) scale = d;
      }
    }
    if (scale < 1e-6) scale = 1.0;

    final out = Float32List(landmarkFeatureCount);
    var offset = 0;
    for (var i = 0; i < 21; i++) {
      shiftedX[i] /= scale;
      shiftedY[i] /= scale;
      out[offset++] = shiftedX[i];
      out[offset++] = shiftedY[i];
    }
    const pairs = [
      [0, 4],
      [0, 8],
      [0, 12],
      [0, 16],
      [0, 20],
      [4, 8],
      [8, 12],
      [12, 16],
      [16, 20],
      [5, 17],
    ];
    for (final p in pairs) {
      final dx = shiftedX[p[0]] - shiftedX[p[1]];
      final dy = shiftedY[p[0]] - shiftedY[p[1]];
      out[offset++] = math.sqrt(dx * dx + dy * dy);
    }
    return out;
  }

  Float32List extractFeatures(Uint8List pixels) {
    if (_featureCount == hogFeatureCount) {
      return hog(pixels);
    }
    return multimodalFeatures(pixels);
  }

  ({String label, List<double> scores, bool accepted}) predictCrops(
    List<Uint8List> crops,
  ) {
    if (crops.length != 2 && crops.length != 4 && crops.length != 5) {
      throw ArgumentError.value(crops.length, 'crops.length');
    }
    if (crops.length > 2) {
      final inverted = predict(extractFeatures(crops[1]));
      final finer = predict(extractFeatures(crops[2]));
      if (inverted.label == finer.label) {
        return (label: finer.label, scores: finer.scores, accepted: true);
      }
      final tight = predict(extractFeatures(crops.first));
      final wide = predict(extractFeatures(crops.last));
      final accepted = tight.label == wide.label;
      if (accepted && crops.length == 5 && finer.label != tight.label) {
        final direct = predict(extractFeatures(crops[3]));
        if (direct.label == finer.label) {
          return (label: finer.label, scores: finer.scores, accepted: true);
        }
      }
      return (label: tight.label, scores: tight.scores, accepted: accepted);
    }
    final tight = predict(extractFeatures(crops.first));
    final other = predict(extractFeatures(crops.last));
    return (
      label: tight.label,
      scores: tight.scores,
      accepted: tight.label == other.label,
    );
  }

  ({String label, List<double> scores}) predict(Float32List features) {
    if (features.length != _featureCount) {
      throw ArgumentError.value(features.length, 'features');
    }
    final input = Float32List(_featureCount);
    for (var j = 0; j < input.length; j++) {
      final s = _scale[j] == 0 ? 1.0 : _scale[j];
      input[j] = (features[j] - _mean[j]) / s;
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

  /// Multimodal feature vector (1815 dims):
  /// - 1764 HOG features
  /// - 40 Uniform LBP features (2x2 spatial grid x 10 bins)
  /// - 7 log-transformed Hu Moments from Otsu foreground mask
  /// - 4 Contour geometry features (aspectRatio, solidity, extent, circularity)
  static Float32List multimodalFeatures(Uint8List pixels) {
    final hogVec = hog(pixels);
    final lbpVec = lbpGrid2x2(pixels);
    final mask = _foregroundMask64(pixels);
    final huVec = huMoments(mask);
    final geoVec = contourGeometry(mask);

    final out = Float32List(multimodalFeatureCount);
    var offset = 0;
    out.setRange(offset, offset + hogVec.length, hogVec);
    offset += hogVec.length;
    out.setRange(offset, offset + lbpVec.length, lbpVec);
    offset += lbpVec.length;
    out.setRange(offset, offset + huVec.length, huVec);
    offset += huVec.length;
    out.setRange(offset, offset + geoVec.length, geoVec);
    return out;
  }

  // skimage HOG: signed central differences, unsigned angles, and L2-Hys.
  static Float32List hog(Uint8List pixels) {
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
    final features = Float32List(hogFeatureCount);
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

  /// 8-neighbor uniform LBP over 2x2 quadrants of 64x64 image (4 x 10 = 40 dims).
  static Float32List lbpGrid2x2(Uint8List pixels) {
    const size = 64;
    const offsets = [
      [-1, -1],
      [0, -1],
      [1, -1],
      [1, 0],
      [1, 1],
      [0, 1],
      [-1, 1],
      [-1, 0],
    ];
    final out = Float32List(40);
    final counts = Float32List(4);
    for (var y = 1; y < size - 1; y++) {
      final qy = y < 32 ? 0 : 1;
      for (var x = 1; x < size - 1; x++) {
        final qx = x < 32 ? 0 : 1;
        final quad = qy * 2 + qx;
        final center = pixels[y * size + x];
        var code = 0;
        for (var b = 0; b < 8; b++) {
          final nx = x + offsets[b][0];
          final ny = y + offsets[b][1];
          if (pixels[ny * size + nx] >= center) {
            code |= (1 << b);
          }
        }
        // Count circular transitions
        var transitions = 0;
        var ones = 0;
        for (var b = 0; b < 8; b++) {
          final curr = (code >> b) & 1;
          final next = (code >> ((b + 1) & 7)) & 1;
          if (curr != next) transitions++;
          ones += curr;
        }
        final bin = transitions <= 2 ? ones : 9;
        out[quad * 10 + bin] += 1.0;
        counts[quad] += 1.0;
      }
    }
    for (var q = 0; q < 4; q++) {
      final c = counts[q] > 0 ? counts[q] : 1.0;
      for (var b = 0; b < 10; b++) {
        out[q * 10 + b] /= c;
      }
    }
    return out;
  }

  static Uint8List _foregroundMask64(Uint8List pixels) {
    const size = 64;
    final border = <int>[];
    for (var i = 0; i < size; i++) {
      border.add(pixels[i]);
      border.add(pixels[(size - 1) * size + i]);
      border.add(pixels[i * size]);
      border.add(pixels[i * size + size - 1]);
    }
    border.sort();
    final bg = border[border.length ~/ 2];

    final delta = Uint8List(size * size);
    final hist = List<int>.filled(256, 0);
    for (var i = 0; i < delta.length; i++) {
      final d = (pixels[i] - bg).abs().clamp(0, 255);
      delta[i] = d;
      hist[d]++;
    }
    // Otsu threshold on delta
    final total = delta.length;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0, wB = 0, maxVar = 0.0, threshold = 12;
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
    final th = math.max(threshold, 10);
    final mask = Uint8List(delta.length);
    for (var i = 0; i < delta.length; i++) {
      if (delta[i] >= th) mask[i] = 1;
    }
    return mask;
  }

  static Float32List huMoments(Uint8List mask) {
    const size = 64;
    var m00 = 0.0, m10 = 0.0, m01 = 0.0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (mask[y * size + x] != 0) {
          m00 += 1.0;
          m10 += x;
          m01 += y;
        }
      }
    }
    if (m00 < 1.0) return Float32List(7);
    final xBar = m10 / m00;
    final yBar = m01 / m00;

    var mu20 = 0.0, mu02 = 0.0, mu11 = 0.0;
    var mu30 = 0.0, mu03 = 0.0, mu21 = 0.0, mu12 = 0.0;
    for (var y = 0; y < size; y++) {
      final dy = y - yBar;
      for (var x = 0; x < size; x++) {
        if (mask[y * size + x] == 0) continue;
        final dx = x - xBar;
        final dx2 = dx * dx;
        final dy2 = dy * dy;
        mu20 += dx2;
        mu02 += dy2;
        mu11 += dx * dy;
        mu30 += dx2 * dx;
        mu03 += dy2 * dy;
        mu21 += dx2 * dy;
        mu12 += dx * dy2;
      }
    }

    final n2 = m00 * m00;
    final n25 = math.pow(m00, 2.5);
    final nu20 = mu20 / n2;
    final nu02 = mu02 / n2;
    final nu11 = mu11 / n2;
    final nu30 = mu30 / n25;
    final nu03 = mu03 / n25;
    final nu21 = mu21 / n25;
    final nu12 = mu12 / n25;

    final h1 = nu20 + nu02;
    final h2 = (nu20 - nu02) * (nu20 - nu02) + 4 * nu11 * nu11;
    final h3 =
        (nu30 - 3 * nu12) * (nu30 - 3 * nu12) +
        (3 * nu21 - nu03) * (3 * nu21 - nu03);
    final h4 =
        (nu30 + nu12) * (nu30 + nu12) + (nu21 + nu03) * (nu21 + nu03);
    final h5 =
        (nu30 - 3 * nu12) *
            (nu30 + nu12) *
            ((nu30 + nu12) * (nu30 + nu12) -
                3 * (nu21 + nu03) * (nu21 + nu03)) +
        (3 * nu21 - nu03) *
            (nu21 + nu03) *
            (3 * (nu30 + nu12) * (nu30 + nu12) -
                (nu21 + nu03) * (nu21 + nu03));
    final h6 =
        (nu20 - nu02) *
            ((nu30 + nu12) * (nu30 + nu12) -
                (nu21 + nu03) * (nu21 + nu03)) +
        4 * nu11 * (nu30 + nu12) * (nu21 + nu03);
    final h7 =
        (3 * nu21 - nu03) *
            (nu30 + nu12) *
            ((nu30 + nu12) * (nu30 + nu12) -
                3 * (nu21 + nu03) * (nu21 + nu03)) -
        (nu30 - 3 * nu12) *
            (nu21 + nu03) *
            (3 * (nu30 + nu12) * (nu30 + nu12) -
                (nu21 + nu03) * (nu21 + nu03));

    final raw = [h1, h2, h3, h4, h5, h6, h7];
    final out = Float32List(7);
    for (var i = 0; i < 7; i++) {
      final v = raw[i];
      if (v == 0.0) {
        out[i] = 0.0;
      } else {
        out[i] = (v < 0 ? 1.0 : -1.0) *
            (math.log(v.abs() + 1e-12) / math.ln10);
      }
    }
    return out;
  }

  /// Contour geometry (4 dims): aspectRatio, solidity, extent, circularity.
  static Float32List contourGeometry(Uint8List mask) {
    const size = 64;
    var area = 0;
    var minX = size, maxX = -1, minY = size, maxY = -1;
    var perimeter = 0;
    final pts = <math.Point<int>>[];

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (mask[y * size + x] == 0) continue;
        area++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        final isEdge = x == 0 ||
            x == size - 1 ||
            y == 0 ||
            y == size - 1 ||
            mask[y * size + x - 1] == 0 ||
            mask[y * size + x + 1] == 0 ||
            mask[(y - 1) * size + x] == 0 ||
            mask[(y + 1) * size + x] == 0;
        if (isEdge) {
          perimeter++;
          pts.add(math.Point(x, y));
        }
      }
    }
    if (area == 0 || pts.length < 3) return Float32List(4);

    final bw = (maxX - minX + 1).toDouble();
    final bh = (maxY - minY + 1).toDouble();
    final aspectRatio = bw / bh;
    final extent = area / (bw * bh);
    final circularity = perimeter > 0
        ? (4.0 * math.pi * area) / (perimeter * perimeter)
        : 0.0;

    // Convex hull via Andrew's monotone chain
    pts.sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    int cross(math.Point<int> o, math.Point<int> a, math.Point<int> b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

    final lower = <math.Point<int>>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <math.Point<int>>[];
    for (var i = pts.length - 1; i >= 0; i--) {
      final p = pts[i];
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    final hull = [...lower, ...upper];
    var hullArea = 0.0;
    for (var i = 0; i < hull.length; i++) {
      final p1 = hull[i];
      final p2 = hull[(i + 1) % hull.length];
      hullArea += p1.x * p2.y - p2.x * p1.y;
    }
    hullArea = hullArea.abs() * 0.5;
    final solidity = hullArea > 0 ? math.min(1.0, area / hullArea) : 1.0;

    return Float32List.fromList([
      aspectRatio,
      solidity,
      extent,
      circularity,
    ]);
  }
}