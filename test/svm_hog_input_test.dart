import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sign_language/services/svm_hog_classifier.dart';
import 'package:sign_language/services/svm_hog_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rotates a stride-padded luma frame', () {
    final input = Uint8List.fromList([1, 2, 99, 3, 4, 99, 5, 6, 99]);
    final image = SvmHogInput.fromLuma(input, 2, 3, 3, 1, 90)!;
    expect([image.width, image.height], [3, 2]);
    expect(image.getBytes(), [5, 3, 1, 6, 4, 2]);
    expect(SvmHogInput.fromLuma(input, 3, 5, 3, 1, 90), isNull);
  });

  test('two square crops retain an off-center foreground', () {
    final image = img.Image(width: 150, height: 120, numChannels: 1);
    img.fill(image, color: img.ColorUint8.rgb(230, 230, 230));
    img.fillRect(
      image,
      x1: 15,
      y1: 20,
      x2: 36,
      y2: 94,
      color: img.ColorUint8.rgb(70, 70, 70),
    );
    final result = SvmHogInput.prepareHandCrops(image).crops;
    expect(result, hasLength(2));
    for (final crop in result) {
      expect(crop, hasLength(64 * 64));
      expect(crop[32 * 64 + 32], 70);
      expect(crop[0], 230);
    }
  });

  test('how tightly the photo is framed changes foreground size', () {
    final image = img.Image(width: 160, height: 160, numChannels: 1);
    img.fill(image, color: img.ColorUint8.rgb(230, 230, 230));
    img.fillRect(
      image,
      x1: 24,
      y1: 42,
      x2: 90,
      y2: 108,
      color: img.ColorUint8.rgb(70, 70, 70),
    );
    final tight = SvmHogInput.prepareHandCrops(image);
    final wide = SvmHogInput.prepareHandCrops(image, tightFraming: false);
    expect(tight.rejection, isNull);
    expect(wide.rejection, isNull);
    for (var i = 0; i < 2; i++) {
      expect(
        tight.crops[i].where((pixel) => pixel < 150).length,
        greaterThan(wide.crops[i].where((pixel) => pixel < 150).length),
      );
    }
  });

  test('foreground failure gives a reason before classification', () {
    final image = img.Image(width: 96, height: 96, numChannels: 1);
    final result = SvmHogInput.prepareHandCrops(image);
    expect(result.crops, isEmpty);
    expect(result.rejection, contains('kurang kontras'));
  });

  test('compensates for smooth lighting on photos', () {
    final image = img.Image(width: 128, height: 96, numChannels: 1);
    for (final pixel in image) {
      final foreground =
          pixel.x >= 44 && pixel.x <= 76 && pixel.y >= 23 && pixel.y <= 70;
      final gain = 0.48 + 0.5 * pixel.x / 127;
      pixel.r = ((foreground ? 95 : 245) * gain).round();
    }
    final baseline = SvmHogInput.prepareHandCrops(
      image,
      includePhotoChecks: true,
      correctUnevenLighting: false,
    );
    expect(baseline.rejection, contains('Tepi foto terlalu bervariasi'));
    final corrected = SvmHogInput.prepareHandCrops(
      image,
      includePhotoChecks: true,
    );
    expect(corrected.rejection, isNull);
    expect(corrected.crops.first[32 * 64 + 32], lessThan(100));
    expect(corrected.crops.first.first, greaterThan(150));
  });

  test('a sharp boundary or a handless gradient gives no crops', () {
    final image = img.Image(width: 128, height: 96, numChannels: 1);
    for (final pixel in image) {
      pixel.r = pixel.x < 64 ? 110 : 240;
    }
    final sharp = SvmHogInput.prepareHandCrops(image, includePhotoChecks: true);
    expect(sharp.rejection, contains('Tepi foto terlalu bervariasi'));
    for (final pixel in image) {
      pixel.r = (110 + 130 * pixel.x / 127).round();
    }
    final smooth = SvmHogInput.prepareHandCrops(
      image,
      includePhotoChecks: true,
    );
    expect(smooth.crops, isEmpty);
    expect(smooth.rejection, contains('kurang kontras'));
  });

  test(
    'photo checks reuse the tight crop and preserve both baseline inputs',
    () {
      final image = img.Image(width: 150, height: 120, numChannels: 1);
      img.fill(image, color: img.ColorUint8.rgb(230, 230, 230));
      img.fillRect(
        image,
        x1: 15,
        y1: 20,
        x2: 36,
        y2: 94,
        color: img.ColorUint8.rgb(70, 70, 70),
      );
      final baseline = SvmHogInput.prepareHandCrops(image).crops;
      final photos = SvmHogInput.prepareHandCrops(
        image,
        includePhotoChecks: true,
      ).crops;
      expect(photos, hasLength(4));
      expect(photos.first, baseline.first);
      expect(photos.last, baseline.last);
      expect(photos[1], baseline.first.map((pixel) => 255 - pixel));
      expect(photos[2], hasLength(64 * 64));
    },
  );

  test(
    'real classifier rejects blank input after loading the bundled asset',
    () async {
      final classifier = SvmHogClassifier.instance;
      await Future.wait([classifier.initialize(), classifier.initialize()]);
      final prediction = await classifier.classifyLuma(
        bytes: Uint8List(96 * 96),
        width: 96,
        height: 96,
        stride: 96,
        pixelStride: 1,
        rotation: 0,
      );
      expect(prediction, isNull);
    },
  );

  test(
    'file inference returns an SVM result through the backend API',
    () async {
      final directory = await Directory.systemTemp.createTemp('svm_hog_test_');
      addTearDown(() => directory.delete(recursive: true));
      final image = img.Image(width: 150, height: 120, numChannels: 3);
      img.fill(image, color: img.ColorUint8.rgb(230, 230, 230));
      img.fillRect(
        image,
        x1: 25,
        y1: 25,
        x2: 65,
        y2: 95,
        color: img.ColorUint8.rgb(70, 70, 70),
      );
      final path = '${directory.path}/foreground.png';
      await File(path).writeAsBytes(img.encodePng(image));
      final prediction = await SvmHogClassifier.instance.classifyFile(path);
      expect('ABCDEFGHIKLMNOPQRSTUVWXY', contains(prediction.label));
      expect(prediction.scores, hasLength(24));
      expect(prediction.scores.every((score) => score.isFinite), isTrue);
    },
  );
}
