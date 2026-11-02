import 'dart:async';

import 'package:camera/camera.dart' show CameraImage;
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:sign_language/models/history_item.dart';
import 'package:sign_language/models/jz_clip_result.dart';
import 'package:sign_language/models/jz_prediction.dart';
import 'package:sign_language/models/sign_prediction.dart';
import 'package:sign_language/screens/camera_screen.dart';
import 'package:sign_language/services/jz_recognition_service.dart';
import 'package:sign_language/services/static_camera_pipeline.dart';

const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);

class _Camera extends CameraPlatform {
  List<CameraDescription> cameras = [_front];
  final initialized = StreamController<CameraInitializedEvent>.broadcast();
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final frames = StreamController<CameraImageData>.broadcast();
  void Function(CameraImageData)? videoFrame;
  var streamStarts = 0;
  var videoStarts = 0;
  var disposals = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;
  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? resolution, {
    bool enableAudio = false,
  }) async => 1;
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    initialized.add(
      CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        false,
        FocusMode.auto,
        false,
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      initialized.stream;
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}
  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.green);
  @override
  bool supportsImageStreaming() => true;
  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    streamStarts++;
    return frames.stream;
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    videoStarts++;
    videoFrame = options.streamCallback;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    videoFrame = null;
    // Exercise the app's existing video-save failure recovery as well.
    throw CameraException(
      'test_no_recording',
      'No physical video in widget test',
    );
  }

  @override
  Future<void> dispose(int cameraId) async => disposals++;

  void emitFrame() {
    final frame = CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      width: 4,
      height: 2,
      planes: [
        CameraImagePlane(bytes: Uint8List(8), bytesPerRow: 4, bytesPerPixel: 1),
        CameraImagePlane(bytes: Uint8List(2), bytesPerRow: 2, bytesPerPixel: 1),
        CameraImagePlane(bytes: Uint8List(2), bytesPerRow: 2, bytesPerPixel: 1),
      ],
    );
    if (videoFrame != null) {
      videoFrame!(frame);
    } else {
      frames.add(frame);
    }
  }

  Future<void> closeStreams() async {
    await initialized.close();
    errors.add(CameraErrorEvent(1, 'test camera disposed'));
    await errors.close();
    await frames.close();
  }
}

class _Motion extends JzRecognitionService {
  var starts = 0;
  var finishes = 0;
  var cancels = 0;
  var closes = 0;
  final timestamps = <int>[];
  final rotations = <int>[];
  Completer<void>? startGate;
  Completer<JzClipResult>? finishGate;
  Object? startError;
  Object? finishError;
  Object? frameError;
  JzClipResult result = JzClipResult(
    status: JzClipStatus.recognized,
    prediction: JzPrediction.fromScores([.95, .03, .02]),
  );

  @override
  Future<void> startClip() async {
    starts++;
    await startGate?.future;
    if (startError case final error?) throw error;
  }

  @override
  Future<JzFrameReceipt> addCameraFrame(
    CameraImage image, {
    required int timestampMs,
    required int rotationDegrees,
  }) async {
    if (frameError case final error?) throw error;
    timestamps.add(timestampMs);
    rotations.add(rotationDegrees);
    return JzFrameReceipt(
      timestampMs: timestampMs,
      status: JzFrameStatus.sampled,
      handDetected: true,
    );
  }

  @override
  Future<JzClipResult> finishClip() async {
    finishes++;
    if (finishError case final error?) throw error;
    return finishGate == null ? result : await finishGate!.future;
  }

  @override
  Future<void> cancelClip() async {
    cancels++;
    await startGate?.future;
  }

  @override
  Future<void> dispose() async => closes++;
}

class _Static extends StaticCameraPipeline {
  final observations = StreamController<List<Hand>>.broadcast();
  var starts = 0;
  var detections = 0;
  var classifications = 0;
  bool visible = true;
  String letter = 'A';
  double confidence = .95;
  Completer<SignPrediction>? predictionGate;
  @override
  Future<void> initialize() async => starts++;
  @override
  Stream<List<Hand>> get hands => observations.stream;
  @override
  void detectHands(CameraImage image, int rotation) {
    detections++;
    observations.add(
      visible
          ? [Hand(List.generate(21, (i) => Landmark(.3 + i * .01, .5, 0.0)))]
          : [],
    );
  }

