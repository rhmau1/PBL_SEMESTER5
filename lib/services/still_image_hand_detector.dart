import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'image_preprocessor.dart';

class HandImageException implements Exception {
  const HandImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// MediaPipe IMAGE mode, independent of the camera's LIVE_STREAM detector.
class StillImageHandDetection {
  const StillImageHandDetection({
    required this.landmarks,
    required this.usedPaddingRetry,
  });

  final List<Offset> landmarks;
  final bool usedPaddingRetry;
}

class StillImageHandDetector {
  const StillImageHandDetector();

  static const _channel = MethodChannel('latih_isyarat/image_hand_landmarker');

  Future<img.Image> loadImage(String path) => compute(_decodeStillImage, path);

  Future<List<Offset>> detect(img.Image image) async =>
      (await detectWithDetails(image)).landmarks;

  Future<List<dynamic>> _detectImage(img.Image image) async {
    try {
      return await _channel.invokeListMethod<dynamic>('detect', {
            'bytes': img.encodeJpg(image, quality: 95),
          }) ??
          const [];
    } on MissingPluginException {
      throw const HandImageException(
        'Deteksi tangan belum tersedia. Hentikan aplikasi lalu jalankan ulang.',
      );
    } on PlatformException {
      throw const HandImageException(
        'MediaPipe gagal memproses gambar. Coba gambar lain.',
      );
    }
  }

  Future<StillImageHandDetection> detectWithDetails(img.Image image) async {
    var hands = await _detectImage(image);
    var usedPaddingRetry = false;
    var border = 0;
    if (hands.isEmpty) {
      // Keep every original pixel. Retry once at another detector scale without
      // lowering confidence or cutting off fingertips. CNN still sees source.
      border = ((image.width > image.height ? image.width : image.height) / 8)
          .round()
          .clamp(1, 128);
      final padded = img.Image(
        width: image.width + 2 * border,
        height: image.height + 2 * border,
        numChannels: 3,
      );
      img.fill(padded, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(padded, image, dstX: border, dstY: border);
      hands = await _detectImage(padded);
      usedPaddingRetry = true;
    }
    if (hands.isEmpty) {
      throw const HandImageException(
        'Tangan tidak terdeteksi. Gunakan foto dengan seluruh jari terlihat.',
      );
    }
    if (hands.length != 1) {
      throw const HandImageException(
        'Gunakan satu tangan dalam setiap gambar.',
      );
    }
    final points = hands.single as List<dynamic>;
    if (points.length != 21) {
      throw const HandImageException('Posisi tangan tidak dapat dibaca.');
    }
    final landmarks = List<Offset>.unmodifiable(
      points.map((point) {
        final coordinates = point as List<dynamic>;
        final x = (coordinates[0] as num).toDouble();
        final y = (coordinates[1] as num).toDouble();
        if (!x.isFinite || !y.isFinite) {
          throw const HandImageException('Posisi tangan tidak dapat dibaca.');
        }
        final sourceX = usedPaddingRetry
            ? (x * (image.width + 2 * border) - border) / image.width
            : x;
        final sourceY = usedPaddingRetry
            ? (y * (image.height + 2 * border) - border) / image.height
            : y;
        // A detection on the artificial border is not a source hand. Do not
        // clamp such points into a fake hand at the image edge.
        if (usedPaddingRetry &&
            (sourceX < 0 || sourceX > 1 || sourceY < 0 || sourceY > 1)) {
          throw const HandImageException('Posisi tangan tidak dapat dibaca.');
        }
        return Offset(sourceX.clamp(0.0, 1.0), sourceY.clamp(0.0, 1.0));
      }),
    );
    return StillImageHandDetection(
      landmarks: landmarks,
      usedPaddingRetry: usedPaddingRetry,
    );
  }
}

img.Image _decodeStillImage(String path) {
  final image = ImagePreprocessor.decodeFileBytes(File(path).readAsBytesSync());
  // Preserve the entire upright image and its aspect ratio. Landmarks and CNN
  // crops use the same coordinates; photo EXIF is applied exactly once.
  final longest = image.width > image.height ? image.width : image.height;
  if (longest <= 1024) return image;
  return img.copyResize(
    image,
    width: (image.width * 1024 / longest).round().clamp(1, 1024),
    height: (image.height * 1024 / longest).round().clamp(1, 1024),
    interpolation: img.Interpolation.average,
  );
}
