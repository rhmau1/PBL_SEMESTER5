import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sign_language/services/image_preprocessor.dart';

CameraImage _frame(img.Image gray, {required bool bgra}) {
  final stride = gray.width * (bgra ? 4 : 1) + 12;
  final data = Uint8List(stride * gray.height);
  for (var y = 0; y < gray.height; y++) {
    for (var x = 0; x < gray.width; x++) {
      final index = y * stride + x * (bgra ? 4 : 1);
      final value = gray.getPixel(x, y).r.toInt();
      data[index] = value;
      if (bgra) {
        data[index + 1] = value;
        data[index + 2] = value;
        data[index + 3] = 255;
      }
    }
  }
  // Includes row padding to catch incorrect stride assumptions.
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: CameraImageFormat(
        bgra ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
        raw: bgra ? 1111970369 : 35,
      ),
      width: gray.width,
      height: gray.height,
      planes: [
        CameraImagePlane(
          bytes: data,
          bytesPerPixel: bgra ? 4 : 1,
          bytesPerRow: stride,
        ),
        if (!bgra) ...[
          CameraImagePlane(
            bytes: Uint8List(gray.width * gray.height ~/ 4),
            bytesPerPixel: 1,
            bytesPerRow: gray.width ~/ 2,
          ),
          CameraImagePlane(
            bytes: Uint8List(gray.width * gray.height ~/ 4),
            bytesPerPixel: 1,
            bytesPerRow: gray.width ~/ 2,
          ),
        ],
      ],
    ),
  );
}

void main() {
  for (final rotation in [0, 90, 180, 270]) {
    for (final mirror in [false, true]) {
      for (final bgra in [false, true]) {
        test(
          'file and ${bgra ? 'BGRA' : 'YUV'} have identical input at $rotation degrees, mirror $mirror, frame edge',
          () {
            final gray = img.Image(width: 96, height: 72, numChannels: 1);
            for (var y = 0; y < gray.height; y++) {
              for (var x = 0; x < gray.width; x++) {
                gray.setPixelR(x, y, (x * 13 + y * 7) % 256);
              }
            }
            var upright = rotation == 0
                ? gray
                : img.copyRotate(gray, angle: rotation.toDouble());
            final detectorPoints = List<Offset>.generate(
              21,
              (i) => Offset(.79 + .20 * (i % 7) / 6, .61 + .32 * (i ~/ 7) / 2),
            );
            final filePoints = ImagePreprocessor.orientNormalizedPoints(
              detectorPoints,
              rotationDegrees: 0,
              mirrorHorizontally: mirror,
            );
            if (mirror) upright = img.flipHorizontal(img.Image.from(upright));
            final file = ImagePreprocessor.imageToGrayHandCrops(
              upright,
              normalizedLandmarks: filePoints,
            );
            final frame = ImagePreprocessor.cameraImageToGrayCrops(
              _frame(gray, bgra: bgra),
              rotationDegrees: rotation,
              mirrorHorizontally: mirror,
              normalizedLandmarks: detectorPoints,
            );
            for (final pair in [
              (file.context, frame.context),
              (file.tight, frame.tight),
            ]) {
              expect(pair.$2.getBytes(), orderedEquals(pair.$1.getBytes()));
            }
          },
        );
      }
    }
  }
}
