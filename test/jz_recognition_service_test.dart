import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/models/hand_landmark_frame.dart';
import 'package:sign_language/models/jz_clip_result.dart';
import 'package:sign_language/services/jz_classifier.dart';
import 'package:sign_language/services/jz_hand_detector.dart';
import 'package:sign_language/services/jz_recognition_service.dart';

HandLandmarkFrame _handFrame(int timestampMs, {bool visible = true}) =>
    HandLandmarkFrame(
      timestampMs: timestampMs,
      width: 640,
      height: 480,
      hands: visible
          ? [
              List.generate(
                21,
                (index) => HandLandmarkPoint(
                  x: 0.2 + timestampMs * 0.0001 + index * 0.006,
                  y: 0.5 - index * 0.008,
                  z: index * 0.001,
                ),
              ),
            ]
          : [],
    );

class _Detector implements JzHandDetector {
  Completer<void>? startGate;
  Completer<void>? frameGate;
  final startEntered = Completer<void>();
  Completer<void> frameEntered = Completer<void>();
  HandLandmarkFrame Function(int) frameFor = _handFrame;
  final timestamps = <int>[];
  var starts = 0;
  var finishes = 0;
  var disposals = 0;
  var failStarts = 0;
  var active = false;

  @override
  Future<void> startClip() async {
    starts++;
    if (!startEntered.isCompleted) startEntered.complete();
    await startGate?.future;
    if (failStarts > 0) {
      failStarts--;
      throw PlatformException(code: 'detector_start_failed');
    }
    expect(active, isFalse, reason: 'A new clip must have a fresh tracker.');
    active = true;
  }

  @override
  Future<HandLandmarkFrame> detectFrame(
    Uint8List uprightJpeg, {
    required int timestampMs,
  }) async {
    expect(active, isTrue);
    timestamps.add(timestampMs);
    if (!frameEntered.isCompleted) frameEntered.complete();
    await frameGate?.future;
    expect(
      active,
      isTrue,
      reason: 'Do not release a tracker during inference.',
    );
    return frameFor(timestampMs);
  }

  @override
  Future<void> finishClip() async {
    expect(active, isTrue);
    finishes++;
    active = false;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    active = false;
  }
}

class _Runner implements JzScoreRunner {
  List<double> scores = [0.8, 0.1, 0.1];
  final tensors = <List<List<double>>>[];
  var closes = 0;

  @override
  Future<List<double>> run(List<List<double>> features) async {
    tensors.add(features);
    return scores;
  }

  @override
  Future<void> close() async => closes++;
}

Matcher _backendError(String code) => throwsA(
  isA<JzBackendException>().having((error) => error.code, 'code', code),
);

CameraImage _cameraFrame() => CameraImage.fromPlatformInterface(
  CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 0),
    width: 2,
    height: 2,
    planes: [
      CameraImagePlane(
        bytes: Uint8List.fromList(List.filled(16, 128)),
        bytesPerRow: 8,
        bytesPerPixel: 4,
      ),
    ],
  ),
);

Future<void> _sendFrames(
  JzRecognitionService service, {
  int count = 6,
  int startMs = 0,
  bool handDetected = true,
}) async {
  for (var index = 0; index < count; index++) {
    final timestamp = startMs + index * 67;
    final receipt = await service.addJpegFrame(
      Uint8List.fromList([timestamp & 255]),
      timestampMs: timestamp,
    );
    expect(receipt.timestampMs, timestamp);
    expect(receipt.status, JzFrameStatus.sampled);
    expect(receipt.handDetected, handDetected);
  }
}

