class SignPrediction {
  const SignPrediction({
    required this.label,
    required this.confidence,
    required this.scores,
    this.agreement,
  });

  final String label;
  final double? confidence;
  final List<double> scores;
  final bool? agreement;

  bool get accepted => agreement ?? (confidence ?? 0) >= 0.60;

  String get confidenceText => confidence == null
      ? 'Tidak tersedia'
      : '${(confidence! * 100).toStringAsFixed(1)}%';
}
