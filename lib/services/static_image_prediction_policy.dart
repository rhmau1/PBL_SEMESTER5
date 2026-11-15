import '../models/sign_prediction.dart';

/// Combines fixed image views without consulting a target letter or user label.
class StaticImagePredictionPolicy {
  const StaticImagePredictionPolicy._();

  static SignPrediction fromScores(List<String> labels, List<double> scores) {
    if (labels.isEmpty ||
        labels.length != scores.length ||
        scores.any((score) => !score.isFinite)) {
      throw ArgumentError('Skor klasifikasi tidak sesuai dengan label model.');
    }
    var best = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[best]) best = i;
    }
    return SignPrediction(
      label: labels[best],
      confidence: scores[best],
      scores: List<double>.unmodifiable(scores),
    );
  }

  // Do not select whichever orientation is most confident: it can be wrong.
  static SignPrediction averageOrientations(
    List<String> labels,
    SignPrediction normal,
    SignPrediction mirrored,
  ) => fromScores(
    labels,
    List<double>.generate(
      labels.length,
      (i) => (normal.scores[i] + mirrored.scores[i]) / 2,
    ),
  );

  static SignPrediction combineCrops(
    List<String> labels,
    SignPrediction context,
    SignPrediction tight,
  ) {
    final blended = fromScores(
      labels,
      List<double>.generate(
        labels.length,
        (i) => context.scores[i] * 0.55 + tight.scores[i] * 0.45,
      ),
    );
    if (context.label == tight.label || blended.confidence <= 0.59) {
      return blended;
    }
    final uniform = 1 / labels.length;
    final scale = (0.59 - uniform) / (blended.confidence - uniform);
    return fromScores(
      labels,
      blended.scores
          .map((score) => uniform + (score - uniform) * scale)
          .toList(),
    );
  }

  /// A recovered detection cannot override a confident, conflicting full view.
  /// This is a rejection check, never a way to replace the predicted letter.
  static SignPrediction confirmRecoveredHand(
    List<String> labels,
    SignPrediction crop,
    SignPrediction fullImage,
  ) {
    if (fullImage.confidence < 0.60 ||
        crop.label == fullImage.label ||
        crop.confidence <= 0.59) {
      return crop;
    }
    final uniform = 1 / labels.length;
    final scale = (0.59 - uniform) / (crop.confidence - uniform);
    return fromScores(
      labels,
      crop.scores.map((score) => uniform + (score - uniform) * scale).toList(),
    );
  }

  /// An uncertain still photo can be recovered only by three strong, agreeing
  /// views. The caller must first validate the background and foreground ROI.
  /// An already accepted prediction is never replaced by this fallback.
  static SignPrediction recoverUncertainPhoto(
    List<String> labels, {
    required SignPrediction primary,
    required SignPrediction full,
    required SignPrediction context,
    required SignPrediction tight,
  }) {
    if (primary.confidence >= 0.60) return primary;
    final views = [full, context, tight];
    if (views.any((p) => p.confidence < 0.80 || p.label != full.label)) {
      return primary;
    }
    return fromScores(
      labels,
      List<double>.generate(
        labels.length,
        (i) => (full.scores[i] + context.scores[i] + tight.scores[i]) / 3,
      ),
    );
  }
}
