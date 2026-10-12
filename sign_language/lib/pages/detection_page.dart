import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../models/history_item.dart';
import '../providers/history_provider.dart';
import '../widgets/app_bottom_nav.dart';

// ---------------------------------------------------------------------------
// Global camera list – populated once in DetectionPage.initState
// ---------------------------------------------------------------------------
List<CameraDescription> _availableCameras = [];

// Simulated detection results (shared by all tabs)
final List<Map<String, dynamic>> _simulatedResults = [
  {'gesture': 'A', 'accuracy': 0.92},
  {'gesture': 'B', 'accuracy': 0.87},
  {'gesture': 'M', 'accuracy': 0.96},
  {'gesture': 'G', 'accuracy': 0.94},
  {'gesture': 'L', 'accuracy': 0.89},
  {'gesture': 'C', 'accuracy': 0.91},
];

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
  }

  Future<void> _loadCameras() async {
    try {
      _availableCameras = await availableCameras();
    } catch (_) {
      _availableCameras = [];
    }
    if (mounted) {
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
        setState(() => _activeTabIndex = newIndex);
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
      setState(() => _cameraInitialized = false);
      await old.dispose();
    }

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _cameraController = controller;

    controller.addListener(() {
      if (mounted) setState(() {});
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      _showSnack('Camera error: ${e.description}');
      return;
    }

    if (mounted) setState(() => _cameraInitialized = true);
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
      _cameraInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      if (_activeTabIndex <= 1) {
        _initCamera(c.description);
      }
    }
  }

  @override
  void dispose() {
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
        title: const Text(
          'Detection',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
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
                ),
                _PhotoDetectionTab(
                  controller: _cameraController,
                  isInitialized: _cameraInitialized,
                  onFlip: _flipCamera,
                  ref: ref,
                ),
                _UploadDetectionTab(ref: ref),
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
// Tab 1 – VIDEO Detection (Real Time)
// ═══════════════════════════════════════════════════════════════════════════════

class _VideoDetectionTab extends StatefulWidget {
  final CameraController? controller;
  final bool isInitialized;
  final VoidCallback onFlip;
  final WidgetRef ref;

  const _VideoDetectionTab({
    required this.controller,
    required this.isInitialized,
    required this.onFlip,
    required this.ref,
  });

  @override
  State<_VideoDetectionTab> createState() => _VideoDetectionTabState();
}

class _VideoDetectionTabState extends State<_VideoDetectionTab> {
  bool _isRecording = false;

  // Simulated real-time detection
  Timer? _detectionTimer;
  String _detectedGesture = '';
  double _accuracy = 0.0;
  bool _showDetection = false;

  // Duration counter while recording
  int _recordingSeconds = 0;
  Timer? _durationTimer;
  int _resultIndex = 0;

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  // ── Recording control ──────────────────────────────────────────────────────
  Future<void> _toggleRecording() async {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;

    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final c = widget.controller!;
    try {
      await c.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
        _showDetection = false;
      });

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingSeconds++);
      });

      _detectionTimer = Timer(const Duration(seconds: 2), () {
        _scheduleDetection();
      });
    } on CameraException catch (e) {
      _showSnack('Recording error: ${e.description}');
    }
  }

  void _scheduleDetection() {
    if (!_isRecording || !mounted) return;
    final result = _simulatedResults[_resultIndex % _simulatedResults.length];
    final gesture = result['gesture'] as String;
    final accuracy = result['accuracy'] as double;
    setState(() {
      _detectedGesture = gesture;
      _accuracy = accuracy;
      _showDetection = true;
      _resultIndex++;
    });

    _saveToHistory(widget.ref, gesture, accuracy);
    _detectionTimer = Timer(const Duration(seconds: 2), _scheduleDetection);
  }

  Future<void> _stopRecording() async {
    _detectionTimer?.cancel();
    _durationTimer?.cancel();

    final c = widget.controller;
    if (c != null) {
      try {
        await c.stopVideoRecording();
      } on CameraException catch (e) {
        _showSnack('Stop error: ${e.description}');
      }
    }

    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
    });
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
              if (canFlip && !_isRecording)
                Positioned(
                  top: 12,
                  left: 12,
                  child: _CircleIconButton(
                    icon: Icons.cameraswitch_outlined,
                    onTap: widget.onFlip,
                    tooltip: 'Ganti Kamera',
                  ),
                ),

              // Recording badge – top right
              if (_isRecording)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle,
                            color: Colors.white, size: 10),
                        const SizedBox(width: 6),
                        Text(
                          'REC  ${_formatDuration(_recordingSeconds)}',
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
                onTap: _toggleRecording,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        _isRecording ? Colors.red : const Color(0xFF2E7D32),
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording
                                ? Colors.red
                                : const Color(0xFF2E7D32))
                            .withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop_rounded : Icons.videocam,
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
// Tab 2 – PHOTO Detection
// ═══════════════════════════════════════════════════════════════════════════════

