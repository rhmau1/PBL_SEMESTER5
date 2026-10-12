import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../models/history_item.dart';
import '../providers/history_provider.dart';
import '../services/sign_language_classifier.dart';
import '../widgets/app_bottom_nav.dart';

// ---------------------------------------------------------------------------
// Global camera list – populated once in DetectionPage.initState
// ---------------------------------------------------------------------------
List<CameraDescription> _availableCameras = [];

/// Helper: save detection to history.
void _saveToHistory(WidgetRef ref, String gesture, double accuracy) {
  final now = DateTime.now();
  ref.read(historyProvider.notifier).addHistory(
    HistoryItem(
      gesture: gesture,
      accuracy: '${(accuracy * 100).toStringAsFixed(1)} %',
      date:
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      time:
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Detection Page – manages a SINGLE shared CameraController
// ═══════════════════════════════════════════════════════════════════════════════

class DetectionPage extends ConsumerStatefulWidget {
  const DetectionPage({super.key});

  @override
  ConsumerState<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends ConsumerState<DetectionPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  bool _camerasLoaded = false;
  bool _modelLoaded = false;
  bool _isDisposed = false;

  // ── Shared camera controller ─────────────────────────────────────────────
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCameras();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      await SignLanguageClassifier.instance.initialize();
      if (!_isDisposed && mounted) setState(() => _modelLoaded = true);
    } catch (e) {
      debugPrint('Failed to load model: $e');
      if (!_isDisposed && mounted) {
        _showSnack('Gagal memuat model: $e');
      }
    }
  }

  Future<void> _loadCameras() async {
    try {
      _availableCameras = await availableCameras();
    } catch (_) {
      _availableCameras = [];
    }
    if (!_isDisposed && mounted) {
      setState(() => _camerasLoaded = true);
      // Start camera for the first tab (Video)
      if (_availableCameras.isNotEmpty) {
        _initCamera(_availableCameras.first);
      }
    }
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final newIndex = _tabController.index;
      if (newIndex != _activeTabIndex) {
        if (!_isDisposed && mounted) setState(() => _activeTabIndex = newIndex);
        // Tabs 0 (Video) and 1 (Photo) need camera; tab 2 (Upload) doesn't.
        if (newIndex <= 1 && !_cameraInitialized && _availableCameras.isNotEmpty) {
          _initCamera(_cameraController?.description ?? _availableCameras.first);
        }
      }
    }
  }

  Future<void> _initCamera(CameraDescription description) async {
    // Dispose old controller
    final old = _cameraController;
    if (old != null) {
      _cameraController = null;
      if (!_isDisposed && mounted) {
        setState(() => _cameraInitialized = false);
      }
      await old.dispose();
      if (_isDisposed || !mounted) return;
    }

    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    _cameraController = controller;

    controller.addListener(() {
      if (!_isDisposed && mounted) setState(() {});
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      if (!_isDisposed && mounted) {
        _showSnack('Camera error: ${e.description}');
      }
      return;
    }

    if (!_isDisposed && mounted) setState(() => _cameraInitialized = true);
  }

  Future<void> _flipCamera() async {
    final c = _cameraController;
    if (c == null) return;
    final target = c.description.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    for (final cam in _availableCameras) {
      if (cam.lensDirection == target) {
        await _initCamera(cam);
        return;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      c.dispose();
      if (!_isDisposed && mounted) _cameraInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      if (_activeTabIndex <= 1) {
        _initCamera(c.description);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'Detection',
              style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(width: 8),
            // Model status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _modelLoaded
                    ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                    : const Color(0xFFF44336).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _modelLoaded ? Icons.check_circle : Icons.hourglass_top,
                    size: 12,
                    color: _modelLoaded
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFF44336),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _modelLoaded ? 'Model Ready' : 'Loading...',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _modelLoaded
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFF44336),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2E7D32),
          unselectedLabelColor: const Color(0xFF9E9E9E),
          indicatorColor: const Color(0xFF2E7D32),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Video'),
            Tab(text: 'Foto'),
            Tab(text: 'Upload'),
          ],
        ),
      ),
      body: _camerasLoaded
          ? TabBarView(
              controller: _tabController,
              children: [
                _VideoDetectionTab(
                  controller: _cameraController,
                  isInitialized: _cameraInitialized,
                  onFlip: _flipCamera,
                  ref: ref,
                  modelReady: _modelLoaded,
                ),
                _PhotoDetectionTab(
                  controller: _cameraController,
                  isInitialized: _cameraInitialized,
                  onFlip: _flipCamera,
                  ref: ref,
                  modelReady: _modelLoaded,
                ),
                _UploadDetectionTab(ref: ref, modelReady: _modelLoaded),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared: Aspect-ratio-correct camera preview (fills container, no squishing)
// ═══════════════════════════════════════════════════════════════════════════════

class _CameraPreviewFill extends StatelessWidget {
  final CameraController controller;

  const _CameraPreviewFill({required this.controller});

  @override
  Widget build(BuildContext context) {
    // previewSize is in landscape orientation (e.g. 1920×1080).
    // On a portrait phone the actual display ratio = height / width.
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const SizedBox.expand();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerW = constraints.maxWidth;
        final containerH = constraints.maxHeight;

        // Camera aspect ratio when displayed in portrait
        final cameraAR = previewSize.height / previewSize.width;
        final containerAR = containerW / containerH;

        // Calculate size that covers the container while keeping aspect ratio
        double previewW, previewH;
        if (cameraAR < containerAR) {
          // Container is wider → match width, height overflows
          previewW = containerW;
          previewH = containerW / cameraAR;
        } else {
          // Container is taller → match height, width overflows
          previewH = containerH;
          previewW = containerH * cameraAR;
        }

        return ClipRect(
          child: OverflowBox(
            maxWidth: previewW,
            maxHeight: previewH,
            child: SizedBox(
              width: previewW,
              height: previewH,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 1 – VIDEO Detection (Real Time with TFLite)
// ═══════════════════════════════════════════════════════════════════════════════

class _VideoDetectionTab extends StatefulWidget {
  final CameraController? controller;
  final bool isInitialized;
  final VoidCallback onFlip;
  final WidgetRef ref;
  final bool modelReady;

  const _VideoDetectionTab({
    required this.controller,
    required this.isInitialized,
    required this.onFlip,
    required this.ref,
    required this.modelReady,
  });

  @override
  State<_VideoDetectionTab> createState() => _VideoDetectionTabState();
}

class _VideoDetectionTabState extends State<_VideoDetectionTab> {
  bool _isDetecting = false;
  bool _isDisposed = false;

  // Real-time detection state
  String _detectedGesture = '';
  double _accuracy = 0.0;
  bool _showDetection = false;
  bool _isProcessingFrame = false;
  bool _isStreamActive = false;

  // Throttle: skip frames to avoid overwhelming the model
  DateTime _lastInference = DateTime.now();
  static const _inferenceInterval = Duration(milliseconds: 500);

  // Duration counter while detecting
  int _detectingSeconds = 0;
  Timer? _durationTimer;

  // Track last gesture for history dedup
  String _lastSavedGesture = '';

  @override
  void dispose() {
    _isDisposed = true;
    _durationTimer?.cancel();
    final c = widget.controller;
    if (c != null && _isStreamActive) {
      try {
        c.stopImageStream();
      } catch (_) {}
      _isStreamActive = false;
    }
    super.dispose();
  }

  // ── Detection control ──────────────────────────────────────────────────────
  Future<void> _toggleDetection() async {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;

    if (_isDetecting) {
      await _stopDetection();
    } else {
      await _startDetection();
    }
  }

  Future<void> _startDetection() async {
    final c = widget.controller;
    if (c == null || !widget.modelReady) {
      _showSnack('Model belum siap, tunggu sebentar...');
      return;
    }

    setState(() {
      _isDetecting = true;
      _detectingSeconds = 0;
      _showDetection = false;
      _lastSavedGesture = '';
    });

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isDisposed && mounted) setState(() => _detectingSeconds++);
    });

    // Start the camera image stream for real-time inference
    try {
      _isStreamActive = true;
      await c.startImageStream(_onCameraFrame);
    } catch (e) {
      if (!_isDisposed && mounted) {
        _showSnack('Gagal memulai stream kamera: $e');
        setState(() => _isDetecting = false);
      }
    }
  }

  void _onCameraFrame(CameraImage image) {
    if (_isDisposed || !_isDetecting || !mounted || _isProcessingFrame) return;

    // Throttle inference
    final now = DateTime.now();
    if (now.difference(_lastInference) < _inferenceInterval) return;
    _lastInference = now;
    _isProcessingFrame = true;

    _runInference(image);
  }

  Future<void> _runInference(CameraImage image) async {
    try {
      final result = await SignLanguageClassifier.instance
          .classifyCameraImage(image);

      if (!_isDisposed && mounted && _isDetecting && result != null) {
        setState(() {
          _detectedGesture = result.gesture;
          _accuracy = result.confidence;
          _showDetection = true;
        });

        // Save to history only when gesture changes
        if (result.gesture != _lastSavedGesture) {
          _lastSavedGesture = result.gesture;
          _saveToHistory(widget.ref, result.gesture, result.confidence);
        }
      }
    } catch (_) {
      // Silently ignore inference errors for individual frames
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _stopDetection() async {
    _durationTimer?.cancel();

    final c = widget.controller;
    if (c != null && _isStreamActive) {
      try {
        await c.stopImageStream();
      } catch (_) {}
      _isStreamActive = false;
    }

    if (!_isDisposed && mounted) {
      setState(() {
        _isDetecting = false;
        _detectingSeconds = 0;
      });
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatDuration(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final canFlip = _availableCameras.length > 1;
    final c = widget.controller;
    final initialized = widget.isInitialized && c != null && c.value.isInitialized;

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Camera preview – aspect-ratio correct, no squishing
              if (initialized)
                _CameraPreviewFill(controller: c)
              else if (_availableCameras.isEmpty)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.no_photography,
                          size: 56, color: Color(0xFFBDBDBD)),
                      SizedBox(height: 8),
                      Text('Tidak ada kamera tersedia',
                          style: TextStyle(
                              color: Color(0xFF9E9E9E), fontSize: 14)),
                    ],
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
                ),

              // Flip camera button – top left
              if (canFlip && !_isDetecting)
                Positioned(
                  top: 12,
                  left: 12,
                  child: _CircleIconButton(
                    icon: Icons.cameraswitch_outlined,
                    onTap: widget.onFlip,
                    tooltip: 'Ganti Kamera',
                  ),
                ),

              // Detecting badge – top right
              if (_isDetecting)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _PulsingDot(color: Colors.white, size: 10),
                        const SizedBox(width: 6),
                        Text(
                          'LIVE  ${_formatDuration(_detectingSeconds)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Detection result card
              if (_showDetection)
                Positioned(
                  left: 16,
                  right: 80,
                  bottom: 16,
                  child: _DetectionResultCard(
                    gesture: _detectedGesture,
                    accuracy: _accuracy,
                  ),
                ),
            ],
          ),
        ),

        // ── Bottom bar ──────────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _toggleDetection,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        _isDetecting ? Colors.red : const Color(0xFF2E7D32),
                    boxShadow: [
                      BoxShadow(
                        color: (_isDetecting
                                ? Colors.red
                                : const Color(0xFF2E7D32))
                            .withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isDetecting ? Icons.stop_rounded : Icons.videocam,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 2 – PHOTO Detection (with TFLite)
// ═══════════════════════════════════════════════════════════════════════════════

class _PhotoDetectionTab extends StatefulWidget {
  final CameraController? controller;
  final bool isInitialized;
  final VoidCallback onFlip;
  final WidgetRef ref;
  final bool modelReady;

  const _PhotoDetectionTab({
    required this.controller,
    required this.isInitialized,
    required this.onFlip,
    required this.ref,
    required this.modelReady,
  });

  @override
  State<_PhotoDetectionTab> createState() => _PhotoDetectionTabState();
}

class _PhotoDetectionTabState extends State<_PhotoDetectionTab> {
  // Captured photo
  File? _capturedPhoto;
  bool _wasFrontCamera = false;
  bool _isDetecting = false;

  // Detection result
  String? _detectedGesture;
  double? _accuracy;

  // ── Take photo ─────────────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;

    try {
      final isFront =
          c.description.lensDirection == CameraLensDirection.front;
      final xFile = await c.takePicture();
      if (!mounted) return;
      setState(() {
        _capturedPhoto = File(xFile.path);
        _wasFrontCamera = isFront;
        _detectedGesture = null;
        _accuracy = null;
      });
    } on CameraException catch (e) {
      if (mounted) _showSnack('Gagal mengambil foto: ${e.description}');
    }
  }

  // ── Run detection on captured photo using real model ────────────────────
  Future<void> _runDetection() async {
    if (_capturedPhoto == null) {
      _showSnack('Ambil foto terlebih dahulu');
      return;
    }

    if (!widget.modelReady) {
      _showSnack('Model belum siap, tunggu sebentar...');
      return;
    }

    setState(() => _isDetecting = true);

    try {
      final result = await SignLanguageClassifier.instance
          .classifyImageFile(_capturedPhoto!);

      if (!mounted) return;

      if (result != null) {
        setState(() {
          _detectedGesture = result.gesture;
          _accuracy = result.confidence;
          _isDetecting = false;
        });

        _saveToHistory(widget.ref, result.gesture, result.confidence);
      } else {
        setState(() => _isDetecting = false);
        _showSnack('Gagal mendeteksi gesture. Coba ambil foto lebih jelas.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDetecting = false);
        _showSnack('Error saat deteksi: $e');
      }
    }
  }

  // ── Reset to camera ────────────────────────────────────────────────────
  void _retake() {
    setState(() {
      _capturedPhoto = null;
      _wasFrontCamera = false;
      _detectedGesture = null;
      _accuracy = null;
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final canFlip = _availableCameras.length > 1;
    final hasPhoto = _capturedPhoto != null;
    final hasResult = _detectedGesture != null && _accuracy != null;
    final c = widget.controller;
    final initialized = widget.isInitialized && c != null && c.value.isInitialized;

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Show captured photo or live preview
              // If taken with front camera, flip horizontally so it
              // matches the mirror-like preview the user saw.
              if (hasPhoto)
                Transform(
                  alignment: Alignment.center,
                  transform: _wasFrontCamera
                      ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
                      : Matrix4.identity(),
                  child: Image.file(
                    _capturedPhoto!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                )
              else if (initialized)
                _CameraPreviewFill(controller: c)
              else if (_availableCameras.isEmpty)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.no_photography,
                          size: 56, color: Color(0xFFBDBDBD)),
                      SizedBox(height: 8),
                      Text('Tidak ada kamera tersedia',
                          style: TextStyle(
                              color: Color(0xFF9E9E9E), fontSize: 14)),
                    ],
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
                ),

              // Flip camera button – top left (only when no photo captured)
              if (canFlip && !hasPhoto)
                Positioned(
                  top: 12,
                  left: 12,
                  child: _CircleIconButton(
                    icon: Icons.cameraswitch_outlined,
                    onTap: widget.onFlip,
                    tooltip: 'Ganti Kamera',
                  ),
                ),

              // Loading spinner while detecting
              if (_isDetecting)
                Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF2E7D32)),
                        SizedBox(height: 12),
                        Text(
                          'Mendeteksi gesture...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Detection result card
              if (hasResult)
                Positioned(
                  left: 16,
                  right: 80,
                  bottom: 16,
                  child: _DetectionResultCard(
                    gesture: _detectedGesture!,
                    accuracy: _accuracy!,
                    showProgressBar: false,
                  ),
                ),
            ],
          ),
        ),

        // ── Bottom bar ──────────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (hasPhoto) ...[
                // Retake button
                OutlinedButton.icon(
                  onPressed: _retake,
                  icon: const Icon(Icons.refresh,
                      size: 18, color: Color(0xFF2E7D32)),
                  label: const Text('Ulangi',
                      style: TextStyle(color: Color(0xFF2E7D32))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
                // Detect button
                ElevatedButton.icon(
                  onPressed: _isDetecting ? null : _runDetection,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(_isDetecting ? 'Mendeteksi...' : 'Deteksi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                ),
              ] else ...[
                // Capture photo button
                GestureDetector(
                  onTap: _takePhoto,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2E7D32),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF2E7D32).withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt,
                        color: Colors.white, size: 32),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab 3 – UPLOAD Detection (WeChat Assets Picker + TFLite)
// ═══════════════════════════════════════════════════════════════════════════════

class _UploadDetectionTab extends StatefulWidget {
  final WidgetRef ref;
  final bool modelReady;
  const _UploadDetectionTab({required this.ref, required this.modelReady});

  @override
  State<_UploadDetectionTab> createState() => _UploadDetectionTabState();
}

class _UploadDetectionTabState extends State<_UploadDetectionTab> {
  AssetEntity? _pickedAsset;
  bool _isLoading = false;
  bool _isDetecting = false;

  // Detection result – null until user clicks Detect
  String? _detectedGesture;
  double? _accuracy;

  Future<void> _pickAsset() async {
    setState(() => _isLoading = true);
    try {
      final List<AssetEntity>? assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          maxAssets: 1,
          requestType: RequestType.common,
          textDelegate: EnglishAssetPickerTextDelegate(),
        ),
      );
      if (!mounted) return;
      if (assets != null && assets.isNotEmpty) {
        setState(() {
          _pickedAsset = assets.first;
          _detectedGesture = null;
          _accuracy = null;
        });
      }
    } catch (e) {
      if (mounted) _showSnack('Gagal memilih file: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runDetection() async {
    if (_pickedAsset == null) {
      _showSnack('Pilih gambar atau video terlebih dahulu');
      return;
    }

    if (!widget.modelReady) {
      _showSnack('Model belum siap, tunggu sebentar...');
      return;
    }

    setState(() => _isDetecting = true);

    try {
      // Get the file from the picked asset
      final file = await _pickedAsset!.file;
      if (file == null) {
        if (mounted) {
          setState(() => _isDetecting = false);
          _showSnack('Gagal membaca file');
        }
        return;
      }

      final result = await SignLanguageClassifier.instance
          .classifyImageFile(file);

      if (!mounted) return;

      if (result != null) {
        setState(() {
          _detectedGesture = result.gesture;
          _accuracy = result.confidence;
          _isDetecting = false;
        });

        _saveToHistory(widget.ref, result.gesture, result.confidence);
      } else {
        setState(() => _isDetecting = false);
        _showSnack('Gagal mendeteksi gesture. Coba gambar yang lebih jelas.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDetecting = false);
        _showSnack('Error saat deteksi: $e');
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _pickedAsset = null;
      _detectedGesture = null;
      _accuracy = null;
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final hasAsset = _pickedAsset != null;
    final hasResult = _detectedGesture != null && _accuracy != null;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFFE0E0E0),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF2E7D32)),
                      )
                    : !hasAsset
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.image_outlined,
                                    size: 56, color: Color(0xFFBDBDBD)),
                                const SizedBox(height: 8),
                                const Text(
                                  'Belum ada file dipilih',
                                  style: TextStyle(
                                      color: Color(0xFF9E9E9E), fontSize: 14),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _pickAsset,
                                  icon: const Icon(Icons.upload_file,
                                      size: 18),
                                  label: const Text('Pilih File'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2E7D32),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Image(
                            image: AssetEntityImageProvider(
                              _pickedAsset!,
                              isOriginal: false,
                            ),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, _, _) => const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.videocam,
                                      size: 56, color: Color(0xFFBDBDBD)),
                                  SizedBox(height: 8),
                                  Text('Preview video tidak tersedia',
                                      style: TextStyle(
                                          color: Color(0xFF9E9E9E),
                                          fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
              ),

              if (_isDetecting)
                Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF2E7D32)),
                        SizedBox(height: 12),
                        Text(
                          'Mendeteksi gesture...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (hasResult)
                Positioned(
                  left: 16,
                  right: 80,
                  bottom: 16,
                  child: _DetectionResultCard(
                    gesture: _detectedGesture!,
                    accuracy: _accuracy!,
                    showProgressBar: false,
                  ),
                ),
            ],
          ),
        ),

        // ── Bottom bar ──────────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickAsset,
                icon: const Icon(Icons.upload_file,
                    size: 18, color: Color(0xFF2E7D32)),
                label: Text(
                  hasAsset ? 'Ganti File' : 'Upload',
                  style: const TextStyle(color: Color(0xFF2E7D32)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
              if (hasAsset) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.close, color: Color(0xFF9E9E9E)),
                  tooltip: 'Hapus pilihan',
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: _isDetecting ? null : _runDetection,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasAsset
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFEEEEEE),
                    border: Border.all(
                      color: const Color(0xFF2E7D32),
                      width: 2,
                    ),
                  ),
                  child: _isDetecting
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          Icons.search,
                          color: hasAsset
                              ? Colors.white
                              : const Color(0xFF2E7D32),
                          size: 28,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Pulsing dot indicator for live detection mode.
class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const _PulsingDot({required this.color, required this.size});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, _) => Opacity(
        opacity: _animation.value,
        child: Icon(Icons.circle, color: widget.color, size: widget.size),
      ),
    );
  }
}

class _DetectionResultCard extends StatelessWidget {
  final String gesture;
  final double accuracy;
  final bool showProgressBar;

  const _DetectionResultCard({
    required this.gesture,
    required this.accuracy,
    this.showProgressBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Gesture : $gesture',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Accuracy ${(accuracy * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
          ),
          if (showProgressBar) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: accuracy,
                minHeight: 10,
                backgroundColor: const Color(0xFFE0E0E0),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF4CAF50),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
