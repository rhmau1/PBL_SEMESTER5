import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/services/svm_hog_model.dart';

Uint8List _pixels(Map<String, dynamic> row) {
  final hex = row['pixels'] as String;
  return Uint8List.fromList(
    List.generate(
      hex.length ~/ 2,
      (index) => int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
    ),
  );
}

void main() {
  final cases = (jsonDecode(
    File('test/fixtures/svm_hog_reference.json').readAsStringSync(),
  ) as List<dynamic>).cast<Map<String, dynamic>>();

  test('SVM-HOG matches scikit-learn on its reference images', () {
    final model = SvmHogModel(
      File('assets/models/svm_hog.bin.gz').readAsBytesSync(),
    );
    expect(cases.length, greaterThanOrEqualTo(24));
    for (final row in cases) {
      final result = model.predict(SvmHogModel.hog(_pixels(row)));
      expect(result.label, row['label'], reason: row['name'] as String);
      final scores = row['scores'] as List<dynamic>;
      for (var i = 0; i < scores.length; i++) {
        expect(
          result.scores[i],
          closeTo(scores[i] as num, 0.0002),
          reason: '${row['name']} score $i',
        );
      }
    }
  });

  test(
    'photo detail can correct an accepted label but cannot accept a new one',
    () {
      final model = SvmHogModel(
        File('assets/models/svm_hog.bin.gz').readAsBytesSync(),
      );
      final a = _pixels(cases.firstWhere((row) => row['label'] == 'A'));
      final b = _pixels(cases.firstWhere((row) => row['label'] == 'B'));
      final c = _pixels(cases.firstWhere((row) => row['label'] == 'C'));
      expect(model.predictCrops([a, a, b, a]).label, 'A');
      final corrected = model.predictCrops([a, a, b, b, a]);
      expect(corrected.accepted, isTrue);
      expect(corrected.label, 'B');
      expect(model.predictCrops([a, a, b, b, c]).accepted, isFalse);
      expect(model.predictCrops([a, a, b, c, a]).label, 'A');
      expect(model.predictCrops([a, c, c, b, a]).label, 'C');
    },
  );
}
