import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/services/static_image_prediction_policy.dart';

void main() {
  const labels = ['A', 'B', 'C'];
  final policy = StaticImagePredictionPolicy.fromScores;

  test(
    'three strong agreeing views recover an uncertain photo without a target',
    () {
      final result = StaticImagePredictionPolicy.recoverUncertainPhoto(
        labels,
        primary: policy(labels, [.3, .5, .2]),
        full: policy(labels, [.90, .05, .05]),
        context: policy(labels, [.85, .10, .05]),
        tight: policy(labels, [.95, .02, .03]),
      );
      expect(result.label, 'A');
      expect(result.confidence, closeTo(.9, 1e-12));
      expect(result.scores.reduce((a, b) => a + b), closeTo(1, 1e-12));
    },
  );

  test('photo fallback never changes an already accepted result', () {
    final primary = policy(labels, [.05, .9, .05]);
    final other = policy(labels, [.99, .005, .005]);
    expect(
      StaticImagePredictionPolicy.recoverUncertainPhoto(
        labels,
        primary: primary,
        full: other,
        context: other,
        tight: other,
      ),
      same(primary),
    );
  });

  test('recovery is rejected when any view is weak or disagrees', () {
    final primary = policy(labels, [.3, .5, .2]);
    final strong = policy(labels, [.9, .05, .05]);
    for (final weakOrDifferent in [
      policy(labels, [.79, .15, .06]),
      policy(labels, [.05, .9, .05]),
    ]) {
      expect(
        StaticImagePredictionPolicy.recoverUncertainPhoto(
          labels,
          primary: primary,
          full: strong,
          context: strong,
          tight: weakOrDifferent,
        ),
        same(primary),
      );
    }
  });

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

  test(
    'a recovered crop cannot override a confident conflicting full photo',
    () {
      final crop = policy(labels, [.995, .003, .002]);
      final full = policy(labels, [.1, .88, .02]);
      final result = StaticImagePredictionPolicy.confirmRecoveredHand(
        labels,
        crop,
        full,
      );
      expect(result.label, crop.label);
      expect(result.confidence, closeTo(.59, 1e-12));
      expect(result.scores.reduce((a, b) => a + b), closeTo(1, 1e-12));
    },
  );

  test(
    'recovered crop is retained when the full view is inconclusive or agrees',
    () {
      final crop = policy(labels, [.1, .65, .25]);
      for (final full in [
        policy(labels, [.55, .4, .05]),
        policy(labels, [.05, .9, .05]),
      ]) {
        expect(
          StaticImagePredictionPolicy.confirmRecoveredHand(labels, crop, full),
          same(crop),
        );
      }
    },
  );
}
