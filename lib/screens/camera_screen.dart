import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/camera_overlay_widgets.dart';
import '../models/history_item.dart';
import '../models/sign_prediction.dart';
import '../services/camera_preview_size.dart';
import '../services/sign_classifier.dart';
import '../services/stable_sign.dart';
import '../widgets/full_bleed_camera_preview.dart';
import '../services/llm_autocorrect_service.dart';

const _modelSelectionBlue = Color(0xFF2864F0);

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.cameraEnabled = true,
    this.photoMode = false,
    this.onResultSaved,
    this.onBusyChanged,
    this.topOverlayHeight = 0,
    this.selectedModel = SignModel.svmHog,
    this.onModelChanged,
  });

  final bool cameraEnabled;
  final bool photoMode;
  final Future<void> Function(HistoryItem)? onResultSaved;
  final ValueChanged<bool>? onBusyChanged;
  final double topOverlayHeight;
  final SignModel selectedModel;
  final ValueChanged<SignModel>? onModelChanged;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static final _supportedLabels = 'ABCDEFGHIKLMNOPQRSTUVWXY'.split('');

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _isInitializing = true;
  bool _isSessionActive = false;
  bool _isTargetAnalysisActive = false;
  bool _isTargetAnalysisStarting = false;
  bool _handDetected = false;
  String? _cameraError;
  final List<String> _sessionLetters = [];
  final _stableSign = StableSign();
  final _frameClock = Stopwatch()..start();
  int _lastFrameAt = -250;
  bool _processingFrame = false;
  int _recognitionGeneration = 0;
  final List<String> _validationPredictions = [];
  String _selectedTarget = '';
  String? _latestTargetPrediction;
  String? _savedVideoPath;
  bool _isStartingSession = false;
  bool _isEndingSession = false;
  late SignModel _selectedModel = widget.selectedModel;
  bool _isTakingPhoto = false;
  bool _isClassifyingPhoto = false;
  bool _isSavingPhotoHistory = false;
  String? _photoPath;
  SignPrediction? _photoPrediction;
  bool _photoHistorySaved = false;
  bool _appIsActive = true;
  int _cameraGeneration = 0;
  int _photoGeneration = 0;
  // Native camera resources belong to the app, even when navigation destroys
  // this State. A new screen must wait for the old controller's disposal.
  static Future<void>? _cameraLifecycleQueue;
  HandLandmarkerPlugin? _handLandmarker;
  StreamSubscription<List<Hand>>? _landmarkSubscription;
  List<Hand> _latestHands = const [];
  int _lastHandDetectedAtMs = 0;
  int _lastMpFeedAtMs = 0;

  bool get _isAnalysisActive => _isSessionActive || _isTargetAnalysisActive;

  Future<void> _showModelPicker() async {
    if (_isTakingPhoto || _isClassifyingPhoto || _isSavingPhotoHistory) return;
    var selectedModel = _selectedModel;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final colors = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pilih Model AI',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pilih model yang digunakan untuk deteksi isyarat.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                for (final model in SignModel.values) ...[
                  ModelOption(
                    key: ValueKey('camera-model-option-${model.id}'),
                    model: model,
                    selected: selectedModel == model,
                    onTap: () => setSheetState(() => selectedModel = model),
                  ),
                  if (model != SignModel.values.last)
                    const SizedBox(height: 10),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('camera-model-confirm'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _modelSelectionBlue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_selectedModel != selectedModel) {
                          _selectedModel = selectedModel;
                          _photoPrediction = null;
                          _photoHistorySaved = false;
                          _resetRecognitionState(clearTargetResults: true);
                        }
                      });
                      widget.onModelChanged?.call(selectedModel);
                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Gunakan Model Terpilih'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.cameraEnabled && !widget.photoMode) {
      _initHandLandmarker();
    }
    if (widget.cameraEnabled) {
      unawaited(_initializeCameras());
    } else {
      _isInitializing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.cameraEnabled) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _appIsActive = false;
      if (_isSessionActive) unawaited(_endSession(showResult: false));
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed) {
      _appIsActive = true;
      unawaited(_initializeCameras());
    }
  }

  @override
  void didUpdateWidget(covariant CameraScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedModel != widget.selectedModel) {
      _selectedModel = widget.selectedModel;
    }
    if (oldWidget.cameraEnabled == widget.cameraEnabled &&
        oldWidget.photoMode == widget.photoMode) {
      return;
    }
    _photoGeneration++;
    _photoPath = null;
    _photoPrediction = null;
    _photoHistorySaved = false;
    _savedVideoPath = null;
    _selectedTarget = '';
    _resetRecognitionState(clearFreeResults: true, clearTargetResults: true);
    unawaited(_disposeCamera());
    if (widget.cameraEnabled && _appIsActive) {
      unawaited(_initializeCameras());
    } else {
      _isInitializing = false;
    }
  }

  Future<void> _initializeCameras() async {
    if (!mounted || !widget.cameraEnabled || !_appIsActive) return;
    final generation = ++_cameraGeneration;
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _cameraError = null;
      });
    }
    try {
      _cameras = await availableCameras();
      if (!_isCurrentCameraRequest(generation)) return;
      if (_cameras.isEmpty) {
        throw StateError('Kamera tidak ditemukan pada perangkat ini.');
      }
      final frontIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (frontIndex >= 0 && _controller == null) _cameraIndex = frontIndex;
      await _openCamera(_cameras[_cameraIndex], generation);
    } on CameraException catch (error) {
      if (_isCurrentCameraRequest(generation)) {
        _setCameraError(_friendlyCameraError(error));
      }
    } catch (error) {
      if (_isCurrentCameraRequest(generation)) {
        _setCameraError('$error');
      }
    } finally {
      if (_isCurrentCameraRequest(generation)) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  bool _isCurrentCameraRequest(int generation) =>
      mounted &&
      widget.cameraEnabled &&
      _appIsActive &&
      generation == _cameraGeneration;

  Future<T> _queueCameraLifecycle<T>(Future<T> Function() operation) {
    final previous = _cameraLifecycleQueue;
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    // A failed initialization must not block the next retry or disposal.
    final completion = result.then<void>((_) {}).catchError((Object _) {});
    _cameraLifecycleQueue = completion;
    unawaited(
      completion.then((_) {
        if (identical(_cameraLifecycleQueue, completion)) {
          _cameraLifecycleQueue = null;
        }
      }),
    );
    return result;
  }

  Future<void> _openCamera(CameraDescription description, int generation) {
    return _queueCameraLifecycle(() async {
      if (!_isCurrentCameraRequest(generation)) return;
      await _releaseCamera();
      if (!_isCurrentCameraRequest(generation)) return;
      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      try {
        await controller.initialize();
        if (!_isCurrentCameraRequest(generation)) {
          await controller.dispose();
          return;
        }
        // Lock the camera as well as the app UI. Otherwise preview and recording
        // may select different orientations even while the screen stays portrait.
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {
        await controller.dispose();
        rethrow;
      }
      if (!_isCurrentCameraRequest(generation)) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      unawaited(SignClassifier.instance.initialize(model: _selectedModel));
      await _refreshPreviewSize(controller);
      if (!widget.photoMode && _selectedTarget.isNotEmpty) {
        await _startTargetAnalysis(resetResults: false);
      }
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 ||
        _isSessionActive ||
        _isTargetAnalysisStarting ||
        _isInitializing ||
        _isStartingSession ||
        _isEndingSession ||
        _isTakingPhoto ||
        _isClassifyingPhoto) {
      return;
    }
    setState(() => _isInitializing = true);
    final generation = ++_cameraGeneration;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    try {
      await _openCamera(_cameras[_cameraIndex], generation);
    } catch (error) {
      if (_isCurrentCameraRequest(generation)) {
        _setCameraError(
          error is CameraException ? _friendlyCameraError(error) : '$error',
        );
      }
    } finally {
      if (_isCurrentCameraRequest(generation)) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _initHandLandmarker() {
    try {
      _handLandmarker = HandLandmarkerPlugin.create(
        numHands: 1,
        minHandDetectionConfidence: 0.35,
        delegate: HandLandmarkerDelegate.cpu,
      );
    } catch (_) {
      try {
        _handLandmarker = HandLandmarkerPlugin.create(
          numHands: 1,
          minHandDetectionConfidence: 0.5,
          delegate: HandLandmarkerDelegate.cpu,
        );
      } catch (e) {
        debugPrint('MediaPipe HandLandmarker gagal dimuat: $e');
      }
    }
    final plugin = _handLandmarker;
    if (plugin != null) {
      _landmarkSubscription = plugin.landmarkStream.listen((hands) {
        _latestHands = hands;
        if (hands.isNotEmpty) {
          _lastHandDetectedAtMs = _frameClock.elapsedMilliseconds;
        }
      });
    }
  }

  Future<void> _startSession() async {
    final controller = _controller;
    if (widget.photoMode ||
        _isStartingSession ||
        _isEndingSession ||
        _selectedTarget.isNotEmpty ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    final cameraGeneration = _cameraGeneration;
    setState(() => _isStartingSession = true);
    widget.onBusyChanged?.call(true);
    try {
      await SignClassifier.instance.initialize(model: _selectedModel);
      if (!_isCurrentCameraRequest(cameraGeneration) ||
          !identical(controller, _controller)) {
        return;
      }
      setState(() {
        _resetRecognitionState(clearFreeResults: true);
        _savedVideoPath = null;
        _isTargetAnalysisActive = false;
        _isSessionActive = true;
      });
      await _queueCameraLifecycle(() async {
        if (!_isCurrentCameraRequest(cameraGeneration) ||
            !identical(controller, _controller)) {
          throw StateError('Kamera tidak lagi aktif.');
        }
        // CameraX rebinds its use cases when recording starts; reapply the
        // portrait target rotation immediately before that transition.
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
        if (!controller.value.isStreamingImages) {
          await controller.startImageStream(_onCameraFrame);
        }
        await _refreshPreviewSize(controller);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _isSessionActive = false);
        _handleCameraOperationError(error, 'Tidak dapat memulai kamera');
      }
    } finally {
      _isStartingSession = false;
      if (mounted) setState(() {});
      if (mounted && !_isSessionActive) widget.onBusyChanged?.call(false);
    }
  }

  Future<void> _handleTargetChanged(String target) async {
    if (widget.photoMode ||
        _isSessionActive ||
        _isStartingSession ||
        _isEndingSession ||
        target == _selectedTarget) {
      return;
    }

    if (target.isEmpty) {
      setState(() {
        _selectedTarget = '';
        _isTargetAnalysisActive = false;
        _isTargetAnalysisStarting = true;
        _resetRecognitionState(clearTargetResults: true);
      });
      try {
        await _stopTargetImageStream();
      } finally {
        if (mounted) setState(() => _isTargetAnalysisStarting = false);
      }
      return;
    }

    final streamAlreadyActive =
        _isTargetAnalysisActive &&
        (_controller?.value.isStreamingImages ?? false);
    setState(() {
      _selectedTarget = target;
      _resetRecognitionState(clearTargetResults: true);
    });
    if (_controller == null && _cameraError != null) {
      await _initializeCameras();
      return;
    }
    if (!streamAlreadyActive) {
      await _startTargetAnalysis(resetResults: false);
    }
  }

  Future<void> _startTargetAnalysis({bool resetResults = true}) async {
    final controller = _controller;
    if (widget.photoMode ||
        _selectedTarget.isEmpty ||
        _isSessionActive ||
        _isTargetAnalysisStarting ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isStreamingImages) {
      if (mounted) setState(() => _isTargetAnalysisActive = true);
      return;
    }

    if (mounted) {
      setState(() => _isTargetAnalysisStarting = true);
    } else {
      _isTargetAnalysisStarting = true;
    }
    try {
      await SignClassifier.instance.initialize(model: _selectedModel);
      if (!mounted ||
          !_appIsActive ||
          !identical(controller, _controller) ||
          _selectedTarget.isEmpty) {
        return;
      }
      if (resetResults && mounted) {
        setState(() => _resetRecognitionState(clearTargetResults: true));
      }
      await controller.startImageStream(_onCameraFrame);
      await _refreshPreviewSize(controller);
      if (!mounted || controller != _controller) return;
      if (_selectedTarget.isEmpty) {
        await controller.stopImageStream();
        return;
      }
      setState(() => _isTargetAnalysisActive = true);
    } catch (error) {
      if (mounted) {
        setState(() => _isTargetAnalysisActive = false);
        _handleCameraOperationError(
          error,
          'Deteksi otomatis tidak dapat dimulai',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTargetAnalysisStarting = false);
      } else {
        _isTargetAnalysisStarting = false;
      }
    }
  }

  Future<void> _stopTargetImageStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isStreamingImages) return;
    try {
      await controller.stopImageStream();
      await _refreshPreviewSize(controller);
    } catch (error) {
      if (mounted) _showMessage('Deteksi otomatis gagal dihentikan: $error');
    }
  }

  void _resetRecognitionState({
    bool clearFreeResults = false,
    bool clearTargetResults = false,
  }) {
    if (clearFreeResults) {
      _sessionLetters.clear();
    }
    if (clearTargetResults) _validationPredictions.clear();
    _handDetected = false;
    _latestTargetPrediction = null;
    _recognitionGeneration++;
    _stableSign.reset();
    _lastFrameAt = -250;
  }

  void _onCameraFrame(CameraImage cameraImage) {
    final controller = _controller;
    final now = _frameClock.elapsedMilliseconds;
    if (!mounted ||
        !_appIsActive ||
        !_isAnalysisActive ||
        controller == null ||
        (cameraImage.format.group != ImageFormatGroup.yuv420 &&
            cameraImage.format.group != ImageFormatGroup.nv21) ||
        cameraImage.planes.isEmpty) {
      return;
    }
    if (now - _lastMpFeedAtMs >= 80) {
      _lastMpFeedAtMs = now;
      try {
        _handLandmarker?.processFrame(
          cameraImage,
          controller.description.sensorOrientation,
        );
      } catch (_) {}
    }
    if (_processingFrame || now - _lastFrameAt < 250) {
      return;
    }
    _lastFrameAt = now;
    _processingFrame = true;
    unawaited(_recognizeFrame(cameraImage, controller));
  }

  Future<void> _recognizeFrame(
    CameraImage image,
    CameraController controller,
  ) async {
    final generation = _recognitionGeneration;
    bool isCurrent() =>
        mounted &&
        _appIsActive &&
        _isAnalysisActive &&
        identical(controller, _controller) &&
        generation == _recognitionGeneration;
    try {
      final luma = image.planes.first;
      final hasFreshMpHand =
          _latestHands.isNotEmpty &&
          (_frameClock.elapsedMilliseconds - _lastHandDetectedAtMs) <= 600;
      SignPrediction? prediction;
      if (hasFreshMpHand) {
        final sensorRot = controller.description.sensorOrientation;
        final landmarks = _latestHands.first.landmarks
            .map((lm) {
              return switch (sensorRot) {
                90 => (x: 1.0 - lm.y, y: lm.x),
                180 => (x: 1.0 - lm.x, y: 1.0 - lm.y),
                270 => (x: lm.y, y: 1.0 - lm.x),
                _ => (x: lm.x, y: lm.y),
              };
            })
            .toList(growable: false);
        prediction = await SignClassifier.instance.classifyLumaWithLandmarks(
          bytes: luma.bytes,
          width: image.width,
          height: image.height,
          stride: luma.bytesPerRow,
          pixelStride: luma.bytesPerPixel ?? 1,
          rotation: controller.description.sensorOrientation,
          landmarks: landmarks,
        );
        debugPrint(
          'MP_ORIENT lens=${controller.description.lensDirection.name} '
          'sensor=${controller.description.sensorOrientation} '
          'w=(${landmarks[0].x.toStringAsFixed(2)},${landmarks[0].y.toStringAsFixed(2)}) '
          'm9=(${landmarks[9].x.toStringAsFixed(2)},${landmarks[9].y.toStringAsFixed(2)}) '
          'pred=${prediction?.label} acc=${prediction?.agreement}',
        );
      } else {
        prediction = await SignClassifier.instance.classifyLuma(
          bytes: luma.bytes,
          width: image.width,
          height: image.height,
          stride: luma.bytesPerRow,
          pixelStride: luma.bytesPerPixel ?? 1,
          rotation: controller.description.sensorOrientation,
        );
      }
      if (!isCurrent()) return;
      final label = _stableSign.add(
        prediction?.accepted == true ? prediction!.label : null,
        hasForeground: prediction != null,
      );
      setState(() {
        _handDetected = prediction != null;
        if (_isTargetAnalysisActive) {
          _latestTargetPrediction = _stableSign.current;
          if (label != null) _validationPredictions.add(label);
        } else if (label != null) {
          _sessionLetters.add(label);
        }
      });
    } catch (error) {
      if (!isCurrent()) return;
      debugPrint('SVM-HOG frame gagal diproses: $error');
      setState(() {
        _handDetected = false;
        _latestTargetPrediction = null;
        _stableSign.add(null, hasForeground: true);
      });
    } finally {
      _processingFrame = false;
    }
  }

  Future<void> _endSession({bool showResult = true}) async {
    if (_isEndingSession || !_isSessionActive) return;
    final controller = _controller;
    final sequence = _sessionLetters.join();
    // Freeze accepted letters immediately. In-flight inference cannot append
    // a letter after Stop or create a second history record.
    setState(() {
      _isEndingSession = true;
      _isSessionActive = false;
      _recognitionGeneration++;
    });
    String? videoPath;
    try {
      await _queueCameraLifecycle(() async {
        if (controller == null || !identical(controller, _controller)) return;
        if (controller.value.isRecordingVideo) {
          final recording = await controller.stopVideoRecording();
          // Stopping recording rebinds the preview use case. Restore its
          // portrait target rotation before refreshing the preview transform.
          await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
          await _refreshPreviewSize(controller);
          videoPath = await _saveRecording(recording);
        } else if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
          await _refreshPreviewSize(controller);
        }
      });
    } catch (error) {
      if (mounted) _showMessage('Rekaman video gagal disimpan: $error');
    }
    if (mounted) {
      setState(() {
        _handDetected = false;
        _savedVideoPath = videoPath;
      });
    }
    try {
      if (sequence.isNotEmpty) {
        await widget.onResultSaved?.call(
          HistoryItem.fromDetection(
            gesture: sequence,
            confidence: null,
            source: 'video',
            modelId: _selectedModel.id,
            videoPath: videoPath,
          ),
        );
      }
    } catch (error) {
      _showMessage('Hasil tampil, tetapi gagal disimpan ke riwayat: $error');
    } finally {
      _isEndingSession = false;
      if (mounted) setState(() {});
      if (mounted) widget.onBusyChanged?.call(false);
    }
    if (mounted && _appIsActive && showResult) await _showSessionResult();
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (!widget.photoMode ||
        _isTakingPhoto ||
        _isClassifyingPhoto ||
        _photoPath != null ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    final generation = ++_photoGeneration;
    setState(() => _isTakingPhoto = true);
    widget.onBusyChanged?.call(true);
    try {
      // CameraPreview mirrors the front lens. takePicture retains the
      // canonical sensor image; do not flip it before model inference.
      final picture = await _queueCameraLifecycle(() async {
        if (!mounted || !_appIsActive || !identical(controller, _controller)) {
          throw StateError('Kamera tidak lagi aktif.');
        }
        return controller.takePicture();
      });
      final documents = await getApplicationDocumentsDirectory();
      final photos = Directory(
        '${documents.path}${Platform.pathSeparator}photos',
      );
      await photos.create(recursive: true);
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final path =
          '${photos.path}${Platform.pathSeparator}asl_photo_$timestamp.jpg';
      await File(picture.path).copy(path);
      if (!mounted || generation != _photoGeneration) return;
      setState(() {
        _photoPath = path;
        _photoPrediction = null;
        _photoHistorySaved = false;
      });
    } catch (error) {
      _handleCameraOperationError(error, 'Foto gagal diambil');
    } finally {
      _isTakingPhoto = false;
      if (mounted) setState(() {});
      if (mounted) widget.onBusyChanged?.call(false);
    }
  }

  Future<void> _detectPhoto() async {
    final path = _photoPath;
    if (path == null ||
        _isClassifyingPhoto ||
        _isSavingPhotoHistory ||
        _photoHistorySaved) {
      return;
    }
    final generation = _photoGeneration;
    setState(() => _isClassifyingPhoto = true);
    widget.onBusyChanged?.call(true);
    try {
      // classifyFile applies EXIF orientation and model-specific resizing.
      final prediction =
          _photoPrediction ??
          await SignClassifier.instance.classifyFile(
            path,
            model: _selectedModel,
          );
      if (!mounted || generation != _photoGeneration) return;
      setState(() => _photoPrediction = prediction);
      if (prediction.accepted) {
        _isSavingPhotoHistory = true;
        await widget.onResultSaved?.call(
          HistoryItem.fromDetection(
            gesture: prediction.label,
            confidence: prediction.confidence,
            source: 'photo',
            modelId: _selectedModel.id,
            imagePath: path,
          ),
        );
        if (mounted && generation == _photoGeneration) {
          setState(() => _photoHistorySaved = true);
        }
      }
    } catch (error) {
      _handleCameraOperationError(error, 'Foto gagal diproses atau disimpan');
    } finally {
      _isClassifyingPhoto = false;
      _isSavingPhotoHistory = false;
      if (mounted) setState(() {});
      if (mounted) widget.onBusyChanged?.call(false);
    }
  }

  void _retakePhoto() {
    if (_isTakingPhoto || _isClassifyingPhoto || _isSavingPhotoHistory) return;
    setState(() {
      _photoGeneration++;
      _photoPath = null;
      _photoPrediction = null;
      _photoHistorySaved = false;
    });
  }

  Future<String> _saveRecording(XFile recording) async {
    final documents = await getApplicationDocumentsDirectory();
    final recordingsDirectory = Directory(
      '${documents.path}${Platform.pathSeparator}recordings',
    );
    await recordingsDirectory.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final destination =
        '${recordingsDirectory.path}${Platform.pathSeparator}asl_session_$timestamp.mp4';
    await File(recording.path).copy(destination);
    return destination;
  }

  Future<void> _showSessionResult() {
    final target = _selectedTarget;
    final displayedPredictions = target.isEmpty
        ? _sessionLetters
        : _validationPredictions;
    final sequence = displayedPredictions.join();
    final validationTotal = _validationPredictions.length;
    final validationCorrect = target.isEmpty
        ? 0
        : _validationPredictions.where((label) => label == target).length;
    final validationAccuracy = validationTotal == 0
        ? 0.0
        : validationCorrect / validationTotal * 100;

    // Panggil LLM hanya di mode bebas (target kosong) dan minimal 2 huruf
    final Future<AutocorrectResult>? autocorrectFuture =
        (target.isEmpty && sequence.length >= 2)
        ? LlmAutocorrectService.instance.correctWord(sequence)
        : null;

    var activeSequence = sequence;

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF4F7FC),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140E2343),
                          blurRadius: 22,
                          offset: Offset(0, 9),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE3F8EF),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.task_alt_rounded,
                            size: 32,
                            color: Color(0xFF10AD7E),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          target.isEmpty
                              ? 'Hasil sesi'
                              : 'Hasil uji target $target',
                          style: const TextStyle(
                            color: Color(0xFF172642),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF0FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            activeSequence.isEmpty
                                ? 'Belum ada huruf yang stabil.'
                                : activeSequence,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: activeSequence.isEmpty
                                  ? const Color(0xFF7585A2)
                                  : const Color(0xFF2864F0),
                              fontSize: activeSequence.isEmpty ? 15 : 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: activeSequence.isEmpty ? 0 : 6,
                            ),
                          ),
                        ),
                        if (autocorrectFuture != null)
                          FutureBuilder<AutocorrectResult>(
                            future: autocorrectFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF2864F0),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Memeriksa saran kata...',
                                        style: TextStyle(
                                          color: Color(0xFF7585A2),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final result = snapshot.data;
                              if (result == null || !result.hasSuggestions) {
                                return const SizedBox.shrink();
                              }

                              return Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Column(
                                  children: [
                                    const Text(
                                      'Mungkin maksudmu (tap untuk ubah):',
                                      style: TextStyle(
                                        color: Color(0xFF7585A2),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        for (final word in result.suggestions)
                                          ChoiceChip(
                                            label: Text(word),
                                            selected: activeSequence == word,
                                            selectedColor: const Color(
                                              0xFF2864F0,
                                            ),
                                            backgroundColor: const Color(
                                              0xFFEAF0FF,
                                            ),
                                            labelStyle: TextStyle(
                                              color: activeSequence == word
                                                  ? Colors.white
                                                  : const Color(0xFF2864F0),
                                              fontWeight: FontWeight.w800,
                                            ),
                                            onSelected: (_) {
                                              setSheetState(() {
                                                activeSequence =
                                                    activeSequence == word
                                                    ? sequence
                                                    : word;
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        if (displayedPredictions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            target.isEmpty
                                ? '${displayedPredictions.length} huruf dikenali tanpa spasi'
                                : '${displayedPredictions.length} percobaan stabil direkam',
                            style: const TextStyle(
                              color: Color(0xFF7585A2),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: displayedPredictions
                                .map(
                                  (letter) => Chip(
                                    backgroundColor: const Color(0xFFEAF0FF),
                                    label: Text(
                                      letter,
                                      style: const TextStyle(
                                        color: Color(0xFF2864F0),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        if (target.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F8EF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              validationTotal == 0
                                  ? 'Validasi target $target: belum ada prediksi stabil.'
                                  : 'Validasi target $target: $validationCorrect/$validationTotal benar (${validationAccuracy.toStringAsFixed(1)}%).',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF087D5B),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _savedVideoPath == null
                        ? 'Video tidak berhasil disimpan.'
                        : 'Video tersimpan di:\n$_savedVideoPath',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF7585A2),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshPreviewSize(CameraController controller) async {
    bool isCurrent() => mounted && identical(controller, _controller);
    await synchronizeCameraPreviewSize(controller, isCurrent: isCurrent);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        if (!isCurrent()) return Future<void>.value();
        return synchronizeCameraPreviewSize(controller, isCurrent: isCurrent);
      }),
    );
  }

  Future<void> _disposeCamera() async {
    _cameraGeneration++;
    _resetRecognitionState();
    _isSessionActive = false;
    _isTargetAnalysisActive = false;
    try {
      await _queueCameraLifecycle(_releaseCamera);
    } catch (error) {
      if (mounted) _showMessage('Kamera gagal ditutup: $error');
    }
    if (mounted &&
        !_isStartingSession &&
        !_isEndingSession &&
        !_isTakingPhoto &&
        !_isClassifyingPhoto &&
        !_isSavingPhotoHistory) {
      widget.onBusyChanged?.call(false);
    }
  }

  Future<void> _releaseCamera() async {
    final controller = _controller;
    _controller = null;
    _isSessionActive = false;
    _isTargetAnalysisActive = false;
    _isTargetAnalysisStarting = false;
    if (controller == null) return;
    try {
      if (controller.value.isRecordingVideo) {
        final recording = await controller.stopVideoRecording();
        _savedVideoPath = await _saveRecording(recording);
      } else if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (error) {
      if (mounted) _showMessage('Kamera dihentikan: $error');
    } finally {
      await controller.dispose();
    }
  }

  void _setCameraError(String message) {
    if (!mounted) return;
    setState(() => _cameraError = message);
  }

  void _handleCameraOperationError(Object error, String message) {
    if (error is CameraException &&
        (error.code.startsWith('CameraAccessDenied') ||
            error.code == 'CameraAccessRestricted')) {
      _setCameraError(_friendlyCameraError(error));
      return;
    }
    _showMessage('$message: $error');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyCameraError(CameraException error) {
    return switch (error.code) {
      'CameraAccessDenied' =>
        'Izin kamera ditolak. Tekan tombol di bawah untuk meminta izin lagi.',
      'CameraAccessDeniedWithoutPrompt' => 'Izin kamera sebelumnya ditolak. Izinkan kamera dari Pengaturan aplikasi, lalu tekan Coba lagi.',
      'CameraAccessRestricted' => 'Akses kamera dibatasi oleh perangkat dan tidak dapat diminta dari aplikasi.',
      _ => 'Kamera gagal dibuka: ${error.description ?? error.code}',
    };
  }

  @override
  void dispose() {
    _photoGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_landmarkSubscription?.cancel());
    _handLandmarker?.dispose();
    unawaited(_disposeCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photoMode) return _buildPhotoScreen();
    final isTargetMode = _selectedTarget.isNotEmpty;
    final eventCount = _selectedTarget.isEmpty
        ? _sessionLetters.length
        : _validationPredictions.length;
    final validationCorrect = isTargetMode
        ? _validationPredictions
              .where((label) => label == _selectedTarget)
              .length
        : 0;
    final showLiveResults = _isSessionActive || isTargetMode;
    final showSetupControls = !_isSessionActive && !isTargetMode;
    return ColoredBox(
      key: const PageStorageKey('camera'),
      color: const Color(0xFFF4F7FC),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.24, 0.62, 1],
                  colors: [
                    Color(0xFFF4F7FC),
                    Color(0x18FFFFFF),
                    Color(0x12FFFFFF),
                    Color(0xFFF4F7FC),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + widget.topOverlayHeight + 12,
              16,
              16,
            ),
            child: Column(
              children: [
                if (showSetupControls) ...[
                  Container(
                    key: const ValueKey('camera-controls'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E9F3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _buildModeSelector()),
                        const SizedBox(width: 8),
                        StatusPill(
                          active: _isAnalysisActive,
                          handDetected: _handDetected,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ActiveModelCard(
                          model: _selectedModel.name,
                          onTap:
                              _isTakingPhoto ||
                                  _isClassifyingPhoto ||
                                  _isSavingPhotoHistory
                              ? null
                              : _showModelPicker,
                        ),
                      ),
                      const SizedBox(width: 8),
                      RoundCameraButton(
                        key: const ValueKey('camera-switch-button'),
                        tooltip: 'Ganti kamera',
                        onPressed:
                            _cameras.length > 1 &&
                                !_isTargetAnalysisStarting &&
                                !_isStartingSession &&
                                !_isEndingSession
                            ? _switchCamera
                            : null,
                        icon: Icons.cameraswitch_rounded,
                      ),
                    ],
                  ),
                ],
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: DetectionFrame(),
                  ),
                ),
                if (showLiveResults) ...[
                  LiveResultCard(
                    key: const ValueKey('camera-live-results'),
                    active: _isAnalysisActive || _isTargetAnalysisStarting,
                    handDetected: _handDetected,
                    eventCount: eventCount,
                    target: _selectedTarget,
                    latestPrediction: _latestTargetPrediction,
                    correctCount: validationCorrect,
                    sessionSequence: _sessionLetters.join(' '),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  key: const ValueKey('camera-primary-action'),
                  width: double.infinity,
                  height: 52,
                  child: _isSessionActive || _isEndingSession
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFC83B31),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _isEndingSession ? null : _endSession,
                          icon: const Icon(Icons.stop_circle_rounded),
                          label: Text(
                            _isEndingSession
                                ? 'Menyimpan hasil...'
                                : 'Selesai / Simpan Sesi Latihan',
                          ),
                        )
                      : isTargetMode
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFC83B31),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          onPressed: _isTargetAnalysisStarting
                              ? null
                              : () => unawaited(_handleTargetChanged('')),
                          icon: const Icon(Icons.stop_circle_rounded),
                          label: Text(
                            _isTargetAnalysisStarting
                                ? 'Menyiapkan deteksi...'
                                : 'Selesai Latihan Huruf',
                          ),
                        )
                      : FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2864F0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          onPressed:
                              !_isTargetAnalysisStarting &&
                                  !_isStartingSession &&
                                  !_isEndingSession
                              ? _cameraError != null
                                    ? _initializeCameras
                                    : (_controller?.value.isInitialized ??
                                          false)
                                    ? _startSession
                                    : null
                              : null,
                          icon: Icon(
                            _cameraError == null
                                ? Icons.play_circle_fill_rounded
                                : Icons.lock_open_rounded,
                          ),
                          label: Text(
                            _isStartingSession
                                ? 'Menyiapkan deteksi...'
                                : _cameraError == null
                                ? 'Mulai Latihan Bebas'
                                : 'Minta Izin Kamera Lagi',
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoScreen() {
    final path = _photoPath;
    final prediction = _photoPrediction;
    final busy = _isTakingPhoto || _isClassifyingPhoto || _isSavingPhotoHistory;
    final colors = Theme.of(context).colorScheme;
    final reliable = prediction?.accepted == true;
    return ColoredBox(
      key: const PageStorageKey('camera_photo'),
      color: colors.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (path == null)
            _buildCameraPreview()
          else
            Image.file(
              File(path),
              key: ValueKey(path),
              fit: BoxFit.contain,
              errorBuilder: (_, error, stackTrace) => Center(
                child: Text(
                  'Foto tidak dapat dibuka.',
                  style: TextStyle(color: colors.onSurface),
                ),
              ),
            ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.surface,
                    colors.surface.withValues(alpha: 0),
                    colors.surface,
                  ],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            minimum: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + widget.topOverlayHeight + 12,
              16,
              16,
            ),
            child: Column(
              children: [
                const SizedBox(height: 70),
                Row(
                  children: [
                    Expanded(
                      child: ActiveModelCard(
                        model: _selectedModel.name,
                        onTap: busy ? null : _showModelPicker,
                      ),
                    ),
                    if (path == null) ...[
                      const SizedBox(width: 8),
                      RoundCameraButton(
                        key: const ValueKey('camera-switch-button'),
                        tooltip: 'Ganti kamera',
                        onPressed:
                            _cameras.length > 1 && !busy && !_isInitializing
                            ? _switchCamera
                            : null,
                        icon: Icons.cameraswitch_rounded,
                      ),
                    ],
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: path == null
                        ? const DetectionFrame()
                        : const SizedBox.expand(),
                  ),
                ),
                if (prediction != null || path != null)
                  Container(
                    key: const ValueKey('photo-result-card'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.12),
                          blurRadius: 18,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (prediction != null) ...[
                          Text(
                            reliable ? prediction.label : 'Belum yakin',
                            style: TextStyle(
                              color: reliable
                                  ? colors.primary
                                  : const Color(0xFFAE7010),
                              fontSize: reliable ? 48 : 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            reliable
                                ? 'Prediksi crop sepakat'
                                : 'Prediksi crop berbeda',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          _photoHistorySaved
                              ? widget.onResultSaved == null
                                    ? 'Hasil foto ditampilkan.'
                                    : 'Hasil foto tersimpan di riwayat.'
                              : prediction != null && !reliable
                              ? 'Ambil ulang dengan tangan lebih jelas dan pencahayaan cukup.'
                              : 'Periksa foto, lalu tekan Deteksi. Ambil ulang jika tangan kurang jelas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                if (path == null)
                  SizedBox(
                    key: const ValueKey('photo-primary-action'),
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      onPressed: !busy
                          ? _cameraError != null
                                ? _initializeCameras
                                : (_controller?.value.isInitialized ?? false)
                                ? _takePhoto
                                : null
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(17),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: Text(
                        _isTakingPhoto
                            ? 'Mengambil foto...'
                            : _cameraError != null
                            ? 'Minta Izin Kamera Lagi'
                            : 'Ambil foto',
                      ),
                    ),
                  )
                else
                  Row(
                    key: const ValueKey('photo-primary-action'),
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.primary,
                            side: BorderSide(color: colors.outlineVariant),
                            minimumSize: const Size(0, 58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          onPressed: busy ? null : _retakePhoto,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Ambil ulang'),
                        ),
                      ),
                      if (!_photoHistorySaved &&
                          (prediction == null || reliable)) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2864F0),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 58),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            onPressed: busy ? null : _detectPhoto,
                            icon: const Icon(Icons.sign_language_rounded),
                            label: Text(
                              _isClassifyingPhoto
                                  ? 'Memproses...'
                                  : prediction == null
                                  ? 'Deteksi'
                                  : 'Simpan hasil',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedTarget,
            isExpanded: true,
            dropdownColor: colors.surface,
            borderRadius: BorderRadius.circular(18),
            iconEnabledColor: colors.primary,
            iconDisabledColor: colors.onSurface.withValues(alpha: 0.38),
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('MODE: LATIHAN BEBAS'),
              ),
              ..._supportedLabels.map(
                (label) => DropdownMenuItem(
                  value: label,
                  child: Text('MODE UJI: HURUF $label'),
                ),
              ),
            ],
            onChanged:
                _isSessionActive ||
                    _isTargetAnalysisStarting ||
                    _isStartingSession ||
                    _isEndingSession
                ? null
                : (value) => unawaited(_handleTargetChanged(value ?? '')),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final colors = Theme.of(context).colorScheme;
    if (!widget.cameraEnabled) {
      return Center(
        child: Text(
          'Kamera dinonaktifkan untuk pengujian.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      );
    }
    if (_isInitializing) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                color: colors.primary,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurface),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                ),
                onPressed: _initializeCameras,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: Text(
          'Kamera belum siap.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      );
    }
    return FullBleedCameraPreview(controller: controller);
  }
}
