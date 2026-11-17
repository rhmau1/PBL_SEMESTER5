import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Copies the selected camera frame before awaiting, then converts off the UI
/// isolate. Rotation is applied once. Camera preview mirroring is never applied.
Future<Uint8List> encodeJzCameraFrame(
  CameraImage image, {
  required int rotationDegrees,
}) {
  final rotation = ((rotationDegrees % 360) + 360) % 360;
  if (!const [0, 90, 180, 270].contains(rotation)) {
    throw ArgumentError.value(rotationDegrees, 'rotationDegrees');
  }
  final group = image.format.group;
  if (group != ImageFormatGroup.yuv420 &&
      group != ImageFormatGroup.nv21 &&
      group != ImageFormatGroup.bgra8888) {
    throw UnsupportedError('Format kamera ${group.name} belum didukung J/Z.');
  }
  return compute(_encodeFrame, <String, Object>{
    'width': image.width,
    'height': image.height,
    'rotation': rotation,
    'format': group.name,
    'planes': image.planes
        .map(
          (plane) => <String, Object>{
            'bytes': Uint8List.fromList(plane.bytes),
            'rowStride': plane.bytesPerRow,
            'pixelStride':
                plane.bytesPerPixel ??
                (group == ImageFormatGroup.bgra8888 ? 4 : 1),
          },
        )
        .toList(growable: false),
  });
}

Uint8List _encodeFrame(Map<String, Object> data) {
  final width = data['width']! as int;
  final height = data['height']! as int;
  final rotation = data['rotation']! as int;
  final format = data['format']! as String;
  final planes = data['planes']! as List<Map<String, Object>>;
  if (width <= 0 || height <= 0 || width > 8192 || height > 8192) {
    throw const FormatException('Ukuran frame tidak valid.');
  }
  final isBgra = format == 'bgra8888';
  final packedNv21 = format == 'nv21' && planes.length == 1;
  if ((isBgra && planes.length != 1) ||
      (!isBgra && !packedNv21 && planes.length != 3)) {
    throw const FormatException('Susunan plane kamera tidak didukung.');
  }
  for (var index = 0; index < planes.length; index++) {
    final plane = planes[index];
    final bytes = plane['bytes']! as Uint8List;
    final stride = plane['rowStride']! as int;
    final pixelStride = plane['pixelStride']! as int;
    final planeWidth = index == 0 ? width : (width + 1) ~/ 2;
    final planeHeight = index == 0 ? height : (height + 1) ~/ 2;
    final channels = isBgra ? 4 : 1;
    final rowBytes = (planeWidth - 1) * pixelStride + channels;
    if (pixelStride < channels ||
        stride < rowBytes ||
        bytes.length < (planeHeight - 1) * stride + rowBytes) {
      throw const FormatException(
        'Stride atau panjang plane kamera tidak valid.',
      );
    }
    if (packedNv21 &&
        (pixelStride != 1 ||
            stride < ((width + 1) ~/ 2) * 2 ||
            bytes.length <
                (height + (height - 1) ~/ 2) * stride +
                    ((width + 1) ~/ 2) * 2)) {
      throw const FormatException('Susunan data NV21 tidak valid.');
    }
  }
  int read(int planeIndex, int x, int y, {int offset = 0}) {
    final plane = planes[planeIndex];
    final bytes = plane['bytes']! as Uint8List;
    final stride = plane['rowStride']! as int;
    final pixelStride = plane['pixelStride']! as int;
    if (stride <= 0 || pixelStride <= 0) {
      throw const FormatException('Stride kamera tidak valid.');
    }
    final index = y * stride + x * pixelStride + offset;
    if (index < 0 || index >= bytes.length) {
      throw const FormatException('Data plane kamera terpotong.');
    }
    return bytes[index];
  }

  // Sample RGB at the final size to avoid allocating a full-resolution image
  // for every frame. Aspect ratio is preserved, including landscape input.
  final scale = math.min(1.0, 640 / math.max(width, height));
  final sampledWidth = math.max(1, (width * scale).round());
  final sampledHeight = math.max(1, (height * scale).round());
  var rgb = img.Image(width: sampledWidth, height: sampledHeight);
  for (var y = 0; y < sampledHeight; y++) {
    final sourceY = math.min(height - 1, ((y + 0.5) / scale).floor());
    for (var x = 0; x < sampledWidth; x++) {
      final sourceX = math.min(width - 1, ((x + 0.5) / scale).floor());
      if (isBgra) {
        rgb.setPixelRgb(
          x,
          y,
          read(0, sourceX, sourceY, offset: 2),
          read(0, sourceX, sourceY, offset: 1),
          read(0, sourceX, sourceY),
        );
        continue;
      }
      final luminance = read(0, sourceX, sourceY);
      late final int u;
      late final int v;
      if (packedNv21) {
        final plane = planes[0];
        final bytes = plane['bytes']! as Uint8List;
        final stride = plane['rowStride']! as int;
        final uvIndex =
            stride * height + (sourceY ~/ 2) * stride + (sourceX ~/ 2) * 2;
        if (uvIndex + 1 >= bytes.length) {
          throw const FormatException('Data NV21 terpotong.');
        }
        v = bytes[uvIndex] - 128;
        u = bytes[uvIndex + 1] - 128;
      } else {
        u = read(1, sourceX ~/ 2, sourceY ~/ 2) - 128;
        v = read(2, sourceX ~/ 2, sourceY ~/ 2) - 128;
      }
      rgb.setPixelRgb(
        x,
        y,
        (luminance + 1.402 * v).round().clamp(0, 255),
        (luminance - 0.344136 * u - 0.714136 * v).round().clamp(0, 255),
        (luminance + 1.772 * u).round().clamp(0, 255),
      );
    }
  }
  if (rotation != 0) {
    rgb = img.copyRotate(rgb, angle: rotation.toDouble());
  }
  return img.encodeJpg(rgb, quality: 95);
}
