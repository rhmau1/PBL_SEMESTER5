import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sign_language/services/photo_recovery_preprocessor.dart';

img.Image scene({bool textured = false, bool largeDistractor = false}) {
  final image = img.Image(width: 200, height: 160, numChannels: 3);
  for (var y = 0; y < 160; y++) {
    for (var x = 0; x < 200; x++) {
      var value = textured ? (x * 13 + y * 7) % 256 : 255;
      if (x >= 110 && x < 150 && y >= 40 && y < 125) value = 80;
      if (largeDistractor && x >= 10 && x < 90 && y >= 10 && y < 145) {
        value = 30;
      }
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

List<Offset> handPoints() => List.generate(
  21,
  (i) => Offset((115 + i % 7 * 4) / 200, (45 + i ~/ 7 * 30) / 160),
);

void main() {
  test('plain foreground views retain the complete validated component', () {
    final prepared = PhotoRecoveryPreprocessor.prepare(
      PhotoRecoveryRequest(scene(), handPoints()),
    );
    expect(prepared, isNotNull);
    expect(prepared!.foregroundBounds, const Rect.fromLTWH(110, 40, 40, 85));
    for (final view in [prepared.context, prepared.tight, prepared.full]) {
      expect([view.width, view.height], [28, 28]);
      expect(view.getBytes().every((v) => v >= 0 && v <= 255), isTrue);
    }
    expect(prepared.context.numChannels, 1);
    expect(prepared.tight.numChannels, 1);
  });

  test('textured borders cannot activate contrast-based photo recovery', () {
    expect(
      PhotoRecoveryPreprocessor.prepare(
        PhotoRecoveryRequest(scene(textured: true), handPoints()),
      ),
      isNull,
    );
  });

  test('a larger unrelated component cannot substitute the MediaPipe hand', () {
    expect(
      PhotoRecoveryPreprocessor.prepare(
        PhotoRecoveryRequest(scene(largeDistractor: true), handPoints()),
      ),
      isNull,
    );
  });

  test('missing, nonfinite and outside-image landmarks are rejected', () {
    for (final points in [
      <Offset>[],
      List.filled(21, const Offset(double.nan, .5)),
      List.filled(21, const Offset(1.1, .5)),
    ]) {
      expect(
        PhotoRecoveryPreprocessor.prepare(
          PhotoRecoveryRequest(scene(), points),
        ),
        isNull,
      );
    }
  });

  test('an empty plain image cannot generate a foreground box', () {
    final empty = img.Image(width: 200, height: 160, numChannels: 3);
    img.fill(empty, color: img.ColorRgb8(255, 255, 255));
    expect(
      PhotoRecoveryPreprocessor.prepare(
        PhotoRecoveryRequest(empty, handPoints()),
      ),
      isNull,
    );
  });

  test(
    'recovery inputs can cross the compute isolate used by the classifier',
    () async {
      final prepared = await compute(
        PhotoRecoveryPreprocessor.prepare,
        PhotoRecoveryRequest(scene(), handPoints()),
      );
      expect(prepared, isNotNull);
      expect(prepared!.context.width, 28);
    },
  );
}