class _PhotoDetectionTab extends StatefulWidget {
  final CameraController? controller;
  final bool isInitialized;
  final VoidCallback onFlip;
  final WidgetRef ref;

  const _PhotoDetectionTab({
    required this.controller,
    required this.isInitialized,
    required this.onFlip,
    required this.ref,
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
  int _resultIndex = 0;

  // ── Take photo ─────────────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;

    try {
      final isFront =
          c.description.lensDirection == CameraLensDirection.front;
      final xFile = await c.takePicture();
      setState(() {
        _capturedPhoto = File(xFile.path);
        _wasFrontCamera = isFront;
        _detectedGesture = null;
        _accuracy = null;
      });
    } on CameraException catch (e) {
      _showSnack('Gagal mengambil foto: ${e.description}');
    }
  }

  // ── Run detection on captured photo ────────────────────────────────────
  Future<void> _runDetection() async {
    if (_capturedPhoto == null) {
      _showSnack('Ambil foto terlebih dahulu');
      return;
    }

    setState(() => _isDetecting = true);

    // Simulate ML inference delay
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    final result = _simulatedResults[_resultIndex % _simulatedResults.length];
    final gesture = result['gesture'] as String;
    final accuracy = result['accuracy'] as double;

    setState(() {
      _detectedGesture = gesture;
      _accuracy = accuracy;
      _isDetecting = false;
      _resultIndex++;
    });

    _saveToHistory(widget.ref, gesture, accuracy);
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
                    child:
                        CircularProgressIndicator(color: Color(0xFF2E7D32)),
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
// Tab 3 – UPLOAD Detection (WeChat Assets Picker)
// ═══════════════════════════════════════════════════════════════════════════════

class _UploadDetectionTab extends StatefulWidget {
  final WidgetRef ref;
  const _UploadDetectionTab({required this.ref});

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
  int _resultIndex = 0;

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
      if (assets != null && assets.isNotEmpty) {
        setState(() {
          _pickedAsset = assets.first;
          _detectedGesture = null;
          _accuracy = null;
        });
      }
    } catch (e) {
      _showSnack('Gagal memilih file: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runDetection() async {
    if (_pickedAsset == null) {
      _showSnack('Pilih gambar atau video terlebih dahulu');
      return;
    }

    setState(() => _isDetecting = true);

    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;

    final result = _simulatedResults[_resultIndex % _simulatedResults.length];
    final gesture = result['gesture'] as String;
    final accuracy = result['accuracy'] as double;

    setState(() {
      _detectedGesture = gesture;
      _accuracy = accuracy;
      _isDetecting = false;
      _resultIndex++;
    });

    _saveToHistory(widget.ref, gesture, accuracy);
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
                    child:
                        CircularProgressIndicator(color: Color(0xFF2E7D32)),
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
            'Accuracy ${(accuracy * 100).toStringAsFixed(0)}%',
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
