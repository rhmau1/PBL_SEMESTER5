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
class StillImageHandDetector {
  const StillImageHandDetector();

  static const _channel = MethodChannel('latih_isyarat/image_hand_landmarker');

  Future<img.Image> loadImage(String path) => compute(_decodeUploadImage, path);

  Future<List<Offset>> detect(img.Image image) async {
    final Uint8List bytes = img.encodeJpg(image, quality: 95);
    final List<dynamic>? hands;
    try {
      hands = await _channel.invokeListMethod<dynamic>('detect', {
        'bytes': bytes,
      });
    } on MissingPluginException {
      throw const HandImageException(
        'Deteksi tangan belum tersedia. Hentikan aplikasi lalu jalankan ulang.',
      );
    } on PlatformException {
      throw const HandImageException(
        'MediaPipe gagal memproses gambar. Coba gambar lain.',
      );
    }
    if (hands == null || hands.isEmpty) {
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
    return List<Offset>.unmodifiable(
      points.map((point) {
        final coordinates = point as List<dynamic>;
        final x = (coordinates[0] as num).toDouble();
        final y = (coordinates[1] as num).toDouble();
        if (!x.isFinite || !y.isFinite) {
          throw const HandImageException('Posisi tangan tidak dapat dibaca.');
        }
        return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
      }),
    );
  }
}

img.Image _decodeUploadImage(String path) {
  final image = ImagePreprocessor.decodeFileBytes(File(path).readAsBytesSync());
  // Preserve the entire upright image and its aspect ratio. Landmarks and CNN
  // crops use the same coordinates; gallery EXIF is applied exactly once.
  final longest = image.width > image.height ? image.width : image.height;
  if (longest <= 1024) return image;
  return img.copyResize(
    image,
    width: (image.width * 1024 / longest).round().clamp(1, 1024),
    height: (image.height * 1024 / longest).round().clamp(1, 1024),
    interpolation: img.Interpolation.average,
  );
}
