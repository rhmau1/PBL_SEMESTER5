class SignPrediction {
  const SignPrediction({
    required this.label,
    required this.confidence,
    required this.scores,
  });

  final String label;
  final double confidence;
  final List<double> scores;

  String get confidenceText => '${(confidence * 100).toStringAsFixed(1)}%';
}
