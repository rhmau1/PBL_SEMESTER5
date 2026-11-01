/// One temporal-model decision. OTHER is an abstention, never a letter.
class JzPrediction {
  JzPrediction.fromScores(List<double> values) : scores = _validated(values) {
    var best = 0;
    for (var index = 1; index < scores.length; index++) {
      if (scores[index] > scores[best]) best = index;
    }
    rawLabel = labels[best];
    confidence = scores[best];
  }

  static const labels = <String>['J', 'Z', 'OTHER'];
  static const acceptanceThreshold = 0.60;

  final List<double> scores;
  late final String rawLabel;
  late final double confidence;

  /// Null means that the frontend must not append a J/Z letter.
  String? get acceptedLabel =>
      rawLabel != 'OTHER' && confidence >= acceptanceThreshold
      ? rawLabel
      : null;

  static List<double> _validated(List<double> values) {
    if (values.length != labels.length ||
        values.any((value) => !value.isFinite || value < 0 || value > 1) ||
        (values.fold<double>(0, (sum, value) => sum + value) - 1).abs() >
            0.001) {
      throw StateError('Skor model J/Z harus berisi tiga probabilitas valid.');
    }
    return List<double>.unmodifiable(values);
  }
}
