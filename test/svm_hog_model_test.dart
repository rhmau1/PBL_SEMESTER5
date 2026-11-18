import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/services/svm_hog_model.dart';

void main() {
  test('SVM-HOG matches scikit-learn on its reference images', () {
    final model = SvmHogModel(
      File('assets/models/svm_hog.bin.gz').readAsBytesSync(),
    );
    final cases = jsonDecode(
      File('test/fixtures/svm_hog_reference.json').readAsStringSync(),
    ) as List<dynamic>;
    expect(cases.length, greaterThanOrEqualTo(24));
    for (final row in cases.cast<Map<String, dynamic>>()) {
      final hex = row['pixels'] as String;
      final pixels = Uint8List.fromList(
        List.generate(
          hex.length ~/ 2,
          (index) =>
              int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16),
        ),
      );
      final result = model.predict(SvmHogModel.hog(pixels));
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
}
