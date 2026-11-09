import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/services/static_image_prediction_policy.dart';

void main() {
  const labels = ['A', 'B', 'C'];
  final policy = StaticImagePredictionPolicy.fromScores;

  test('normal and mirrored views give the same combined prediction in either order', () {
    final a = policy(labels, [.8, .15, .05]);
    final b = policy(labels, [.6, .3, .1]);
    final ab = StaticImagePredictionPolicy.averageOrientations(labels, a, b);
    final ba = StaticImagePredictionPolicy.averageOrientations(labels, b, a);
    expect(ab.scores, ba.scores);
    expect(ab.label, 'A');
    expect(ab.confidence, closeTo(.7, 1e-12));
    expect(ab.scores.reduce((a, b) => a + b), closeTo(1, 1e-12));
  });

  test('a confident disagreement between orientations cannot win by max confidence', () {
    final normal = policy(labels, [.99, .005, .005]);
    final mirrored = policy(labels, [.005, .99, .005]);
    final result = StaticImagePredictionPolicy.averageOrientations(
      labels,
      normal,
      mirrored,
    );
    expect(result.confidence, lessThan(.6));
  });

  test(
    'crop disagreement remains below the existing upload acceptance limit',
    () {
      final context = policy(labels, [.99, .005, .005]);
      final tight = policy(labels, [.2, .79, .01]);
      final result = StaticImagePredictionPolicy.combineCrops(
        labels,
        context,
        tight,
      );
      expect(result.confidence, closeTo(.59, 1e-12));
      expect(result.scores.reduce((a, b) => a + b), closeTo(1, 1e-12));
    },
  );

  test('agreeing crops keep the existing 55:45 weighting', () {
    final result = StaticImagePredictionPolicy.combineCrops(
      labels,
      policy(labels, [.8, .1, .1]),
      policy(labels, [.6, .2, .2]),
    );
    expect(result.label, 'A');
    expect(result.confidence, closeTo(.71, 1e-12));
  });

  test('invalid model scores are rejected', () {
    expect(() => policy(labels, [1, 0]), throwsArgumentError);
    expect(() => policy(labels, [double.nan, 0, 0]), throwsArgumentError);
  });
}
