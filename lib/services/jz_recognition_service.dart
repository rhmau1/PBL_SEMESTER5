import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../models/hand_landmark_frame.dart';
import '../models/jz_clip_result.dart';
import 'jz_camera_frame_encoder.dart';
import 'jz_classifier.dart';
import 'jz_hand_detector.dart';
import 'jz_sequence_preprocessor.dart';

enum JzCaptureState { idle, starting, capturing, finishing, disposed }

/// Backend for an explicitly delimited J/Z gesture. Does not own the camera,
/// alter a widget, or replace/retune the static 24-letter classifier.
class JzRecognitionService {
  JzRecognitionService({
    JzClassifier? classifier,
    JzHandDetector? detector,
    JzSequencePreprocessor? preprocessor,
  }) : _classifier = classifier ?? JzClassifier(),
       _detector = detector ?? PlatformJzHandDetector(),
       _preprocessor = preprocessor ?? const JzSequencePreprocessor();

  final JzClassifier _classifier;
  final JzHandDetector _detector;
  final JzSequencePreprocessor _preprocessor;
  final List<HandLandmarkFrame> _frames = [];
  JzCaptureState _state = JzCaptureState.idle;
  Future<void>? _transition;
  Future<JzFrameReceipt>? _pendingFrame;
  Future<void>? _cancellation;
  Future<void>? _closing;
  bool _disposeRequested = false;
  bool _ownsDetector = false;
  JzBackendException? _frameFailure;
  int? _lastReceivedMs;
  double? _nextSampleMs;
  int? _rotation;
  int _skippedBusy = 0;
  int _skippedInterval = 0;

  JzCaptureState get state => _state;
  int get sampledFrames => _frames.length;

  Future<void> startClip() {
    _checkOpen();
    if (_state != JzCaptureState.idle || _cancellation != null) {
      throw const JzBackendException('busy', 'Selesaikan gerakan sebelumnya.');
    }
    _reset();
    _state = JzCaptureState.starting;
    return _trackTransition(_start());
  }

  Future<void> _start() async {
    try {
      await _classifier.initialize();
      _checkOpen();
      await _detector.startClip();
      _ownsDetector = true;
      _checkOpen();
      _state = JzCaptureState.capturing;
    } catch (error) {
      try {
        await _releaseDetector();
      } finally {
        _state = JzCaptureState.idle;
      }
      throw _asBackendError(error);
    }
  }

  /// timestampMs is monotonic acquisition time (e.g. one Stopwatch per clip).
  /// Supply the upright rotation of the raw buffer, without preview mirroring.
  Future<JzFrameReceipt> addCameraFrame(
    CameraImage image, {
    required int timestampMs,
    required int rotationDegrees,
  }) {
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    if (!const [0, 90, 180, 270].contains(rotation)) {
      throw const JzBackendException('invalid_frame', 'Rotasi tidak valid.');
    }
    if (_rotation != null && _rotation != rotation) {
      const failure = JzBackendException(
        'geometry_changed',
        'Orientasi kamera berubah. Mulai gerakan baru.',
      );
      _frameFailure = failure;
      throw failure;
    }
    _rotation = rotation;
    return _addSample(
      timestampMs,
      () => encodeJzCameraFrame(image, rotationDegrees: rotation),
    );
  }

  /// For decoded video sources: one fresh, upright, unmirrored JPEG <=640px
  /// on the longest side. This does not accept a whole MP4 or a still gesture.
  Future<JzFrameReceipt> addJpegFrame(
    Uint8List uprightJpeg, {
    required int timestampMs,
  }) => _addSample(timestampMs, () async => Uint8List.fromList(uprightJpeg));

  Future<JzFrameReceipt> _addSample(
    int timestampMs,
    Future<Uint8List> Function() encode,
  ) {
    _checkOpen();
    if (_state != JzCaptureState.capturing || _cancellation != null) {
      throw const JzBackendException(
        'clip_not_started',
        'Mulai gerakan dahulu.',
      );
    }
    if (_frameFailure case final failure?) throw failure;
    if (timestampMs < 0 ||
        timestampMs > 9223372036854775 ||
        (_lastReceivedMs != null && timestampMs <= _lastReceivedMs!)) {
      throw const JzBackendException(
        'invalid_timestamp',
        'Waktu setiap frame harus bertambah dan tidak boleh dipakai ulang.',
      );
    }
    _lastReceivedMs = timestampMs;
    if (_pendingFrame != null) {
      _skippedBusy++;
      return Future.value(
        JzFrameReceipt(
          timestampMs: timestampMs,
          status: JzFrameStatus.skippedBusy,
        ),
      );
    }
    final nextSampleMs = _nextSampleMs ?? timestampMs.toDouble();
    if (timestampMs + 0.000001 < nextSampleMs) {
      _skippedInterval++;
      return Future.value(
        JzFrameReceipt(
          timestampMs: timestampMs,
          status: JzFrameStatus.skippedInterval,
        ),
      );
    }
    const periodMs = 1000 / JzSequencePreprocessor.sampleFps;
    final elapsedPeriods =
        ((timestampMs + 0.000001 - nextSampleMs) / periodMs).floor() + 1;
    _nextSampleMs = nextSampleMs + elapsedPeriods * periodMs;
    late final Future<JzFrameReceipt> pending;
    pending = _detectSample(timestampMs, encode).whenComplete(() {
      if (identical(_pendingFrame, pending)) _pendingFrame = null;
    });
    _pendingFrame = pending;
    return pending;
  }

