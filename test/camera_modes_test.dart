import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sign_language/models/history_item.dart';
import 'package:sign_language/pages/detection_page.dart';
import 'package:sign_language/screens/camera_screen.dart';
import 'package:sign_language/services/sign_classifier.dart';

const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 270,
);
const _rear = CameraDescription(
  name: 'rear',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

class _CameraBackend extends CameraPlatform {
  final initialized = StreamController<CameraInitializedEvent>.broadcast();
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final orientations =
      StreamController<DeviceOrientationChangedEvent>.broadcast();
  final List<CameraDescription> opened = [];
  final List<int> closed = [];
  final List<int> disposalStarted = [];
  final List<String> lifecycle = [];
  Completer<List<CameraDescription>>? availableGate;
  Completer<void>? initializeGate;
  Completer<void>? disposeGate;
  DeviceOrientation? lockedOrientation;
  String? picturePath;
  int picturesTaken = 0;
  int deniedInitializations = 0;
  int permissionRequestAttempts = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async =>
      availableGate == null ? [_rear, _front] : await availableGate!.future;

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    permissionRequestAttempts++;
    if (deniedInitializations > 0) {
      deniedInitializations--;
      throw PlatformException(
        code: 'CameraAccessDenied',
        message: 'Camera access permission was denied.',
      );
    }
    opened.add(cameraDescription);
    lifecycle.add('create-${opened.length}');
    return opened.length;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    if (initializeGate != null) await initializeGate!.future;
    initialized.add(
      CameraInitializedEvent(
        cameraId,
        720,
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
      initialized.stream.where((event) => event.cameraId == cameraId);

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      orientations.stream;

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {
    lockedOrientation = orientation;
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposalStarted.add(cameraId);
    lifecycle.add('dispose-start-$cameraId');
    if (disposeGate != null) await disposeGate!.future;
    closed.add(cameraId);
    lifecycle.add('dispose-complete-$cameraId');
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.green);

  @override
  Future<XFile> takePicture(int cameraId) async {
    picturesTaken++;
    return XFile(picturePath!);
  }

  Future<void> closeStreams() async {
    await initialized.close();
    // Complete CameraController's one-shot error listener after disposal.
    errors.add(CameraErrorEvent(0, 'disposed test camera'));
    await errors.close();
    await orientations.close();
  }
}

Widget _screen({
  bool photoMode = false,
  bool enabled = false,
  double topOverlayHeight = 0,
  ValueChanged<bool>? onBusyChanged,
  Future<void> Function(HistoryItem)? onResultSaved,
}) => MaterialApp(
  home: Scaffold(
    body: CameraScreen(
      cameraEnabled: enabled,
      photoMode: photoMode,
      topOverlayHeight: topOverlayHeight,
      onBusyChanged: onBusyChanged,
      onResultSaved: onResultSaved,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CameraPlatform previous;
  late _CameraBackend backend;

  setUp(() {
    previous = CameraPlatform.instance;
    backend = _CameraBackend();
    CameraPlatform.instance = backend;
  });
  tearDown(() async {
    await backend.closeStreams();
    CameraPlatform.instance = previous;
  });

  testWidgets('Foto has capture controls, without video or target controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_screen(photoMode: true, topOverlayHeight: 52));
    expect(find.text('Foto Isyarat'), findsNothing);
    expect(
      find.byKey(const ValueKey('camera-detection-frame')),
      findsOneWidget,
    );
    expect(find.text('Ambil foto'), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-model-selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-switch-button')), findsOneWidget);
    final modelCard = tester.getRect(
      find.byKey(const ValueKey('camera-model-selector')),
    );
    final cameraToggle = tester.getRect(
      find.byKey(const ValueKey('camera-switch-button')),
    );
    expect(cameraToggle.center.dy, closeTo(modelCard.center.dy, 1));
    expect(modelCard.left, lessThan(cameraToggle.left));
    final frame = tester.getRect(
      find.byKey(const ValueKey('camera-detection-frame')),
    );
    final action = tester.getRect(
      find.byKey(const ValueKey('photo-primary-action')),
    );
    expect(frame.height, greaterThan(200));
    expect(frame.bottom, lessThan(action.top - 8));
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('Mulai latihan bebas'), findsNothing);
    expect(find.text('Deteksi'), findsNothing);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Foto model and camera controls align with Video controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_screen(topOverlayHeight: 52));
    final videoModel = tester.getRect(
      find.byKey(const ValueKey('camera-model-selector')),
    );
    await tester.pumpWidget(_screen(photoMode: true, topOverlayHeight: 52));
    final photoModel = tester.getRect(
      find.byKey(const ValueKey('camera-model-selector')),
    );
    final photoToggle = tester.getRect(
      find.byKey(const ValueKey('camera-switch-button')),
    );
    final photoFrame = tester.getRect(
      find.byKey(const ValueKey('camera-detection-frame')),
    );

    expect(photoModel.top, closeTo(videoModel.top, 1));
    expect(photoToggle.center.dy, closeTo(photoModel.center.dy, 1));
    expect(photoFrame.top, greaterThan(photoModel.bottom));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('Video keeps a visible detection frame without a text header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_screen(topOverlayHeight: 52));
    expect(find.text('Kamera Latihan'), findsNothing);
    expect(find.text('Tangan boleh di mana saja dalam frame'), findsNothing);
    expect(
      find.byKey(const ValueKey('camera-detection-frame')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('camera-controls')), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-model-selector')), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-live-results')), findsNothing);
    final modelCard = tester.getRect(
      find.byKey(const ValueKey('camera-model-selector')),
    );
    final cameraToggle = tester.getRect(
      find.byKey(const ValueKey('camera-switch-button')),
    );
    final frame = tester.getRect(
      find.byKey(const ValueKey('camera-detection-frame')),
    );
    final action = tester.getRect(
      find.byKey(const ValueKey('camera-primary-action')),
    );
    expect(frame.height, greaterThan(200));
    expect(cameraToggle.center.dy, closeTo(modelCard.center.dy, 1));
    expect(modelCard.left, lessThan(cameraToggle.left));
    expect(frame.top, greaterThan(modelCard.bottom));
    expect(frame.bottom, lessThan(action.top));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('camera UI follows the dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(body: CameraScreen(cameraEnabled: false)),
      ),
    );
    final cameraSurface = tester.widget<ColoredBox>(
      find.byKey(const PageStorageKey('camera')),
    );
    expect(cameraSurface.color, const Color(0xFF090D16));
    expect(find.text('LatihIsyarat Model C'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('camera UI keeps the existing light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const Scaffold(body: CameraScreen(cameraEnabled: false)),
      ),
    );
    final cameraSurface = tester.widget<ColoredBox>(
      find.byKey(const PageStorageKey('camera')),
    );
    expect(cameraSurface.color, const Color(0xFFF4F7FC));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final photoMode in [false, true]) {
    testWidgets(
      '${photoMode ? 'Foto' : 'Video'} can request camera permission after repeated denial',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        backend.deniedInitializations = 2;

        await tester.pumpWidget(_screen(photoMode: photoMode, enabled: true));
        await tester.pumpAndSettle();
        expect(backend.permissionRequestAttempts, 1);
        expect(find.text('Minta Izin Kamera Lagi'), findsOneWidget);

        final primaryAction = find.byKey(
          ValueKey(
            photoMode ? 'photo-primary-action' : 'camera-primary-action',
          ),
        );
        await tester.tap(
          find.descendant(
            of: primaryAction,
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(backend.permissionRequestAttempts, 2);
        expect(find.text('Minta Izin Kamera Lagi'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: primaryAction,
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(backend.permissionRequestAttempts, 3);
        expect(find.text('Kamera belum siap.'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }

  testWidgets('model picker is interactive in video and photo modes', (
    tester,
  ) async {
    Future<void> openAndConfirmModel() async {
      await tester.tap(find.byKey(const ValueKey('camera-model-selector')));
      await tester.pumpAndSettle();
      expect(find.text('Pilih Model AI'), findsOneWidget);
      expect(find.text('Model C'), findsWidgets);
      expect(find.text('Model E'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('camera-model-option-model_e')),
      );
      await tester.tap(find.byKey(const ValueKey('camera-model-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Pilih Model AI'), findsNothing);
      expect(find.text('LatihIsyarat Model E'), findsOneWidget);
    }

    await tester.pumpWidget(_screen());
    await openAndConfirmModel();

    await tester.pumpWidget(_screen(photoMode: true));
    await tester.pumpAndSettle();
    await openAndConfirmModel();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('selected model is shared by camera and upload modes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DetectionPage(cameraEnabled: false)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    final modelDropdown = find.byKey(const ValueKey('upload-model-dropdown'));
    expect(
      tester.widget<DropdownButton<SignModel>>(modelDropdown).value,
      SignModel.modelC,
    );
    await tester.tap(modelDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model E').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DropdownButton<SignModel>>(modelDropdown).value,
      SignModel.modelE,
    );

    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(find.text('LatihIsyarat Model E'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('target mode has automatic detection, without a Start button', (
    tester,
  ) async {
    await tester.pumpWidget(_screen());
    await tester.tap(find.text('MODE: LATIHAN BEBAS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MODE UJI: HURUF C').last);
    await tester.pumpAndSettle();
    expect(find.text('Selesai Latihan Huruf'), findsOneWidget);
    expect(find.byKey(const ValueKey('camera-controls')), findsNothing);
    expect(find.byKey(const ValueKey('camera-model-selector')), findsNothing);
    expect(find.byKey(const ValueKey('camera-live-results')), findsOneWidget);
    expect(find.text('Mulai latihan bebas'), findsNothing);
    expect(find.textContaining('video tidak direkam'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'camera discovery completing after disposal never opens a camera',
    (tester) async {
      backend.availableGate = Completer<List<CameraDescription>>();
      await tester.pumpWidget(_screen(photoMode: true, enabled: true));
      await tester.pumpWidget(const SizedBox());
      backend.availableGate!.complete([_rear, _front]);
      await tester.pump();
      await tester.pump();
      expect(backend.opened, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initialization completing after disposal releases the camera', (
    tester,
  ) async {
    backend.initializeGate = Completer<void>();
    await tester.pumpWidget(_screen(photoMode: true, enabled: true));
    await tester.pump();
    expect(backend.opened, [_front]);
    await tester.pumpWidget(const SizedBox());
    backend.initializeGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(backend.closed, [1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Foto opens the front camera and locks the same portrait preview',
    (tester) async {
      await tester.pumpWidget(_screen(photoMode: true, enabled: true));
      await tester.pumpAndSettle();
      expect(backend.opened, [_front]);
      expect(backend.lockedOrientation, DeviceOrientation.portraitUp);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(backend.closed, [1]);
    },
  );

  testWidgets(
    'photo detection uses MediaPipe, rejects no hand, and allows retry/retake',
    (tester) async {
      final directory = (await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'asl_photo_test_',
        );
        await File('${directory.path}/temporary.jpg')
            .writeAsBytes(img.encodeJpg(img.Image(width: 4, height: 6)));
        return directory;
      }))!;
      final original = File('${directory.path}/temporary.jpg');
      backend.picturePath = original.path;
      var isBusy = false;
      var handDetectionCalls = 0;
      final savedResults = <HistoryItem>[];
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      const handChannel = MethodChannel('latih_isyarat/image_hand_landmarker');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
      messenger.setMockMethodCallHandler(handChannel, (call) async {
        expect(call.method, 'detect');
        handDetectionCalls++;
        return [];
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(handChannel, null);
        // Windows can retain the file briefly while Flutter's image codec
        // finishes an asynchronous read after Retake unmounts Image.file.
        for (var attempt = 0; attempt < 10; attempt++) {
          try {
            if (await directory.exists()) {
              await directory.delete(recursive: true);
            }
            break;
          } on PathAccessException {
            // The Windows Flutter test engine can retain a mapped JPEG until
            // its isolate exits. The disposable fixture stays in OS temp;
            // this platform cleanup condition is not an app test failure.
            if (attempt == 9 && Platform.isWindows) break;
            if (attempt == 9) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      });

      await tester.pumpWidget(
        _screen(
          photoMode: true,
          enabled: true,
          onBusyChanged: (busy) => isBusy = busy,
          onResultSaved: (item) async => savedResults.add(item),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ambil foto'));
      for (var attempt = 0; isBusy && attempt < 30; attempt++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(isBusy, isFalse);
      expect(find.text('Deteksi'), findsOneWidget);
      expect(find.text('Ambil ulang'), findsOneWidget);
      expect(backend.picturesTaken, 1);
      final files = Directory('${directory.path}/photos').listSync();
      expect(files, hasLength(1));
      expect(files.single.path, isNot(original.path));
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('Deteksi'));
        for (var poll = 0; isBusy && poll < 100; poll++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pump();
        expect(isBusy, isFalse);
        expect(handDetectionCalls, attempt + 1);
        expect(find.textContaining('Tangan tidak terdeteksi'), findsOneWidget);
        expect(savedResults, isEmpty);
        expect(find.text('Deteksi'), findsOneWidget);
        // Dismiss the previous error before checking a second attempt.
        ScaffoldMessenger.of(tester.element(find.byType(CameraScreen)))
            .removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
      // Let the image codec finish reading in the real IO zone before the
      // preview is removed, then release cached decoded images explicitly.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ambil ulang'));
      await tester.pumpAndSettle();
      expect(find.text('Ambil foto'), findsOneWidget);
      expect(find.text('Deteksi'), findsNothing);
      expect(backend.opened, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    },
  );

  testWidgets('camera controls clear the status bar and detection tabs', (
    tester,
  ) async {
    for (final photoMode in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
            child: Scaffold(
              body: CameraScreen(
                cameraEnabled: false,
                photoMode: photoMode,
                topOverlayHeight: detectionOverlayHeight,
              ),
            ),
          ),
        ),
      );
      final toggle = find.byKey(const ValueKey('camera-switch-button'));
      expect(
        tester.getTopLeft(toggle).dy,
        greaterThanOrEqualTo(24 + detectionOverlayGap + detectionOverlayHeight),
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
    'rapid Video/Foto switches wait for the previous native disposal',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DetectionPage())),
      );
      await tester.pumpAndSettle();
      final initialState = tester.state(find.byType(CameraScreen));
      expect(backend.opened, [_front]);

      backend.disposeGate = Completer<void>();
      await tester.tap(find.text('Foto'));
      await tester.pump();
      expect(backend.disposalStarted, [1]);
      expect(backend.closed, isEmpty);
      expect(backend.opened, hasLength(1));

      await tester.tap(find.text('Video'));
      await tester.pump();
      await tester.tap(find.text('Foto'));
      await tester.pump();
      expect(tester.state(find.byType(CameraScreen)), same(initialState));
      expect(backend.opened, hasLength(1));

      backend.disposeGate!.complete();
      await tester.pumpAndSettle();
      expect(backend.opened, [_front, _front]);
      expect(backend.closed, [1]);
      expect(backend.lifecycle.take(4), [
        'create-1',
        'dispose-start-1',
        'dispose-complete-1',
        'create-2',
      ]);
      expect(find.text('Foto Isyarat'), findsNothing);
      expect(find.text('Ambil foto'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(backend.closed, [1, 2]);
    },
  );

  testWidgets(
    'Upload then Video waits for disposal across camera screen states',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DetectionPage())),
      );
      await tester.pumpAndSettle();
      final initialState = tester.state(find.byType(CameraScreen));
      expect(backend.opened, [_front]);

      backend.disposeGate = Completer<void>();
      await tester.tap(find.text('Upload'));
      await tester.pump();
      expect(find.byType(CameraScreen), findsNothing);
      expect(backend.disposalStarted, [1]);
      expect(backend.closed, isEmpty);

      await tester.tap(find.text('Video'));
      await tester.pump();
      expect(
        tester.state(find.byType(CameraScreen)),
        isNot(same(initialState)),
      );
      expect(backend.opened, hasLength(1));
      expect(backend.closed, isEmpty);

      backend.disposeGate!.complete();
      await tester.pumpAndSettle();
      expect(backend.opened, [_front, _front]);
      expect(backend.closed, [1]);
      expect(backend.lifecycle.take(4), [
        'create-1',
        'dispose-start-1',
        'dispose-complete-1',
        'create-2',
      ]);
      expect(find.text('Kamera Latihan'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(backend.closed, [1, 2]);
    },
  );
}
