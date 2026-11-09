import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/history_item.dart';
import '../models/jz_clip_result.dart';
import '../models/sign_prediction.dart';
import '../services/camera_preview_size.dart';
import '../services/image_preprocessor.dart';
import '../services/sign_classifier.dart';
import '../services/jz_recognition_service.dart';
import '../services/static_camera_pipeline.dart';
import '../widgets/full_bleed_camera_preview.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.cameraEnabled = true,
    this.photoMode = false,
    this.onResultSaved,
    this.onBusyChanged,
    this.topOverlayHeight = 0,
    this.jzServiceFactory,
    this.staticPipelineFactory,
  });

  final bool cameraEnabled;
  final bool photoMode;
  final Future<void> Function(HistoryItem)? onResultSaved;
  final ValueChanged<bool>? onBusyChanged;
  final double topOverlayHeight;
  final JzRecognitionService Function()? jzServiceFactory;
  final StaticCameraPipeline Function()? staticPipelineFactory;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  static const _handDetectionInterval = Duration(milliseconds: 320);
  static const _analysisInterval = Duration(milliseconds: 260);
  static const _minimumConfidence = 0.60;
  static const _stableFramesRequired = 2;
  static const _handPresenceWindow = Duration(milliseconds: 800);
  static const _handDetectionTimeout = Duration(seconds: 2);
  static const _jzOperationTimeout = Duration(seconds: 10);
  static const _jzCancellationTimeout = Duration(seconds: 2);
  static final _supportedLabels = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');

  CameraController? _controller;
  StaticCameraPipeline? _staticPipeline;
  StreamSubscription<StaticHandObservation>? _handSubscription;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _isInitializing = true;
  bool _isSessionActive = false;
  bool _isTargetAnalysisActive = false;
  bool _isTargetAnalysisStarting = false;
  bool _isProcessingFrame = false;
  bool _isHandDetectionPending = false;
  bool _handDetected = false;
  String? _cameraError;
  DateTime? _lastHandDetectionAt;
  DateTime? _lastAnalysisAt;
  DateTime? _lastHandSeenAt;
  List<Offset>? _latestHandLandmarks;
  String? _candidateLabel;
  int _candidateCount = 0;
  String? _lastCommittedLabel;
  int _releaseFrameCount = 0;
  final List<String> _sessionLetters = [];
  final List<double> _sessionConfidences = [];
  final List<String> _validationPredictions = [];
  String _selectedTarget = '';
  String? _latestTargetPrediction;
  double? _latestTargetConfidence;
  String? _savedVideoPath;
  int _analysisGeneration = 0;
  DateTime? _lastCameraDiagnosticAt;
  int? _lastFrameWidth;
  int? _lastFrameHeight;
  int? _lastFrameRotation;
  bool? _lastFrameMirrored;
  bool _isStartingSession = false;
  bool _isEndingSession = false;
  bool _isTakingPhoto = false;
  bool _isClassifyingPhoto = false;
  bool _isSavingPhotoHistory = false;
  String? _photoPath;
  SignPrediction? _photoPrediction;
  bool _photoHistorySaved = false;
  bool _appIsActive = true;
  int _cameraGeneration = 0;
  int _photoGeneration = 0;
  late final JzRecognitionService _jz =
      widget.jzServiceFactory?.call() ?? JzRecognitionService();
  final Stopwatch _jzClock = Stopwatch();
  bool _isJzStarting = false;
  bool _isJzCapturing = false;
  bool _isJzFinishing = false;
  bool _isJzCancelling = false;
  bool _awaitingStaticRelease = false;
  String? _jzFeedback;
  int _jzGeneration = 0;
  int? _lastJzTimestamp;
  Future<void>? _jzCancellation;
  Future<void>? _jzFinishOperation;
  Future<void>? _cameraDisposal;
  Future<void>? _interruptedSessionSave;
  HistoryItem? _pendingInterruptedHistory;
  Timer? _jzLimitTimer;
  // Native camera resources belong to the app, even when navigation destroys
  // this State. A new screen must wait for the old controller's disposal.
  static Future<void>? _cameraLifecycleQueue;

  bool get _isAnalysisActive => _isSessionActive || _isTargetAnalysisActive;
  bool get _isJzTarget => _selectedTarget == 'J' || _selectedTarget == 'Z';
  bool get _isJzBusy =>
      _isJzStarting || _isJzCapturing || _isJzFinishing || _isJzCancelling;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed) {
      _appIsActive = true;
      unawaited(_initializeCameras());
    }
  }

  @override
  void didUpdateWidget(covariant CameraScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraEnabled == widget.cameraEnabled &&
        oldWidget.photoMode == widget.photoMode) {
      return;
    }
    _photoGeneration++;
    unawaited(_disposeCamera());
    _photoPath = null;
    _photoPrediction = null;
    _photoHistorySaved = false;
    _savedVideoPath = null;
    _selectedTarget = '';
    _resetRecognitionState(clearFreeResults: true, clearTargetResults: true);
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
      if (_isCurrentCameraRequest(generation)) _setCameraError('$error');
    } finally {
      if (_isCurrentCameraRequest(generation)) {
        setState(() => _isInitializing = false);
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
      await _refreshPreviewSize(controller);
      if (!widget.photoMode && _selectedTarget.isNotEmpty) {
        await _startTargetAnalysis(resetResults: false);
      }
    });
  }

  Future<bool> _initializeStaticPipeline() async {
    if (_staticPipeline != null) return true;
    final pipeline =
        widget.staticPipelineFactory?.call() ?? StaticCameraPipeline();
    _staticPipeline = pipeline;
    try {
      await pipeline.initialize();
    } catch (_) {
      if (identical(_staticPipeline, pipeline)) _staticPipeline = null;
      pipeline.dispose();
      rethrow;
    }
    if (!mounted || !_appIsActive || !identical(pipeline, _staticPipeline)) {
      pipeline.dispose();
      return false;
    }
    _handSubscription = pipeline.generationObservations.listen(
      (observation) =>
          _acceptHandLandmarks(observation.hands, observation.generation),
      onError: (Object error) {
        _isHandDetectionPending = false;
        if (mounted) _showMessage('Hand detector gagal: $error');
      },
    );
    return true;
  }

  void _acceptHandLandmarks(List<Hand> hands, int generation) {
    // A detector result can arrive after a J/Z clip has invalidated the
    // static-analysis generation. It must not release the hand guard or feed
    // the CNN in the new generation.
    if (generation != _analysisGeneration) return;
    _isHandDetectionPending = false;
    if (!mounted || !_isAnalysisActive) return;
    if (_isJzBusy || _isJzTarget) return;
    final now = DateTime.now();
    final detectedHands = hands.where((hand) => hand.landmarks.isNotEmpty);
    final detected = detectedHands.isNotEmpty;
    if (_awaitingStaticRelease) {
      if (!detected) {
        setState(() {
          _awaitingStaticRelease = false;
          _jzFeedback = null;
        });
      }
      _handDetected = false;
      _lastHandSeenAt = null;
      _latestHandLandmarks = null;
      return;
    }
    if (detected) {
      _lastHandSeenAt = now;
      final landmarks = detectedHands.first.landmarks;
      _latestHandLandmarks = List<Offset>.unmodifiable(
        landmarks.map(
          (landmark) =>
              Offset(landmark.x.clamp(0.0, 1.0), landmark.y.clamp(0.0, 1.0)),
        ),
      );
    }
    final recentlyDetected =
        _lastHandSeenAt != null &&
        now.difference(_lastHandSeenAt!) <= _handPresenceWindow;
    if (!recentlyDetected) {
      _resetUnstablePrediction();
    }
    if (_handDetected != recentlyDetected) {
      setState(() => _handDetected = recentlyDetected);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 ||
        _isSessionActive ||
        _isJzStarting ||
        _isJzFinishing ||
        _isJzCancelling ||
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
      if (_isCurrentCameraRequest(generation)) _setCameraError('$error');
    } finally {
      if (_isCurrentCameraRequest(generation)) {
        setState(() => _isInitializing = false);
      }
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
      final pendingInterruptedSave = _interruptedSessionSave;
      if (pendingInterruptedSave != null) {
        await pendingInterruptedSave;
      }
      if (!mounted || !_appIsActive) return;
      // A failed database write must be retried before a new session clears
      // the accepted letters from the interrupted one.
      await _saveInterruptedSession();
      if (!await _initializeStaticPipeline()) return;
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
        await controller.startVideoRecording(onAvailable: _onCameraFrame);
        await _refreshPreviewSize(controller);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _isSessionActive = false);
        _showMessage('Tidak dapat memulai kamera: $error');
      }
    } finally {
      _isStartingSession = false;
      if (mounted) setState(() {});
      if (mounted && !_isSessionActive) widget.onBusyChanged?.call(false);
    }
  }

  Future<void> _handleTargetChanged(String target) async {
    if (widget.photoMode ||
        _isTargetAnalysisStarting ||
        _isJzCancelling ||
        _isSessionActive ||
        _isStartingSession ||
        _isEndingSession ||
        target == _selectedTarget) {
      return;
    }

    await _cancelJz();
    if (!mounted || !_appIsActive) return;
    if (_isJzTarget || target == 'J' || target == 'Z') {
      await _stopTargetImageStream();
      if (!mounted) return;
      _isTargetAnalysisActive = false;
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
    if (!streamAlreadyActive) {
      await _startTargetAnalysis(resetResults: false);
    }
  }

  Future<void> _startTargetAnalysis({bool resetResults = true}) async {
    final controller = _controller;
    if (widget.photoMode ||
        _selectedTarget.isEmpty ||
        _isJzTarget ||
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
      if (!await _initializeStaticPipeline()) return;
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
        _showMessage('Deteksi otomatis tidak dapat dimulai: $error');
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

  void _resetTargetResults() {
    if (_selectedTarget.isEmpty) return;
    setState(() => _resetRecognitionState(clearTargetResults: true));
  }

  Future<void> _startJzGesture() async {
    final controller = _controller;
    if (_isJzBusy ||
        widget.photoMode ||
        (!_isJzTarget && !_isSessionActive) ||
        _isStartingSession ||
        _isEndingSession ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    final generation = ++_jzGeneration;
    final cameraGeneration = _cameraGeneration;
    setState(() {
      _isJzStarting = true;
      _jzFeedback = 'Menyiapkan pembacaan gerakan...';
      _latestTargetPrediction = null;
      _latestTargetConfidence = null;
      _analysisGeneration++;
      _candidateLabel = null;
      _candidateCount = 0;
      _handDetected = false;
    });
    widget.onBusyChanged?.call(true);
    try {
      await _jz.startClip().timeout(_jzOperationTimeout);
      if (!_isCurrentCameraRequest(cameraGeneration) ||
          generation != _jzGeneration ||
          !identical(controller, _controller)) {
        return;
      }
      _jzClock
        ..reset()
        ..start();
      _lastJzTimestamp = null;
      setState(() {
        _isJzCapturing = true;
        _isTargetAnalysisActive = _isJzTarget;
        _jzFeedback =
            'Lakukan satu gerakan lengkap, lalu tekan Selesai gerakan.';
      });
      if (_isJzTarget) {
        await _queueCameraLifecycle(() async {
          if (!_isCurrentCameraRequest(cameraGeneration) ||
              generation != _jzGeneration) {
            return;
          }
          if (!controller.value.isStreamingImages) {
            await controller.startImageStream(_onCameraFrame);
            await _refreshPreviewSize(controller);
          }
        });
      }
      if (generation != _jzGeneration) return;
      setState(() => _isJzStarting = false);
      // A single gesture must not grow into an unbounded multi-letter video.
      _jzLimitTimer = Timer(const Duration(seconds: 10), () {
        unawaited(_abortJz('Gerakan terlalu lama. Ulangi satu gerakan J/Z.'));
      });
    } catch (error) {
      if (generation == _jzGeneration) {
        await _abortJz('Gerakan tidak dapat dimulai: $error');
      }
    }
  }

  Future<void> _sendJzFrame(
    CameraImage image,
    int timestamp,
    int rotation,
    int generation,
  ) async {
    try {
      final receipt = await _jz.addCameraFrame(
        image,
        timestampMs: timestamp,
        rotationDegrees: rotation,
      );
      if (!mounted || generation != _jzGeneration || !_isJzCapturing) return;
      if (receipt.handDetected case final detected?) {
        if (_handDetected != detected) setState(() => _handDetected = detected);
      }
    } catch (error) {
      if (generation == _jzGeneration && _isJzCapturing) {
        await _abortJz('Gerakan terhenti: $error');
      }
    }
  }

  Future<void> _finishJzGesture() {
    if (_jzFinishOperation case final pending?) return pending;
    if (!_isJzCapturing) return Future<void>.value();
    late final Future<void> operation;
    operation = _completeJzGesture().whenComplete(() {
      if (identical(_jzFinishOperation, operation)) _jzFinishOperation = null;
    });
    _jzFinishOperation = operation;
    return operation;
  }

  Future<void> _completeJzGesture() async {
    final generation = _jzGeneration;
    final target = _selectedTarget;
    final inFreeSession = _isSessionActive;
    _jzLimitTimer?.cancel();
    _jzClock.stop();
    setState(() {
      _isJzCapturing = false;
      _isJzFinishing = true;
      _jzFeedback = 'Sedang membaca gerakan...';
    });
    try {
      final result = await _jz.finishClip().timeout(_jzOperationTimeout);
      if (!mounted || generation != _jzGeneration) return;
      final letter = result.letter;
      setState(() {
        _latestTargetPrediction = letter;
        _latestTargetConfidence = letter == null
            ? null
            : result.prediction!.confidence;
        if (letter != null) {
          if (inFreeSession) {
            _sessionLetters.add(letter);
            _sessionConfidences.add(result.prediction!.confidence);
          } else {
            _validationPredictions.add(letter);
          }
        }
        _jzFeedback = letter != null
            ? inFreeSession
                  ? 'Gerakan diterima. Turunkan tangan sebelum huruf berikutnya.'
                  : letter == target
                  ? 'Benar: terdeteksi $letter. Hasil gerakan diterima.'
                  : 'Belum tepat: terdeteksi $letter, target $target.'
            : switch (result.status) {
                JzClipStatus.rejected =>
                  result.message ?? 'Tangan kurang terlihat. Ulangi gerakan.',
                JzClipStatus.other =>
                  'Gerakan belum dikenali sebagai J/Z. Silakan ulangi.',
                _ => 'Model belum yakin. Ulangi satu gerakan lengkap.',
              };
      });
      // A target is a comparison, never a replacement for the predicted letter.
      if (letter != null && !inFreeSession) {
        try {
          await widget.onResultSaved?.call(
            HistoryItem.fromDetection(
              gesture: letter,
              confidence: result.prediction!.confidence,
              source: 'motion',
            ),
          );
        } catch (error) {
          _showMessage(
            'Hasil gerakan tampil, tetapi riwayat gagal disimpan: $error',
          );
        }
      }
    } catch (error) {
      if (mounted && generation == _jzGeneration) {
        if (error is TimeoutException) {
          await _abortJz(
            'Pembacaan gerakan terlalu lama. Silakan ulangi.',
            waitForFinish: false,
          );
        } else {
          setState(
            () => _jzFeedback = 'Gerakan gagal diproses. Silakan ulangi.',
          );
          _showMessage('Pembacaan gerakan gagal: $error');
        }
      }
    } finally {
      if (generation == _jzGeneration) {
        if (!inFreeSession) await _stopTargetImageStream();
        if (generation == _jzGeneration) {
          _isJzFinishing = false;
          _isTargetAnalysisActive = false;
          _resetAfterMotion(inFreeSession);
          if (mounted) {
            setState(() {});
            if (!inFreeSession) widget.onBusyChanged?.call(false);
          }
        }
      }
    }
  }

  void _resetAfterMotion(bool inFreeSession) {
    _analysisGeneration++;
    _candidateLabel = null;
    _candidateCount = 0;
    _lastCommittedLabel = null;
    _releaseFrameCount = 0;
    _lastHandSeenAt = null;
    _latestHandLandmarks = null;
    _lastHandDetectionAt = null;
    _isHandDetectionPending = false;
    _handDetected = false;
    _awaitingStaticRelease = inFreeSession;
  }

  Future<void> _abortJz(String message, {bool waitForFinish = true}) async {
    final generation = _jzGeneration;
    await _cancelJz(waitForFinish: waitForFinish);
    if (!mounted || _jzGeneration != generation + 1) return;
    setState(() => _jzFeedback = message);
  }

  Future<void> _cancelJz({bool waitForFinish = true}) {
    if (_jzCancellation case final pending?) return pending;
    if (!_isJzBusy) return Future<void>.value();
    _jzGeneration++;
    _jzLimitTimer?.cancel();
    _jzClock.stop();
    _isJzStarting = false;
    _isJzCapturing = false;
    _isJzFinishing = false;
    _isJzCancelling = true;
    final inFreeSession = _isSessionActive;
    late final Future<void> operation;
    operation =
        () async {
          try {
            await _jz.cancelClip().timeout(_jzCancellationTimeout);
            // Let an interrupted frontend completion unwind before accepting
            // the next clip. Its result has already been invalidated above.
            final pendingFinish = _jzFinishOperation;
            if (waitForFinish && pendingFinish != null) {
              await pendingFinish.timeout(_jzCancellationTimeout);
            }
          } catch (error) {
            _showMessage('Pembacaan gerakan gagal dibatalkan: $error');
          } finally {
            if (!inFreeSession) await _stopTargetImageStream();
            _isJzCancelling = false;
            if (!inFreeSession) _isTargetAnalysisActive = false;
            _resetAfterMotion(inFreeSession);
            _jzFeedback = inFreeSession
                ? 'Gerakan dibatalkan. Turunkan tangan sebelum melanjutkan.'
                : 'Gerakan dibatalkan. Tekan Mulai gerakan untuk mengulang.';
            if (mounted) {
              setState(() {});
              if (!inFreeSession) widget.onBusyChanged?.call(false);
            }
          }
        }().whenComplete(() {
          if (identical(_jzCancellation, operation)) _jzCancellation = null;
        });
    _jzCancellation = operation;
    return operation;
  }

  void _resetRecognitionState({
    bool clearFreeResults = false,
    bool clearTargetResults = false,
  }) {
    if (clearFreeResults) {
      _sessionLetters.clear();
      _sessionConfidences.clear();
    }
    if (clearTargetResults) _validationPredictions.clear();
    _candidateLabel = null;
    _candidateCount = 0;
    _lastCommittedLabel = null;
    _releaseFrameCount = 0;
    _handDetected = false;
    _lastHandDetectionAt = null;
    _lastAnalysisAt = null;
    _lastHandSeenAt = null;
    _latestHandLandmarks = null;
    _isHandDetectionPending = false;
    _latestTargetPrediction = null;
    _latestTargetConfidence = null;
    _jzFeedback = null;
    _awaitingStaticRelease = false;
    _analysisGeneration++;
  }

  void _onCameraFrame(CameraImage cameraImage) {
    if (!_isAnalysisActive) return;
    final controller = _controller;
    if (controller == null) return;
    final rotation = ImagePreprocessor.effectivePortraitRotation(
      frameWidth: cameraImage.width,
      frameHeight: cameraImage.height,
      requestedRotationDegrees: _imageRotation(controller),
    );
    // Fresh raw frames reach the temporal model before the static throttles
    // and cached-hand checks. Never mirror the input to match the preview.
    if (_isJzCapturing) {
      final timestamp = _jzClock.elapsedMilliseconds;
      if (_lastJzTimestamp != null && timestamp <= _lastJzTimestamp!) return;
      _lastJzTimestamp = timestamp;
      unawaited(_sendJzFrame(cameraImage, timestamp, rotation, _jzGeneration));
      return;
    }
    if (_isJzBusy || _isJzTarget || _isEndingSession) return;
    final now = DateTime.now();
    if (_isHandDetectionPending &&
        _lastHandDetectionAt != null &&
        now.difference(_lastHandDetectionAt!) >= _handDetectionTimeout) {
      _isHandDetectionPending = false;
    }
    if (!_isHandDetectionPending &&
        (_lastHandDetectionAt == null ||
            now.difference(_lastHandDetectionAt!) >= _handDetectionInterval)) {
      _lastHandDetectionAt = now;
      _isHandDetectionPending = true;
      try {
        _staticPipeline?.detectHandsForGeneration(
          cameraImage,
          rotation,
          _analysisGeneration,
        );
      } catch (error) {
        _isHandDetectionPending = false;
        if (mounted) {
          _showMessage('Hand detector gagal memproses frame: $error');
        }
      }
    }
    if (_awaitingStaticRelease) return;
    final handIsFresh =
        _lastHandSeenAt != null &&
        now.difference(_lastHandSeenAt!) <= _handPresenceWindow;
    if (!handIsFresh) {
      _latestHandLandmarks = null;
      _resetUnstablePrediction();
      return;
    }
    if (_isProcessingFrame) return;
    if (_lastAnalysisAt != null &&
        now.difference(_lastAnalysisAt!) < _analysisInterval) {
      return;
    }
    _lastAnalysisAt = now;
    _isProcessingFrame = true;
    final analysisGeneration = _analysisGeneration;

    // CameraPreview mirrors the front camera for the user, but the raw image
    // stream and MediaPipe landmarks are not mirrored. Keep their geometry
    // aligned. Any experimental model-input mirror is handled by SignClassifier
    // and must not mirror the preview or MediaPipe coordinates a second time.
    const mirrorForModel = false;
    _lastFrameWidth = cameraImage.width;
    _lastFrameHeight = cameraImage.height;
    _lastFrameRotation = rotation;
    _lastFrameMirrored = mirrorForModel;
    final landmarks = _latestHandLandmarks;
    if (landmarks == null || landmarks.length != 21) {
      _isProcessingFrame = false;
      return;
    }
    _staticPipeline!
        .classify(
          cameraImage,
          rotationDegrees: rotation,
          mirrorHorizontally: mirrorForModel,
          normalizedLandmarks: landmarks,
        )
        .then((prediction) => _acceptPrediction(prediction, analysisGeneration))
        .catchError((Object error) {
          if (mounted) _showMessage('Frame gagal diproses: $error');
        })
        .whenComplete(() => _isProcessingFrame = false);
  }

  void _acceptPrediction(SignPrediction prediction, int analysisGeneration) {
    if (!mounted ||
        !_isAnalysisActive ||
        _isJzBusy ||
        _isJzTarget ||
        _awaitingStaticRelease ||
        _isEndingSession ||
        analysisGeneration != _analysisGeneration) {
      return;
    }
    unawaited(_saveCameraDiagnostic(prediction));

    if (_isTargetAnalysisActive) {
      setState(() {
        _latestTargetPrediction = prediction.label;
        _latestTargetConfidence = prediction.confidence;
      });
    }

    if (prediction.confidence < _minimumConfidence) {
      _candidateLabel = null;
      _candidateCount = 0;
      _releaseFrameCount++;
      return;
    }
    if (_lastCommittedLabel != null &&
        prediction.label != _lastCommittedLabel) {
      _releaseFrameCount++;
    }
    if (_candidateLabel == prediction.label) {
      _candidateCount++;
    } else {
      _candidateLabel = prediction.label;
      _candidateCount = 1;
    }
    final mayRepeatLastLetter =
        prediction.label == _lastCommittedLabel && _releaseFrameCount >= 2;
    if (_candidateCount >= _stableFramesRequired) {
      if (prediction.label != _lastCommittedLabel || mayRepeatLastLetter) {
        setState(() {
          if (_isSessionActive) {
            _sessionLetters.add(prediction.label);
            _sessionConfidences.add(prediction.confidence);
          } else if (_isTargetAnalysisActive) {
            _validationPredictions.add(prediction.label);
          }
        });
        _lastCommittedLabel = prediction.label;
        _releaseFrameCount = 0;
      }
      _candidateCount = 0;
    }
  }

  void _resetUnstablePrediction() {
    _candidateLabel = null;
    _candidateCount = 0;
    _releaseFrameCount++;
  }

  Future<void> _saveCameraDiagnostic(SignPrediction finalPrediction) async {
    if (!kDebugMode) return;
    final now = DateTime.now();
    if (_lastCameraDiagnosticAt != null &&
        now.difference(_lastCameraDiagnosticAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastCameraDiagnosticAt = now;
    try {
      final classifier = SignClassifier.instance;
      final contextPng = classifier.lastContextInputPng;
      if (contextPng == null) return;
      final tightPng = classifier.lastTightInputPng;
      final metadata = <String, Object?>{
        'final_prediction': _predictionJson(finalPrediction),
        'context_prediction': _predictionJson(classifier.lastContextPrediction),
        'tight_prediction': _predictionJson(classifier.lastTightPrediction),
        'landmark_prediction': _predictionJson(
          classifier.lastLandmarkPrediction,
        ),
        'sensor_orientation': _controller?.description.sensorOrientation,
        'device_orientation': _controller?.value.deviceOrientation.name,
        'capture_orientation':
            _controller?.value.lockedCaptureOrientation?.name,
        'recording_orientation': _controller?.value.recordingOrientation?.name,
        'preview_width': _controller?.value.previewSize?.width,
        'preview_height': _controller?.value.previewSize?.height,
        'native_preview': _controller == null
            ? null
            : cameraPreviewGeometry(_controller!).value?.toJson(),
        'lens_direction': _controller?.description.lensDirection.name,
        'frame_width': _lastFrameWidth,
        'frame_height': _lastFrameHeight,
        'rotation_degrees': _lastFrameRotation,
        'mirrored': _lastFrameMirrored,
        'mediapipe_landmarks': _latestHandLandmarks
            ?.map((point) => <double>[point.dx, point.dy])
            .toList(growable: false),
      };
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(
        '${documents.path}${Platform.pathSeparator}camera_diagnostic',
      );
      await directory.create(recursive: true);
      await File(
        '${directory.path}${Platform.pathSeparator}model_input_context.png',
      ).writeAsBytes(contextPng, flush: true);
      final tightPath =
          '${directory.path}${Platform.pathSeparator}model_input_tight.png';
      if (tightPng != null) {
        await File(tightPath).writeAsBytes(tightPng, flush: true);
      } else {
        final staleTightFile = File(tightPath);
        if (await staleTightFile.exists()) await staleTightFile.delete();
      }
      await File('${directory.path}${Platform.pathSeparator}metadata.json')
          .writeAsString(
            const JsonEncoder.withIndent('  ').convert(metadata),
            flush: true,
          );
    } catch (_) {
      _lastCameraDiagnosticAt = null;
    }
  }

  static Map<String, Object?>? _predictionJson(SignPrediction? prediction) {
    if (prediction == null) return null;
    return <String, Object?>{
      'label': prediction.label,
      'confidence': prediction.confidence,
    };
  }

  Future<void> _endSession() async {
    if (_isEndingSession || !_isSessionActive || _isJzStarting) return;
    setState(() {
      _isEndingSession = true;
      _analysisGeneration++;
    });
    // Include the final complete motion decision before freezing the transcript.
    await _finishJzGesture();
    await _jzCancellation;
    if (!mounted || !_isSessionActive) {
      _isEndingSession = false;
      if (mounted) {
        setState(() {});
        widget.onBusyChanged?.call(false);
      }
      return;
    }
    final controller = _controller;
    final sequence = _sessionLetters.join();
    final confidence = _sessionConfidences.isEmpty
        ? 0.0
        : _sessionConfidences.reduce((a, b) => a + b) /
              _sessionConfidences.length;
    // Freeze accepted letters immediately. In-flight inference cannot append
    // a letter after Stop or create a second history record.
    setState(() {
      _isSessionActive = false;
      _analysisGeneration++;
    });
    String? videoPath;
    try {
      await _queueCameraLifecycle(() async {
        if (!identical(controller, _controller)) return;
        if (controller?.value.isRecordingVideo ?? false) {
          final recording = await controller!.stopVideoRecording();
          await _refreshPreviewSize(controller);
          videoPath = await _saveRecording(recording);
        } else if (controller?.value.isStreamingImages ?? false) {
          await controller!.stopImageStream();
          await _refreshPreviewSize(controller);
        }
      });
    } catch (error) {
      if (mounted) _showMessage('Rekaman video gagal disimpan: $error');
    }
    if (mounted) {
      setState(() {
        _isProcessingFrame = false;
        _handDetected = false;
        _latestHandLandmarks = null;
        _savedVideoPath = videoPath;
      });
    }
    try {
      if (sequence.isNotEmpty) {
        await widget.onResultSaved?.call(
          HistoryItem.fromDetection(
            gesture: sequence,
            confidence: confidence,
            source: 'video',
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
    if (mounted) await _showSessionResult();
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
      _showMessage('Foto gagal diambil: $error');
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
      // classifyFile decodes EXIF orientation before grayscale/resizing.
      // This plugin exposes MediaPipe only for live CameraImage frames;
      // a still image is never given stale landmarks from another frame.
      final prediction =
          _photoPrediction ?? await SignClassifier.instance.classifyFile(path);
      if (!mounted || generation != _photoGeneration) return;
      setState(() => _photoPrediction = prediction);
      if (prediction.confidence >= _minimumConfidence) {
        _isSavingPhotoHistory = true;
        await widget.onResultSaved?.call(
          HistoryItem.fromDetection(
            gesture: prediction.label,
            confidence: prediction.confidence,
            source: 'photo',
            imagePath: path,
          ),
        );
        if (mounted && generation == _photoGeneration) {
          setState(() => _photoHistorySaved = true);
        }
      }
    } catch (error) {
      _showMessage('Foto gagal diproses atau disimpan: $error');
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
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF4F7FC),
      builder: (context) => SafeArea(
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
                          sequence.isEmpty
                              ? 'Belum ada huruf yang stabil.'
                              : sequence,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: sequence.isEmpty
                                ? const Color(0xFF7585A2)
                                : const Color(0xFF2864F0),
                            fontSize: sequence.isEmpty ? 15 : 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: sequence.isEmpty ? 0 : 6,
                          ),
                        ),
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
    );
  }

  int _imageRotation(CameraController controller) {
    const deviceDegrees = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final captureOrientation =
        controller.value.lockedCaptureOrientation ??
        controller.value.deviceOrientation;
    final device = deviceDegrees[captureOrientation] ?? 0;
    final sensor = controller.description.sensorOrientation;
    return controller.description.lensDirection == CameraLensDirection.front
        ? (sensor + device) % 360
        : (sensor - device + 360) % 360;
  }

  Future<void> _refreshPreviewSize(CameraController controller) {
    return synchronizeCameraPreviewSize(
      controller,
      isCurrent: () => mounted && identical(controller, _controller),
    );
  }

  Future<void> _disposeCamera() async {
    final pendingDisposal = _cameraDisposal;
    if (pendingDisposal != null) return pendingDisposal;
    final previousSave = _interruptedSessionSave;
    _cameraGeneration++;
    final interruptedLetters = List<String>.of(_sessionLetters);
    final interruptedConfidences = List<double>.of(_sessionConfidences);
    final shouldSaveInterruptedSession =
        _isSessionActive && interruptedLetters.isNotEmpty;
    if (shouldSaveInterruptedSession) {
      _pendingInterruptedHistory = HistoryItem.fromDetection(
        gesture: interruptedLetters.join(),
        confidence: interruptedConfidences.isEmpty
            ? 0.0
            : interruptedConfidences.reduce((a, b) => a + b) /
                  interruptedConfidences.length,
        source: 'video',
      );
    }
    final motionCancellation = _cancelJz();
    _isSessionActive = false;
    _isTargetAnalysisActive = false;
    _analysisGeneration++;
    // Enqueue release immediately, before a rapid resume can enqueue an open.
    late final Future<void> cameraRelease;
    cameraRelease =
        _queueCameraLifecycle(() async {
          await motionCancellation;
          await _releaseCamera();
        }).whenComplete(() {
          if (identical(_cameraDisposal, cameraRelease)) _cameraDisposal = null;
        });
    _cameraDisposal = cameraRelease;
    late final Future<void> operation;
    operation =
        () async {
          await cameraRelease;
          // Releasing a resumed camera must not wait for the previous write.
          // Keep writes serialized separately so a new session cannot retry
          // the same pending history concurrently.
          if (previousSave != null) {
            try {
              await previousSave;
            } catch (_) {
              // The original caller reports the failure. Start will retry it.
            }
          }
          if (shouldSaveInterruptedSession) {
            _pendingInterruptedHistory = _pendingInterruptedHistory?.copyWith(
              videoPath: _savedVideoPath,
            );
            await _saveInterruptedSession();
          }
        }().whenComplete(() {
          if (identical(_interruptedSessionSave, operation)) {
            _interruptedSessionSave = null;
          }
        });
    _interruptedSessionSave = operation;
    try {
      await operation;
    } catch (error) {
      if (mounted) _showMessage('Penutupan sesi belum selesai: $error');
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
    await _cancelJz();
    final controller = _controller;
    _controller = null;
    if (mounted) setState(() {});
    _isSessionActive = false;
    _isTargetAnalysisActive = false;
    _isTargetAnalysisStarting = false;
    _isHandDetectionPending = false;
    _analysisGeneration++;
    await _handSubscription?.cancel();
    _handSubscription = null;
    _staticPipeline?.dispose();
    _staticPipeline = null;
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

  Future<void> _saveInterruptedSession() async {
    final history = _pendingInterruptedHistory;
    if (history == null) return;
    await widget.onResultSaved?.call(history);
    if (identical(history, _pendingInterruptedHistory)) {
      _pendingInterruptedHistory = null;
    }
  }

  void _setCameraError(String message) {
    if (!mounted) return;
    setState(() => _cameraError = message);
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
        'Izin kamera ditolak. Aktifkan izin dari pengaturan.',
      'CameraAccessDeniedWithoutPrompt' =>
        'Izin kamera diblokir. Aktifkan izin dari pengaturan.',
      _ => 'Kamera gagal dibuka: ${error.description ?? error.code}',
    };
  }

  @override
  void dispose() {
    _photoGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _jzLimitTimer?.cancel();
    unawaited(
      _disposeCamera().whenComplete(_jz.dispose).catchError((Object error) {
        debugPrint('Penutupan kamera/JZ: $error');
      }),
    );
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
          const Positioned.fill(child: IgnorePointer(child: _DetectionFrame())),
          SafeArea(
            minimum: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 12 + widget.topOverlayHeight,
              16,
              MediaQuery.sizeOf(context).height < 700 ? 88 : 102,
            ),
            child: _ScrollableCameraControls(
              children: [
                _CameraHeader(
                  title: 'Kamera Latihan',
                  subtitle: 'Deteksi isyarat secara langsung',
                  trailing: _RoundCameraButton(
                    tooltip: 'Ganti kamera',
                    onPressed:
                        _cameras.length > 1 &&
                            !_isSessionActive &&
                            !_isJzStarting &&
                            !_isJzFinishing &&
                            !_isJzCancelling &&
                            !_isTargetAnalysisStarting &&
                            !_isStartingSession &&
                            !_isEndingSession
                        ? _switchCamera
                        : null,
                    icon: Icons.cameraswitch_rounded,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
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
                      _StatusPill(
                        active: _isAnalysisActive,
                        handDetected: _handDetected,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _LiveResultCard(
                  active: _isAnalysisActive,
                  handDetected: _handDetected,
                  eventCount: eventCount,
                  target: _selectedTarget,
                  latestPrediction: _latestTargetPrediction,
                  latestConfidence: _latestTargetConfidence,
                  correctCount: validationCorrect,
                  motionTarget: _isJzTarget,
                  motionBusy: _isJzBusy,
                  motionFeedback: _jzFeedback,
                ),
                const SizedBox(height: 10),
                if (_isSessionActive) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: _buildJzControl(),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: _isJzTarget
                      ? _buildJzControl()
                      : isTargetMode
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFF1D6),
                            foregroundColor: const Color(0xFF92610A),
                          ),
                          onPressed: _resetTargetResults,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text('Reset hasil uji $_selectedTarget'),
                        )
                      : _isSessionActive || _isEndingSession
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFC83B31),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _isEndingSession || _isJzStarting
                              ? null
                              : _endSession,
                          icon: const Icon(Icons.stop_circle_rounded),
                          label: Text(
                            _isEndingSession
                                ? 'Menyimpan hasil...'
                                : 'Akhiri dan lihat hasil',
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
                              (_controller?.value.isInitialized ?? false) &&
                                  !_isTargetAnalysisStarting &&
                                  !_isStartingSession &&
                                  !_isEndingSession
                              ? _startSession
                              : null,
                          icon: const Icon(Icons.play_circle_fill_rounded),
                          label: Text(
                            _isStartingSession
                                ? 'Menyiapkan deteksi...'
                                : 'Mulai latihan bebas',
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
    final reliable =
        prediction != null && prediction.confidence >= _minimumConfidence;
    return ColoredBox(
      key: const PageStorageKey('camera_photo'),
      color: const Color(0xFFF4F7FC),
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
              errorBuilder: (_, error, stackTrace) => const Center(
                child: Text(
                  'Foto tidak dapat dibuka.',
                  style: TextStyle(color: Color(0xFF172642)),
                ),
              ),
            ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF4F7FC),
                    Color(0x00000000),
                    Color(0xFFF4F7FC),
                  ],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
          ),
          if (path == null)
            const Positioned.fill(
              child: IgnorePointer(child: _DetectionFrame()),
            ),
          SafeArea(
            minimum: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 12 + widget.topOverlayHeight,
              16,
              MediaQuery.sizeOf(context).height < 700 ? 88 : 102,
            ),
            child: Column(
              children: [
                _CameraHeader(
                  title: 'Foto Isyarat',
                  subtitle: '24 huruf statis. Gunakan Video untuk J/Z.',
                  trailing: path == null
                      ? _RoundCameraButton(
                          tooltip: 'Ganti kamera',
                          onPressed:
                              _cameras.length > 1 && !busy && !_isInitializing
                              ? _switchCamera
                              : null,
                          icon: Icons.cameraswitch_rounded,
                        )
                      : null,
                ),
                if (prediction == null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF0FF),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'MODE FOTO · SATU HURUF',
                        style: TextStyle(
                          color: Color(0xFF2864F0),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (prediction != null || path != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x180E2343),
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
                                  ? const Color(0xFF00A879)
                                  : const Color(0xFFAE7010),
                              fontSize: reliable ? 48 : 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Keyakinan model ${(prediction.confidence * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Color(0xFF7585A2),
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
                          style: const TextStyle(
                            color: Color(0xFF52627D),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                if (path == null)
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      onPressed:
                          !busy && (_controller?.value.isInitialized ?? false)
                          ? _takePhoto
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2864F0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(17),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: Text(
                        _isTakingPhoto ? 'Mengambil foto...' : 'Ambil foto',
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2864F0),
                            side: const BorderSide(color: Color(0xFFDCE4F1)),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCE4F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E2343),
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
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(18),
            iconEnabledColor: const Color(0xFF2864F0),
            iconDisabledColor: const Color(0xFF9AA8BD),
            style: const TextStyle(
              color: Color(0xFF172642),
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
                    _isEndingSession ||
                    _isJzStarting ||
                    _isJzFinishing ||
                    _isJzCancelling
                ? null
                : (value) => unawaited(_handleTargetChanged(value ?? '')),
          ),
        ),
      ),
    );
  }

  Widget _buildJzControl() {
    final blocked =
        _isJzStarting ||
        _isInitializing ||
        _isTargetAnalysisStarting ||
        _isJzFinishing ||
        _isJzCancelling ||
        _isEndingSession ||
        !(_controller?.value.isInitialized ?? false);
    final label = _isJzStarting
        ? 'Menyiapkan gerakan...'
        : _isJzFinishing
        ? 'Membaca gerakan...'
        : _isJzCancelling
        ? 'Membatalkan gerakan...'
        : _isJzCapturing
        ? 'Selesai gerakan'
        : _isJzTarget
        ? 'Mulai gerakan $_selectedTarget'
        : 'Mulai J/Z';
    return FilledButton.icon(
      key: const ValueKey('jz-gesture-control'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFFF1D6),
        foregroundColor: const Color(0xFF92610A),
      ),
      onPressed: blocked
          ? null
          : _isJzCapturing
          ? _finishJzGesture
          : _startJzGesture,
      icon: Icon(_isJzCapturing ? Icons.stop_circle_rounded : Icons.gesture),
      label: Text(label),
    );
  }

  Widget _buildCameraPreview() {
    if (!widget.cameraEnabled) {
      return const Center(
        child: Text(
          'Kamera dinonaktifkan untuk pengujian.',
          style: TextStyle(color: Color(0xFF52627D)),
        ),
      );
    }
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2864F0)),
      );
    }
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Color(0xFF2864F0),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF172642)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2864F0),
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
      return const Center(
        child: Text(
          'Kamera belum siap.',
          style: TextStyle(color: Color(0xFF52627D)),
        ),
      );
    }
    return FullBleedCameraPreview(controller: controller);
  }
}

/// Keeps the overlay bottom-aligned while allowing access to every control
/// when navigation, system insets, or larger text leave too little height.
class _ScrollableCameraControls extends StatelessWidget {
  const _ScrollableCameraControls({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(child: Column(children: children)),
      ),
    ),
  );
}

class _CameraHeader extends StatelessWidget {
  const _CameraHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E9F3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160E2343),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF172642),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF596B87),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _RoundCameraButton extends StatelessWidget {
  const _RoundCameraButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2864F0),
        disabledBackgroundColor: const Color(0xFFE8EDF5),
        disabledForegroundColor: const Color(0xFF9AA8BD),
        minimumSize: const Size.square(48),
        elevation: 2,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class _DetectionFrame extends StatelessWidget {
  const _DetectionFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.78,
        heightFactor: 0.42,
        child: Container(
          key: const ValueKey('camera-detection-frame'),
          decoration: BoxDecoration(
            color: const Color(0x182864F0),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xCC2864F0), width: 2),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active, required this.handDetected});

  final bool active;
  final bool handDetected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCE4F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E2343),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active && handDetected
                  ? Icons.back_hand_rounded
                  : active
                  ? Icons.search_rounded
                  : Icons.pause_circle_outline,
              size: 10,
              color: active && handDetected
                  ? const Color(0xFF00A879)
                  : active
                  ? const Color(0xFFE3A21A)
                  : const Color(0xFF7585A2),
            ),
            const SizedBox(width: 7),
            Text(
              active && handDetected
                  ? 'TANGAN TERDETEKSI'
                  : active
                  ? 'CARI TANGAN'
                  : 'SIAP',
              style: const TextStyle(
                color: Color(0xFF172642),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveResultCard extends StatelessWidget {
  const _LiveResultCard({
    required this.active,
    required this.handDetected,
    required this.eventCount,
    required this.target,
    required this.latestPrediction,
    required this.latestConfidence,
    required this.correctCount,
    this.motionTarget = false,
    this.motionBusy = false,
    this.motionFeedback,
  });

  final bool active;
  final bool handDetected;
  final int eventCount;
  final String target;
  final String? latestPrediction;
  final double? latestConfidence;
  final int correctCount;
  final bool motionTarget;
  final bool motionBusy;
  final String? motionFeedback;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E9F3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140E2343),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF0FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                target.isNotEmpty
                    ? handDetected || motionTarget
                          ? _predictionIsReliable
                                ? latestPrediction ?? '?'
                                : '?'
                          : '?'
                    : active
                    ? '$eventCount'
                    : '-',
                style: const TextStyle(
                  color: Color(0xFF2864F0),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: const TextStyle(
                      color: Color(0xFF172642),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _description,
                    style: const TextStyle(
                      color: Color(0xFF7585A2),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _title {
    if (motionTarget) {
      if (motionBusy) return 'Membaca gerakan $target';
      if (_predictionIsReliable) {
        return latestPrediction == target
            ? 'Benar: terdeteksi $target'
            : 'Belum tepat: terdeteksi $latestPrediction';
      }
      return 'Latihan gerakan $target';
    }
    if (motionBusy) return 'Membaca satu gerakan J/Z';
    if (motionFeedback != null) return 'Latihan bebas';
    if (target.isNotEmpty) {
      if (!active) return 'Deteksi otomatis menunggu kamera';
      if (!handDetected) return 'Tampilkan tangan untuk huruf $target';
      if (latestPrediction == null) return 'Menganalisis target $target';
      if (!_predictionIsReliable) return 'Belum yakin, tahan pose sebentar';
      return latestPrediction == target
          ? 'Benar: terdeteksi $target'
          : 'Belum tepat: terdeteksi $latestPrediction';
    }
    if (!active) {
      return 'Tekan Mulai untuk latihan bebas';
    }
    if (!handDetected) {
      return 'Tampilkan tangan ke kamera';
    }
    return 'Tangan terdeteksi';
  }

  String get _description {
    if (motionTarget && !motionBusy && _predictionIsReliable) {
      return '$correctCount/$eventCount gerakan diterima sesuai target. '
          'Keyakinan ${(latestConfidence! * 100).toStringAsFixed(1)}%.';
    }
    if (motionFeedback != null) return motionFeedback!;
    if (motionTarget) {
      return 'Tekan Mulai gerakan, peragakan lengkap, lalu tekan Selesai gerakan.';
    }
    if (target.isNotEmpty) {
      if (!active) {
        return 'Deteksi dimulai otomatis saat kamera siap; video tidak direkam.';
      }
      if (!handDetected) {
        return 'Tangan boleh di mana saja; pastikan telapak dan jari tidak terpotong.';
      }
      if (latestPrediction == null || latestConfidence == null) {
        return 'Tahan pose sebentar sampai prediksi muncul.';
      }
      final confidence = (latestConfidence! * 100).toStringAsFixed(1);
      if (!_predictionIsReliable) {
        return 'Keyakinan $confidence% masih di bawah 60% dan belum dihitung.';
      }
      return '$correctCount/$eventCount percobaan stabil benar | keyakinan $confidence%';
    }
    if (!active) {
      return 'Hasil tampil di akhir. Untuk J/Z, gunakan Mulai J/Z saat sesi berjalan.';
    }
    if (!handDetected) {
      return 'Boleh di bagian mana saja; pastikan telapak dan jari tidak terpotong.';
    }
    return '$eventCount huruf tersimpan. Hasil disembunyikan sampai sesi diakhiri.';
  }

  bool get _predictionIsReliable =>
      latestPrediction != null &&
      latestConfidence != null &&
      latestConfidence! >= 0.60;
}