  Future<JzFrameReceipt> _detectSample(
    int timestampMs,
    Future<Uint8List> Function() encode,
  ) async {
    try {
      final frame = await _detector.detectFrame(
        await encode(),
        timestampMs: timestampMs,
      );
      if (frame.timestampMs != timestampMs) {
        throw const FormatException('MediaPipe mengembalikan frame lama.');
      }
      _frames.add(frame);
      return JzFrameReceipt(
        timestampMs: timestampMs,
        status: JzFrameStatus.sampled,
      );
    } catch (error) {
      final failure = _asBackendError(error);
      _frameFailure = failure;
      throw failure;
    }
  }

  Future<JzClipResult> finishClip() {
    _checkOpen();
    if (_state != JzCaptureState.capturing || _cancellation != null) {
      throw const JzBackendException(
        'clip_not_started',
        'Tidak ada gerakan aktif.',
      );
    }
    _state = JzCaptureState.finishing;
    late JzClipResult result;
    final operation = _finish().then<void>((value) {
      result = value;
    });
    return _trackTransition(operation).then((_) => result);
  }

  Future<JzClipResult> _finish() async {
    try {
      await _pendingFrame;
      if (_frameFailure case final failure?) throw failure;
      final prepared = _preprocessor.prepare(_frames);
      final prediction = await _classifier.classifyFeatures(prepared.features);
      final status = prediction.acceptedLabel != null
          ? JzClipStatus.recognized
          : prediction.rawLabel == 'OTHER'
          ? JzClipStatus.other
          : JzClipStatus.uncertain;
      return JzClipResult(
        status: status,
        prediction: prediction,
        quality: {
          ...prepared.quality,
          ..._captureQuality,
          'actual_sample_fps':
              (prepared.sampledFrames - 1) / prepared.durationSeconds,
        },
      );
    } on JzSequenceException catch (error) {
      return JzClipResult(
        status: JzClipStatus.rejected,
        rejectionCode: error.code,
        message: error.message,
        quality: _captureQuality,
      );
    } catch (error) {
      throw _asBackendError(error);
    } finally {
      try {
        await _releaseDetector();
      } finally {
        _reset();
        _state = JzCaptureState.idle;
      }
    }
  }

  Map<String, Object> get _captureQuality => {
    'sampled_frames': _frames.length,
    'requested_sample_fps': JzSequencePreprocessor.sampleFps,
    'skipped_busy': _skippedBusy,
    'skipped_interval': _skippedInterval,
  };

  Future<void> cancelClip() => _cancellation ??= _cancel().whenComplete(() {
    _cancellation = null;
  });

  Future<void> _cancel() async {
    if (_state == JzCaptureState.disposed) return;
    try {
      await _transition;
    } catch (_) {
      // A failing start/finish already reports to its caller.
    }
    try {
      await _pendingFrame;
    } catch (_) {
      // The frame caller receives the failure; cancellation releases resources.
    }
    try {
      await _releaseDetector();
    } finally {
      _reset();
      _state = JzCaptureState.idle;
    }
  }

  Future<void> dispose() {
    _disposeRequested = true;
    return _closing ??= _dispose();
  }

  Future<void> _dispose() async {
    try {
      await cancelClip();
    } finally {
      try {
        await _classifier.close();
      } finally {
        _state = JzCaptureState.disposed;
      }
    }
  }

  Future<void> _releaseDetector() async {
    if (!_ownsDetector) return;
    _ownsDetector = false;
    try {
      await _detector.finishClip();
    } on PlatformException catch (error) {
      if (error.code != 'clip_not_started') throw _asBackendError(error);
    }
  }

  Future<void> _trackTransition(Future<void> operation) async {
    _transition = operation;
    try {
      await operation;
    } finally {
      if (identical(_transition, operation)) _transition = null;
    }
  }

  void _checkOpen() {
    if (_disposeRequested) {
      throw const JzBackendException('disposed', 'Layanan J/Z sudah ditutup.');
    }
  }

  void _reset() {
    _frames.clear();
    _frameFailure = null;
    _lastReceivedMs = null;
    _nextSampleMs = null;
    _rotation = null;
    _skippedBusy = 0;
    _skippedInterval = 0;
  }

  static JzBackendException _asBackendError(Object error) => switch (error) {
    JzBackendException() => error,
    PlatformException() => JzBackendException(
      error.code,
      error.message ?? 'MediaPipe gagal memproses gerakan.',
    ),
    MissingPluginException() => const JzBackendException(
      'unsupported_platform',
      'Deteksi J/Z memerlukan backend Android yang telah dikompilasi ulang.',
    ),
    FormatException() => JzBackendException('invalid_frame', error.message),
    UnsupportedError() => JzBackendException(
      'invalid_frame',
      error.message ?? '',
    ),
    _ => JzBackendException('processing_failed', error.toString()),
  };
}