  @override
  Future<SignPrediction> classify(
    CameraImage image, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    required List<Offset> normalizedLandmarks,
  }) async {
    classifications++;
    expect(mirrorHorizontally, isFalse);
    expect(normalizedLandmarks, hasLength(21));
    return predictionGate == null
        ? SignPrediction(
            label: letter,
            confidence: confidence,
            scores: const [],
          )
        : await predictionGate!.future;
  }

  @override
  void dispose() {}
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  // Stream cancellation may complete in the platform stream's real IO zone.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 5)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CameraPlatform previous;
  late _Camera camera;
  late _Motion motion;
  late _Static staticPipeline;
  late List<HistoryItem> saved;
  bool busy = false;

  Widget screen({bool photoMode = false}) => MaterialApp(
    home: Scaffold(
      body: CameraScreen(
        photoMode: photoMode,
        jzServiceFactory: () => motion,
        staticPipelineFactory: () => staticPipeline,
        onResultSaved: (item) async => saved.add(item),
        onBusyChanged: (value) => busy = value,
      ),
    ),
  );

  Future<void> selectTarget(WidgetTester tester, String target) async {
    addTearDown(() async {
      if (motion.startGate != null && !motion.startGate!.isCompleted) {
        motion.startGate!.complete();
      }
      if (motion.finishGate != null && !motion.finishGate!.isCompleted) {
        motion.finishGate!.complete(motion.result);
      }
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    });
    final previousTarget = tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .value!;
    final direction = target.compareTo(previousTarget) < 0 ? -180.0 : 180.0;
    await tester.tap(find.byType(DropdownButton<String>));
    await _settle(tester);
    final text = target.isEmpty
        ? 'MODE: LATIHAN BEBAS'
        : 'MODE UJI: HURUF $target';
    await tester.scrollUntilVisible(
      find.text(text),
      direction,
      scrollable: find.byType(Scrollable).last,
    );
    final item = find.text(text).last;
    await tester.ensureVisible(item);
    await _settle(tester);
    await tester.tap(item);
    await _settle(tester);
  }

  Future<void> closeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> emitStaticFrame(WidgetTester tester) async {
    // The established static path uses wall-clock intervals of 260/320 ms.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 340)),
    );
    camera.emitFrame();
    await _settle(tester);
  }

  setUp(() {
    previous = CameraPlatform.instance;
    camera = _Camera();
    CameraPlatform.instance = camera;
    motion = _Motion();
    staticPipeline = _Static();
    saved = [];
    busy = false;
  });
  tearDown(() async {
    await camera.closeStreams();
    await staticPipeline.observations.close();
    CameraPlatform.instance = previous;
  });

  testWidgets(
    'J target uses one motion decision and saves once, without static inference',
    (tester) async {
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'J');
      expect(find.text('Mulai gerakan J'), findsOneWidget);
      expect(camera.streamStarts, 0);
      await tester.tap(find.text('Mulai gerakan J'));
      await _settle(tester);
      expect(busy, isTrue);
      camera.emitFrame();
      await tester.pump();
      expect(motion.timestamps, hasLength(1));
      expect(motion.rotations, [270]);
      expect(staticPipeline.starts, 0);
      await tester.tap(find.text('Selesai gerakan'));
      await _settle(tester);
      expect(motion.finishes, 1);
      expect(saved.single.gesture, 'J');
      expect(saved.single.source, 'motion');
      expect(saved.single.sourceLabel, 'Latihan gerakan J/Z');
      expect(
        find.text('Benar: terdeteksi J'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(busy, isFalse);
      await closeScreen(tester);
      expect(motion.closes, 1);
    },
  );

  testWidgets(
    'selected J does not overwrite a recognized Z; repeated clips each save once',
    (tester) async {
      motion.result = JzClipResult(
        status: JzClipStatus.recognized,
        prediction: JzPrediction.fromScores([.01, .98, .01]),
      );
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'J');
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Mulai gerakan J'));
        await _settle(tester);
        await tester.tap(find.text('Selesai gerakan'));
        await _settle(tester);
      }
      expect(saved.map((item) => item.gesture), ['Z', 'Z']);
      expect(find.text('Belum tepat: terdeteksi Z'), findsOneWidget);
      await closeScreen(tester);
    },
  );

  for (final status in [
    JzClipStatus.other,
    JzClipStatus.uncertain,
    JzClipStatus.rejected,
  ]) {
    testWidgets('$status never saves a letter or credits practice', (
      tester,
    ) async {
      motion.result = JzClipResult(
        status: status,
        prediction: status == JzClipStatus.rejected
            ? null
            : JzPrediction.fromScores(
                status == JzClipStatus.other ? [.01, .01, .98] : [.5, .4, .1],
              ),
        message: 'Tangan tidak cukup terlihat.',
      );
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'Z');
      await tester.tap(find.text('Mulai gerakan Z'));
      await _settle(tester);
      await tester.tap(find.text('Selesai gerakan'));
      await _settle(tester);
      expect(saved, isEmpty);
      expect(busy, isFalse);
      expect(find.text('Mulai gerakan Z'), findsOneWidget);
      await closeScreen(tester);
    });
  }

  testWidgets(
    'switching target cancels motion and static targets still start automatically',
    (tester) async {
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'J');
      await tester.tap(find.text('Mulai gerakan J'));
      await _settle(tester);
      await selectTarget(tester, 'C');
      expect(motion.cancels, 1);
      expect(motion.finishes, 0);
      expect(saved, isEmpty);
      expect(find.text('Reset hasil uji C'), findsOneWidget);
      expect(staticPipeline.starts, 1);
      expect(busy, isFalse);
      await closeScreen(tester);
    },
  );

  testWidgets(
    'Foto mode cancels an active gesture and keeps photo-only controls',
    (tester) async {
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'J');
      await tester.tap(find.text('Mulai gerakan J'));
      await _settle(tester);
      await tester.pumpWidget(screen(photoMode: true));
      await _settle(tester);
      expect(motion.cancels, 1);
      expect(saved, isEmpty);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.text('Ambil foto'), findsOneWidget);
      await closeScreen(tester);
    },
  );

  testWidgets(
    'stale finish after leaving the page cannot save or append a gesture',
    (tester) async {
      motion.finishGate = Completer<JzClipResult>();
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'J');
      await tester.tap(find.text('Mulai gerakan J'));
      await _settle(tester);
      await tester.tap(find.text('Selesai gerakan'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      motion.finishGate!.complete(motion.result);
      await _settle(tester);
      expect(saved, isEmpty);
      expect(motion.cancels, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'frame failures cancel capture and allow retry without a false letter',
    (tester) async {
      motion.frameError = const JzBackendException(
        'hand_detection',
        'Detector gagal',
      );
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'Z');
      await tester.tap(find.text('Mulai gerakan Z'));
      await _settle(tester);
      camera.emitFrame();
      await _settle(tester);
      expect(motion.cancels, 1);
      expect(saved, isEmpty);
      expect(busy, isFalse);
      expect(find.text('Mulai gerakan Z'), findsOneWidget);
      await closeScreen(tester);
    },
  );

  testWidgets(
    'Stop awaits the final J/Z decision and saves a free session only once',
    (tester) async {
      motion.finishGate = Completer<JzClipResult>();
      await tester.pumpWidget(screen());
      await _settle(tester);
      await tester.tap(find.text('Mulai latihan bebas'));
      await _settle(tester);
      expect(camera.videoStarts, 1);
      await tester.tap(find.text('Mulai J/Z'));
      await _settle(tester);
      camera.emitFrame();
      await tester.pump();
      expect(staticPipeline.classifications, 0);
      expect(motion.timestamps, hasLength(1));
      await tester.tap(find.text('Akhiri dan lihat hasil'));
      await tester.pump();
      expect(saved, isEmpty);
      expect(motion.finishes, 1);
      motion.finishGate!.complete(motion.result);
      await _settle(tester);
      expect(saved.single.gesture, 'J');
      expect(saved.single.source, 'video');
      expect(find.text('Hasil sesi'), findsOneWidget);
      expect(busy, isFalse);
      await closeScreen(tester);
    },
  );

  testWidgets(
    'mixed A-J-B-Z session retains order and blocks static results during motion and release',
    (tester) async {
      await tester.pumpWidget(screen());
      await _settle(tester);
      await tester.tap(find.text('Mulai latihan bebas'));
      await _settle(tester);
      // First frame finds the hand. Two fresh static decisions commit A.
      for (var i = 0; i < 3; i++) {
        await emitStaticFrame(tester);
      }
      expect(staticPipeline.classifications, 2);
      expect(saved, isEmpty);
      await tester.tap(find.text('Mulai J/Z'));
      await _settle(tester);
      camera.emitFrame();
      await _settle(tester);
      expect(staticPipeline.classifications, 2);
      await tester.tap(find.text('Selesai gerakan'));
      await _settle(tester);
      // Holding the endpoint (the CNN sees I) must not add an I.
      staticPipeline.letter = 'I';
      for (var i = 0; i < 3; i++) {
        await emitStaticFrame(tester);
      }
      expect(staticPipeline.classifications, 2);
      staticPipeline.visible = false;
      await emitStaticFrame(tester);
      staticPipeline.visible = true;
      staticPipeline.letter = 'B';
      for (var i = 0; i < 3; i++) {
        await emitStaticFrame(tester);
      }
      expect(staticPipeline.classifications, 4);
      motion.result = JzClipResult(
        status: JzClipStatus.recognized,
        prediction: JzPrediction.fromScores([.01, .98, .01]),
      );
      await tester.tap(find.text('Mulai J/Z'));
      await _settle(tester);
      camera.emitFrame();
      await _settle(tester);
      await tester.tap(find.text('Akhiri dan lihat hasil'));
      await _settle(tester);
      expect(saved.single.gesture, 'AJBZ');
      expect(saved.single.source, 'video');
      expect(motion.finishes, 2);
      expect(camera.videoStarts, 1);
      expect(
        camera.streamStarts,
        0,
        reason: 'Do not start a second camera stream.',
      );
      expect(find.text('AJBZ'), findsOneWidget);
      await closeScreen(tester);
    },
  );

  testWidgets(
    'a static decision already in flight cannot leak into a J/Z clip',
    (tester) async {
      await tester.pumpWidget(screen());
      await _settle(tester);
      await tester.tap(find.text('Mulai latihan bebas'));
      await _settle(tester);
      staticPipeline.predictionGate = Completer<SignPrediction>();
      await emitStaticFrame(tester);
      await emitStaticFrame(tester);
      expect(staticPipeline.classifications, 1);
      await tester.tap(find.text('Mulai J/Z'));
      await _settle(tester);
      staticPipeline.predictionGate!.complete(
        SignPrediction(label: 'I', confidence: .99, scores: const []),
      );
      await _settle(tester);
      await tester.tap(find.text('Akhiri dan lihat hasil'));
      await _settle(tester);
      expect(saved.single.gesture, 'J');
      await closeScreen(tester);
    },
  );

  testWidgets(
    'background cancels capture and resume requires a fresh gesture',
    (tester) async {
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'J');
      await tester.tap(find.text('Mulai gerakan J'));
      await _settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _settle(tester);
      expect(motion.cancels, 1);
      expect(saved, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(find.text('Mulai gerakan J'), findsOneWidget);
      expect(motion.starts, 1);
      await closeScreen(tester);
    },
  );

  testWidgets(
    'background while model starts invalidates the late start without a stream',
    (tester) async {
      motion.startGate = Completer<void>();
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'Z');
      await tester.tap(find.text('Mulai gerakan Z'));
      await tester.pump();
      expect(busy, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      motion.startGate!.complete();
      await _settle(tester);
      expect(camera.streamStarts, 0);
      expect(motion.cancels, 1);
      expect(saved, isEmpty);
      expect(busy, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      await closeScreen(tester);
    },
  );

  testWidgets('motion timeout cancels without a prediction and permits retry', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await _settle(tester);
    await selectTarget(tester, 'Z');
    await tester.tap(find.text('Mulai gerakan Z'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 11));
    await _settle(tester);
    expect(motion.cancels, 1);
    expect(motion.finishes, 0);
    expect(saved, isEmpty);
    expect(find.text('Mulai gerakan Z'), findsOneWidget);
    expect(find.textContaining('Gerakan terlalu lama'), findsOneWidget);
    await closeScreen(tester);
  });

  testWidgets(
    'background during Stop discards a late motion decision and releases navigation',
    (tester) async {
      motion.finishGate = Completer<JzClipResult>();
      await tester.pumpWidget(screen());
      await _settle(tester);
      await tester.tap(find.text('Mulai latihan bebas'));
      await _settle(tester);
      await tester.tap(find.text('Mulai J/Z'));
      await _settle(tester);
      await tester.tap(find.text('Akhiri dan lihat hasil'));
      await tester.pump();
      expect(motion.finishes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      motion.finishGate!.complete(motion.result);
      await _settle(tester);
      expect(motion.cancels, 1);
      expect(saved, isEmpty);
      expect(busy, isFalse);
      expect(find.text('Hasil sesi'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(find.text('Mulai latihan bebas'), findsOneWidget);
      await closeScreen(tester);
    },
  );

  for (final failureStage in ['start', 'finish']) {
    testWidgets('$failureStage failure releases controls and permits retry', (
      tester,
    ) async {
      if (failureStage == 'start') {
        motion.startError = StateError('model unavailable');
      } else {
        motion.finishError = StateError('inference failed');
      }
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'J');
      await tester.tap(find.text('Mulai gerakan J'));
      await _settle(tester);
      if (failureStage == 'finish') {
        await tester.tap(find.text('Selesai gerakan'));
        await _settle(tester);
      }
      expect(saved, isEmpty);
      expect(busy, isFalse);
      expect(find.text('Mulai gerakan J'), findsOneWidget);
      motion.startError = null;
      motion.finishError = null;
      await tester.tap(find.text('Mulai gerakan J'));
      await _settle(tester);
      await tester.tap(find.text('Selesai gerakan'));
      await _settle(tester);
      expect(saved.single.gesture, 'J');
      expect(motion.starts, 2);
      expect(busy, isFalse);
      await closeScreen(tester);
    });
  }

  testWidgets(
    'switching camera cancels a gesture before opening the next lens',
    (tester) async {
      camera.cameras = [
        _front,
        const CameraDescription(
          name: 'back',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
      ];
      await tester.pumpWidget(screen());
      await _settle(tester);
      await selectTarget(tester, 'Z');
      await tester.tap(find.text('Mulai gerakan Z'));
      await _settle(tester);
      await tester.tap(find.byTooltip('Ganti kamera'));
      await _settle(tester);
      expect(motion.cancels, 1);
      expect(camera.disposals, 1);
      expect(saved, isEmpty);
      expect(busy, isFalse);
      expect(find.text('Mulai gerakan Z'), findsOneWidget);
      await closeScreen(tester);
    },
  );

  testWidgets(
    'camera controls fit narrow phone sizes during motion and a free session',
    (tester) async {
      for (final size in [const Size(360, 640), const Size(411, 800)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(screen());
        await _settle(tester);
        await selectTarget(tester, 'J');
        await tester.tap(find.text('Mulai gerakan J'));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Selesai gerakan'));
        await _settle(tester);
        await selectTarget(tester, '');
        await tester.tap(find.text('Mulai latihan bebas'));
        await _settle(tester);
        expect(find.text('Mulai J/Z'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeScreen(tester);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
