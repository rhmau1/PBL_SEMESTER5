import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sign_language/services/image_preprocessor.dart';
import 'package:sign_language/services/sign_classifier.dart';
import 'package:sign_language/services/still_image_hand_detector.dart';

const _channel = MethodChannel('latih_isyarat/image_hand_landmarker');

List<List<double>> _hand() => List.generate(
  21,
  (i) => [0.70 + 0.20 * (i % 7) / 6, 0.65 + 0.25 * (i ~/ 7) / 2],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const detector = StillImageHandDetector();

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test(
    'applies EXIF once and downsizes the full photo proportionally',
    () async {
      final directory = await Directory.systemTemp.createTemp('upload_exif_');
      addTearDown(() => directory.delete(recursive: true));
      final image = img.Image(width: 1200, height: 600);
      image.exif.imageIfd.orientation = 6;
      final file = File('${directory.path}/rotated.jpg');
      await file.writeAsBytes(img.encodeJpg(image));
      final upright = await detector.loadImage(file.path);
      expect([upright.width, upright.height], [512, 1024]);
      expect(upright.exif.imageIfd.orientation, anyOf(isNull, 1));
    },
  );

  for (final entry in {
    'camera photo': SignClassifier.instance.classifyFile,
    'upload': SignClassifier.instance.classifyUploadFile,
  }.entries) {
    for (final handCount in [0, 2]) {
      test(
        '${entry.key} rejects $handCount hands before loading or running CNN',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'upload_no_hand_',
          );
          addTearDown(() => directory.delete(recursive: true));
          final file = File('${directory.path}/empty.png');
          await file.writeAsBytes(
            img.encodePng(img.Image(width: 40, height: 40)),
          );
          var calls = 0;
          messenger.setMockMethodCallHandler(_channel, (_) async {
            calls++;
            return List.generate(handCount, (_) => _hand());
          });
          await expectLater(
            entry.value(file.path),
            throwsA(isA<HandImageException>()),
          );
          expect(calls, 1);
          expect(SignClassifier.instance.isReady, isFalse);
        },
      );
    }
  }

  test(
    'sends a complete image to IMAGE mode, preserving its dimensions',
    () async {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        expect(call.method, 'detect');
        final bytes = (call.arguments as Map)['bytes'] as Uint8List;
        final image = img.decodeJpg(bytes)!;
        expect([image.width, image.height], [200, 160]);
        return [_hand()];
      });
      final landmarks = await detector.detect(
        img.Image(width: 200, height: 160),
      );
      expect(landmarks, hasLength(21));
      expect(landmarks.first, const Offset(0.70, 0.65));
    },
  );

  test(
    'rejects no hand instead of sending the center/background to CNN',
    () async {
      messenger.setMockMethodCallHandler(_channel, (_) async => []);
      await expectLater(
        detector.detect(img.Image(width: 40, height: 40)),
        throwsA(
          isA<HandImageException>().having(
            (error) => error.message,
            'message',
            contains('Tangan tidak terdeteksi'),
          ),
        ),
      );
    },
  );

  test('requires one hand rather than silently choosing between two', () async {
    messenger.setMockMethodCallHandler(
      _channel,
      (_) async => [_hand(), _hand()],
    );
    await expectLater(
      detector.detect(img.Image(width: 40, height: 40)),
      throwsA(
        isA<HandImageException>().having(
          (error) => error.message,
          'message',
          contains('satu tangan'),
        ),
      ),
    );
  });

  test('both crops follow an off-center hand and remain square', () {
    final image = img.Image(width: 200, height: 160);
    for (var y = 104; y < 144; y++) {
      for (var x = 140; x < 180; x++) {
        image.setPixelRgb(x, y, 240, 240, 240);
      }
    }
    final landmarks = _hand().map((p) => Offset(p[0], p[1])).toList();
    final crops = ImagePreprocessor.imageToGrayHandCrops(
      image,
      normalizedLandmarks: landmarks,
    );
    for (final crop in [crops.context, crops.tight]) {
      expect([crop.width, crop.height], [28, 28]);
      expect(crop.getPixel(14, 14).r, greaterThan(200));
      expect(crop.getPixel(0, 0).r, lessThan(20));
    }
    // The old center crop does not place this hand at the model's center.
    expect(ImagePreprocessor.toModelImage(image).getPixel(14, 14).r, 0);
  });
}
