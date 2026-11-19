import 'jz_prediction.dart';

enum JzClipStatus { recognized, other, uncertain, rejected }

/// One complete gesture clip, not a transcript of an arbitrary long video.
class JzClipResult {
  JzClipResult({
    required this.status,
    this.prediction,
    this.rejectionCode,
    this.message,
    Map<String, Object> quality = const {},
  }) : quality = Map.unmodifiable(quality);

  final JzClipStatus status;
  final JzPrediction? prediction;
  final String? rejectionCode;
  final String? message;
  final Map<String, Object> quality;

  String? get letter =>
      status == JzClipStatus.recognized ? prediction?.acceptedLabel : null;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'letter': letter,
    'prediction': prediction == null
        ? null
        : {
            'raw_label': prediction!.rawLabel,
            'confidence': prediction!.confidence,
            'labels': JzPrediction.labels,
            'scores': prediction!.scores,
          },
    'quality': quality,
    'rejection': rejectionCode == null
        ? null
        : {'code': rejectionCode, 'message': message},
  };
}

enum JzFrameStatus { sampled, skippedBusy, skippedInterval }

class JzFrameReceipt {
  const JzFrameReceipt({
    required this.timestampMs,
    required this.status,
    this.handDetected,
  });

  final int timestampMs;
  final JzFrameStatus status;

  /// Present only for a newly sampled detector observation.
  final bool? handDetected;
}

class JzBackendException implements Exception {
  const JzBackendException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'JzBackendException($code): $message';
}
