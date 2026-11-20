import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/services/random_forest_hog_model.dart';

void main() {
  final model = RandomForestHogModel(
    File('assets/models/random_forest_hog.bin.gz').readAsBytesSync(),
  );

  test('matches scikit-learn probabilities for representative HOG vectors', () {
    final inputs = [
      Float32List(1764),
      Float32List.fromList(
        List.generate(1764, (index) => ((index * 37) % 101) / 500.0),
      ),
      Float32List.fromList(
        List.generate(1764, (index) => (index % 7) * 0.03125),
      ),
    ];
    const expectedLabels = ['R', 'P', 'P'];
    const expectedScores = [
      [
        0.0,
        0.022751826749,
        0.081320181222,
        0.015095813581,
        0.0,
        0.033936235438,
        0.016523809524,
        0.06,
        0.036830252101,
        0.10914873305,
        0.064811521773,
        0.026965467238,
        0.04,
        0.043146762808,
        0.044697160238,
        0.06733368672,
        0.113394713395,
        0.01,
        0.012530296411,
        0.014765669113,
        0.025180008691,
        0.066586339207,
        0.054981522742,
        0.04,
      ],
      [
        0.03,
        0.02,
        0.042770185437,
        0.032577865487,
        0.024642368535,
        0.067842748931,
        0.022514953359,
        0.073477713702,
        0.022318013132,
        0.022767753698,
        0.040544420976,
        0.056272873632,
        0.06,
        0.034807323517,
        0.131119146717,
        0.090043660782,
        0.012319120624,
        0.04379598103,
        0.022167211864,
        0.0,
        0.007760920743,
        0.030816575764,
        0.040525800195,
        0.070915361873,
      ],
      [
        0.042516985433,
        0.009571860489,
        0.013994838521,
        0.02,
        0.01,
        0.05338269096,
        0.036240227543,
        0.055204267355,
        0.03,
        0.028084745763,
        0.034988670867,
        0.03,
        0.009895803962,
        0.054128157733,
        0.150428349627,
        0.086580557444,
        0.002164747434,
        0.051301220314,
        0.068960000206,
        0.011915254237,
        0.004373532248,
        0.036103870319,
        0.116113427726,
        0.044050791821,
      ],
    ];

    for (var inputIndex = 0; inputIndex < inputs.length; inputIndex++) {
      final result = model.predict(inputs[inputIndex]);
      expect(result.label, expectedLabels[inputIndex]);
      expect(result.scores, hasLength(expectedScores[inputIndex].length));
      for (
        var scoreIndex = 0;
        scoreIndex < result.scores.length;
        scoreIndex++
      ) {
        expect(
          result.scores[scoreIndex],
          closeTo(expectedScores[inputIndex][scoreIndex], 1e-8),
        );
      }
    }
  });
}