void main() {
  late _Detector detector;
  late _Runner runner;
  late JzRecognitionService service;

  setUp(() {
    detector = _Detector();
    runner = _Runner();
    service = JzRecognitionService(
      detector: detector,
      classifier: JzClassifier(scoreRunnerFactory: () async => runner),
    );
  });

  tearDown(() async => service.dispose());

  test(
    'fresh frame clip produces one J decision and releases its tracker',
    () async {
      expect(service.state, JzCaptureState.idle);
      await service.startClip();
      expect(service.state, JzCaptureState.capturing);
      await _sendFrames(service);
      final result = await service.finishClip();
      expect(result.status, JzClipStatus.recognized);
      expect(result.letter, 'J');
      expect(result.toJson()['letter'], 'J');
      expect(result.quality['sampled_frames'], 6);
      expect(result.quality['detected_frames'], 6);
      expect(result.quality['skipped_busy'], 0);
      expect(result.quality['skipped_interval'], 0);
      expect(runner.tensors, hasLength(1));
      expect(runner.tensors.single, hasLength(48));
      expect(runner.tensors.single.first, hasLength(64));
      expect(detector.starts, 1);
      expect(detector.finishes, 1);
      expect(service.state, JzCaptureState.idle);
      expect(service.sampledFrames, 0);
    },
  );

  test(
    'no-hand observations reject before any temporal model inference',
    () async {
      detector.frameFor = (timestamp) => _handFrame(timestamp, visible: false);
      await service.startClip();
      await _sendFrames(service, handDetected: false);
      final result = await service.finishClip();
      expect(result.status, JzClipStatus.rejected);
      expect(result.rejectionCode, 'too_few_detected_samples');
      expect(result.letter, isNull);
      expect(result.prediction, isNull);
      expect(runner.tensors, isEmpty);
      expect(detector.finishes, 1);
    },
  );

  test('OTHER and low confidence never append a letter', () async {
    for (final outcome in [
      ([0.01, 0.01, 0.98], JzClipStatus.other),
      ([0.55, 0.25, 0.2], JzClipStatus.uncertain),
    ]) {
      runner.scores = outcome.$1;
      await service.startClip();
      await _sendFrames(service);
      final result = await service.finishClip();
      expect(result.status, outcome.$2);
      expect(result.letter, isNull);
    }
    expect(runner.tensors, hasLength(2));
  });

  test('duplicate/backwards acquisition times never reach MediaPipe', () async {
    await service.startClip();
    await service.addJpegFrame(Uint8List(1), timestampMs: 0);
    for (final timestamp in [0, -1]) {
      expect(
        () => service.addJpegFrame(Uint8List(1), timestampMs: timestamp),
        _backendError('invalid_timestamp'),
      );
    }
    await _sendFrames(service, count: 5, startMs: 67);
    final result = await service.finishClip();
    expect(result.letter, 'J');
    expect(detector.timestamps, [0, 67, 134, 201, 268, 335]);
  });

  test(
    'camera rotation change invalidates an otherwise complete clip',
    () async {
      await service.startClip();
      final image = _cameraFrame();
      for (var index = 0; index < 6; index++) {
        final receipt = await service.addCameraFrame(
          image,
          timestampMs: index * 67,
          rotationDegrees: 0,
        );
        expect(receipt.status, JzFrameStatus.sampled);
      }
      expect(
        () => service.addCameraFrame(
          image,
          timestampMs: 402,
          rotationDegrees: 90,
        ),
        _backendError('geometry_changed'),
      );
      await expectLater(
        service.finishClip(),
        _backendError('geometry_changed'),
      );
      expect(runner.tensors, isEmpty);
      expect(detector.timestamps, [0, 67, 134, 201, 268, 335]);
      expect(detector.finishes, 1);
      expect(service.state, JzCaptureState.idle);
    },
  );

  test(
    'huge timestamps validate bounds and scheduling skips in constant time',
    () async {
      await service.startClip();
      await service.addJpegFrame(Uint8List(1), timestampMs: 0);
      expect(
        () => service.addJpegFrame(Uint8List(1), timestampMs: 9223372036854776),
        _backendError('invalid_timestamp'),
      );
      expect(detector.timestamps, [0]);
      final receipt = await service.addJpegFrame(
        Uint8List(1),
        timestampMs: 9223372036854775,
      );
      expect(receipt.status, JzFrameStatus.sampled);
      expect(detector.timestamps, [0, 9223372036854775]);
      expect(service.sampledFrames, 2);
      await service.cancelClip();
      expect(runner.tensors, isEmpty);
    },
  );

  test(
    'interval throttling does not duplicate detector observations',
    () async {
      await service.startClip();
      await service.addJpegFrame(Uint8List(1), timestampMs: 0);
      for (final timestamp in [10, 66]) {
        final receipt = await service.addJpegFrame(
          Uint8List(1),
          timestampMs: timestamp,
        );
        expect(receipt.status, JzFrameStatus.skippedInterval);
        expect(receipt.handDetected, isNull);
      }
      await _sendFrames(service, count: 5, startMs: 67);
      final result = await service.finishClip();
      expect(result.letter, 'J');
      expect(result.quality['skipped_interval'], 2);
      expect(result.quality['sampled_frames'], 6);
      expect(detector.timestamps, [0, 67, 134, 201, 268, 335]);
    },
  );

  test(
    'backpressure skips busy frames without resubmitting stale landmarks',
    () async {
      final gate = Completer<void>();
      detector.frameGate = gate;
      await service.startClip();
      final first = service.addJpegFrame(Uint8List(1), timestampMs: 0);
      await detector.frameEntered.future;
      for (final timestamp in [67, 134]) {
        final receipt = await service.addJpegFrame(
          Uint8List(1),
          timestampMs: timestamp,
        );
        expect(receipt.status, JzFrameStatus.skippedBusy);
        expect(receipt.handDetected, isNull);
      }
      expect(detector.timestamps, [0]);
      gate.complete();
      await first;
      await _sendFrames(service, startMs: 201);
      final result = await service.finishClip();
      expect(result.letter, 'J');
      expect(result.quality['skipped_busy'], 2);
      expect(result.quality['sampled_frames'], 7);
      expect(result.quality['detected_frames'], 7);
      expect(detector.timestamps, [0, 201, 268, 335, 402, 469, 536]);
    },
  );

  test('finish awaits the final detector result before classifying', () async {
    await service.startClip();
    await _sendFrames(service, count: 5);
    detector.frameGate = Completer<void>();
    detector.frameEntered = Completer<void>();
    final lastFrame = service.addJpegFrame(Uint8List(1), timestampMs: 335);
    await detector.frameEntered.future;
    var completed = false;
    final finishing = service.finishClip().then((result) {
      completed = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(service.state, JzCaptureState.finishing);
    expect(completed, isFalse);
    expect(runner.tensors, isEmpty);
    expect(detector.finishes, 0);
    detector.frameGate!.complete();
    await lastFrame;
    final result = await finishing;
    expect(result.letter, 'J');
    expect(result.quality['sampled_frames'], 6);
    expect(detector.finishes, 1);
  });

  test(
    'separate clips reset timestamps and cannot reuse the previous sequence',
    () async {
      await service.startClip();
      await _sendFrames(service);
      expect((await service.finishClip()).letter, 'J');
      runner.scores = [0.1, 0.8, 0.1];
      await service.startClip();
      expect(service.sampledFrames, 0);
      final empty = await service.finishClip();
      expect(empty.status, JzClipStatus.rejected);
      expect(empty.rejectionCode, 'clip_too_short');
      expect(runner.tensors, hasLength(1));
      await service.startClip();
      await _sendFrames(service);
      expect((await service.finishClip()).letter, 'Z');
      expect(detector.finishes, 3);
      expect(runner.tensors, hasLength(2));
    },
  );

  test(
    'failed detector start permits retry without closing the ready model',
    () async {
      detector.failStarts = 1;
      await expectLater(
        service.startClip(),
        _backendError('detector_start_failed'),
      );
      expect(service.state, JzCaptureState.idle);
      expect(detector.finishes, 0);
      expect(runner.closes, 0);
      await service.startClip();
      await _sendFrames(service);
      expect((await service.finishClip()).letter, 'J');
      expect(detector.starts, 2);
      expect(detector.finishes, 1);
    },
  );

  test('failed model initialization also allows a complete retry', () async {
    var attempts = 0;
    service = JzRecognitionService(
      detector: detector,
      classifier: JzClassifier(
        scoreRunnerFactory: () async {
          if (++attempts == 1) throw StateError('initial load failed');
          return runner;
        },
      ),
    );
    await expectLater(service.startClip(), _backendError('processing_failed'));
    expect(detector.starts, 0);
    await service.startClip();
    await _sendFrames(service);
    expect((await service.finishClip()).letter, 'J');
    expect(attempts, 2);
  });

  test(
    'cancel during pending model initialization cleans up then permits reuse',
    () async {
      final factoryEntered = Completer<void>();
      final factoryGate = Completer<JzScoreRunner>();
      service = JzRecognitionService(
        detector: detector,
        classifier: JzClassifier(
          scoreRunnerFactory: () {
            factoryEntered.complete();
            return factoryGate.future;
          },
        ),
      );
      final starting = service.startClip();
      await factoryEntered.future;
      final cancelling = service.cancelClip();
      expect(() => service.startClip(), _backendError('busy'));
      factoryGate.complete(runner);
      await starting;
      await cancelling;
      expect(service.state, JzCaptureState.idle);
      expect(detector.finishes, 1);
      expect(runner.closes, 0);
      await service.startClip();
      await _sendFrames(service);
      expect((await service.finishClip()).letter, 'J');
    },
  );

  test(
    'cancel waits for an in-flight frame and discards the cancelled clip',
    () async {
      detector.frameGate = Completer<void>();
      await service.startClip();
      final frame = service.addJpegFrame(Uint8List(1), timestampMs: 0);
      await detector.frameEntered.future;
      final cancelling = service.cancelClip();
      expect(
        () => service.addJpegFrame(Uint8List(1), timestampMs: 67),
        _backendError('clip_not_started'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(detector.finishes, 0);
      detector.frameGate!.complete();
      await frame;
      await cancelling;
      expect(service.sampledFrames, 0);
      expect(service.state, JzCaptureState.idle);
      expect(detector.finishes, 1);
      expect(runner.tensors, isEmpty);
      await service.startClip();
      await _sendFrames(service);
      expect((await service.finishClip()).letter, 'J');
    },
  );

  test(
    'dispose during model initialization closes only its own loaded resources',
    () async {
      final factoryEntered = Completer<void>();
      final factoryGate = Completer<JzScoreRunner>();
      service = JzRecognitionService(
        detector: detector,
        classifier: JzClassifier(
          scoreRunnerFactory: () {
            factoryEntered.complete();
            return factoryGate.future;
          },
        ),
      );
      final starting = expectLater(
        service.startClip(),
        _backendError('disposed'),
      );
      await factoryEntered.future;
      final closing = service.dispose();
      factoryGate.complete(runner);
      await starting;
      await closing;
      expect(service.state, JzCaptureState.disposed);
      expect(detector.starts, 0);
      expect(detector.finishes, 0);
      expect(
        detector.disposals,
        0,
        reason: 'Do not reset another channel owner.',
      );
      expect(runner.closes, 1);
      expect(() => service.startClip(), _backendError('disposed'));
      await service.dispose();
      expect(runner.closes, 1);
    },
  );

  test(
    'dispose during tracker initialization releases the tracker exactly once',
    () async {
      detector.startGate = Completer<void>();
      final starting = expectLater(
        service.startClip(),
        _backendError('disposed'),
      );
      await detector.startEntered.future;
      final closing = service.dispose();
      detector.startGate!.complete();
      await starting;
      await closing;
      expect(service.state, JzCaptureState.disposed);
      expect(detector.finishes, 1);
      expect(runner.closes, 1);
    },
  );

  test(
    'dispose waits for pending detection and never classifies cancelled frames',
    () async {
      detector.frameGate = Completer<void>();
      await service.startClip();
      final frame = service.addJpegFrame(Uint8List(1), timestampMs: 0);
      await detector.frameEntered.future;
      final closing = service.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(detector.finishes, 0);
      expect(runner.closes, 0);
      detector.frameGate!.complete();
      await frame;
      await closing;
      expect(service.state, JzCaptureState.disposed);
      expect(service.sampledFrames, 0);
      expect(detector.finishes, 1);
      expect(runner.closes, 1);
      expect(runner.tensors, isEmpty);
    },
  );

  test(
    'stale detector output poisons only its clip and permits the next clip',
    () async {
      detector.frameFor = (timestamp) => _handFrame(timestamp - 1);
      await service.startClip();
      await expectLater(
        service.addJpegFrame(Uint8List(1), timestampMs: 0),
        _backendError('invalid_frame'),
      );
      await expectLater(service.finishClip(), _backendError('invalid_frame'));
      expect(detector.finishes, 1);
      expect(service.sampledFrames, 0);
      expect(runner.tensors, isEmpty);
      detector.frameFor = _handFrame;
      await service.startClip();
      await _sendFrames(service);
      expect((await service.finishClip()).letter, 'J');
    },
  );
}
