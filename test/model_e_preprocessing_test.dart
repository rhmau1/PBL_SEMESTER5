import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sign_language/services/image_preprocessor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Model E receives RGB 96x96 normalized to [-1, 1]', () {
    final image = img.Image(width: 4, height: 4, numChannels: 3);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, 255, 128, 0);
      }
    }

    final resized = ImagePreprocessor.toModelRgbImage(image);
    final input = ImagePreprocessor.rgbImageToInput(resized);

    expect(resized.width, 96);
    expect(resized.height, 96);
    expect(resized.numChannels, 3);
    expect(input, hasLength(1));
    expect(input.first, hasLength(96));
    expect(input.first.first, hasLength(96));
    expect(input.first.first.first, [
      1.0,
      closeTo(128 / 127.5 - 1, 0.000001),
      -1.0,
    ]);
  });

  test('Model E keeps color when cropping around hand landmarks', () {
    final image = img.Image(width: 100, height: 100, numChannels: 3);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, 12, 100, 220);
      }
    }
    final landmarks = List<Offset>.generate(
      21,
      (index) => Offset(0.3 + (index % 7) * 0.05, 0.3 + (index ~/ 7) * 0.1),
    );

    final crops = ImagePreprocessor.imageToRgbHandCrops(
      image,
      normalizedLandmarks: landmarks,
    );
    final modelImage = ImagePreprocessor.toModelRgbImage(crops.context);
    final pixel = modelImage.getPixel(48, 48);

    expect(modelImage.numChannels, 3);
    expect(pixel.r, 12);
    expect(pixel.g, 100);
    expect(pixel.b, 220);
  });

  test('Model E camera preprocessing converts YUV420 to RGB crops', () {
    const width = 16;
    const height = 16;
    // Test-only constructor for a synthetic YUV frame.
    // ignore: deprecated_member_use
    final frame = CameraImage.fromPlatformData({
      'format': 35,
      'height': height,
      'width': width,
      'planes': [
        {
          'bytes': Uint8List.fromList(List<int>.filled(width * height, 255)),
          'bytesPerPixel': 1,
          'bytesPerRow': width,
        },
        {
          'bytes': Uint8List.fromList(List<int>.filled(64, 128)),
          'bytesPerPixel': 1,
          'bytesPerRow': 8,
        },
        {
          'bytes': Uint8List.fromList(List<int>.filled(64, 128)),
          'bytesPerPixel': 1,
          'bytesPerRow': 8,
        },
      ],
    });
    final landmarks = List<Offset>.generate(
      21,
      (index) => Offset(0.25 + (index % 7) * 0.08, 0.3 + (index ~/ 7) * 0.15),
    );

    final crops = ImagePreprocessor.cameraImageToRgbCrops(
      frame,
      rotationDegrees: 0,
      mirrorHorizontally: false,
      normalizedLandmarks: landmarks,
    );
    final pixel = crops.context.getPixel(48, 48);

    expect(crops.context.width, 96);
    expect(crops.context.height, 96);
    expect(crops.context.numChannels, 3);
    expect(pixel.r, 255);
    expect(pixel.g, 255);
    expect(pixel.b, 255);
  });
}
