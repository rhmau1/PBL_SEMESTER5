import 'package:flutter/material.dart';
import '../widgets/app_bottom_nav.dart';

/// Detection Page with two tabs:
/// 1. Real Time Detection – uses camera (camera section left empty, to be implemented)
/// 2. Upload Detection   – picks image from gallery (picker left empty, to be implemented)
class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Real Time Detection'),
            Tab(text: 'Upload Detection'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _RealTimeDetectionTab(),
          _UploadDetectionTab(),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 – Real Time Detection
// ---------------------------------------------------------------------------
class _RealTimeDetectionTab extends StatefulWidget {
  const _RealTimeDetectionTab();

  @override
  State<_RealTimeDetectionTab> createState() => _RealTimeDetectionTabState();
}

class _RealTimeDetectionTabState extends State<_RealTimeDetectionTab> {
  /// Simulated detection result. Will be replaced with real model output.
  final String _detectedGesture = 'M';
  final double _accuracy = 0.96;
  bool _isCameraActive = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Camera preview area ─────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              // Camera preview placeholder
              Container(
                width: double.infinity,
                color: const Color(0xFFE0E0E0),
                child: _isCameraActive
                    ? const Center(
                        // TODO: Replace with actual CameraPreview widget
                        // e.g.: CameraPreview(controller)
                        child: Text(
                          'Camera Preview\n(implement with camera package)',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Color(0xFF757575), fontSize: 14),
                        ),
                      )
                    : const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_off,
                                size: 56, color: Color(0xFFBDBDBD)),
                            SizedBox(height: 8),
                            Text(
                              'Kamera belum aktif',
                              style: TextStyle(
                                  color: Color(0xFF9E9E9E), fontSize: 14),
                            ),
                          ],
                        ),
                      ),
              ),

              // Detection result card (shown over the camera view)
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

        // ── Bottom bar: Upload button + Camera toggle ────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Upload button (placeholder – no file picker yet)
              OutlinedButton.icon(
                onPressed: () {
                  // TODO: implement file/image picker
                },
                icon: const Icon(Icons.upload_file,
                    size: 18, color: Color(0xFF2E7D32)),
                label: const Text(
                  'Upload',
                  style: TextStyle(color: Color(0xFF2E7D32)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const Spacer(),
              // Camera shutter / toggle button
              GestureDetector(
                onTap: () {
                  setState(() => _isCameraActive = !_isCameraActive);
                  // TODO: initialise camera controller here
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isCameraActive
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFEEEEEE),
                    border: Border.all(
                      color: const Color(0xFF2E7D32),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _isCameraActive ? Icons.stop : Icons.camera,
                    color: _isCameraActive ? Colors.white : const Color(0xFF2E7D32),
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

// ---------------------------------------------------------------------------
// Tab 2 – Upload Detection
// ---------------------------------------------------------------------------
class _UploadDetectionTab extends StatefulWidget {
  const _UploadDetectionTab();

  @override
  State<_UploadDetectionTab> createState() => _UploadDetectionTabState();
}

class _UploadDetectionTabState extends State<_UploadDetectionTab> {
  /// Simulated detection result. Will be replaced with real model output.
  final String _detectedGesture = 'G';
  final double _accuracy = 0.98;

  /// Holds the picked image. Null when no image is selected yet.
  // TODO: Replace with actual image file type (e.g., XFile from image_picker)
  final dynamic _pickedImage = null;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Image preview area ───────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              // Image preview placeholder
              Container(
                width: double.infinity,
                color: const Color(0xFFE0E0E0),
                child: _pickedImage == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.image_outlined,
                                size: 56, color: const Color(0xFFBDBDBD)),
                            const SizedBox(height: 8),
                            const Text(
                              'Belum ada gambar dipilih',
                              style: TextStyle(
                                  color: Color(0xFF9E9E9E), fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.upload_file, size: 18),
                              label: const Text('Pilih Gambar'),
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
                    : const Center(
                        // TODO: Replace with actual Image.file(_pickedImage.path)
                        child: Text(
                          'Gambar terpilih\n(implement with image_picker)',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Color(0xFF757575), fontSize: 14),
                        ),
                      ),
              ),

              // Detection result card
              Positioned(
                left: 16,
                right: 80,
                bottom: 16,
                child: _DetectionResultCard(
                  gesture: _detectedGesture,
                  accuracy: _accuracy,
                  showProgressBar: false,
                ),
              ),
            ],
          ),
        ),

        // ── Bottom bar: Upload button + detect button ────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.upload_file,
                    size: 18, color: Color(0xFF2E7D32)),
                label: const Text(
                  'Upload',
                  style: TextStyle(color: Color(0xFF2E7D32)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const Spacer(),
              // Detect / analyse button
              GestureDetector(
                onTap: _runDetection,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEEEEEE),
                    border: Border.all(
                      color: const Color(0xFF2E7D32),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.search,
                    color: Color(0xFF2E7D32),
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

  void _pickImage() {
    // TODO: Use image_picker package
    // final ImagePicker picker = ImagePicker();
    // final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    // if (file != null) setState(() => _pickedImage = file);
  }

  void _runDetection() {
    // TODO: Send _pickedImage to the ML model for detection
  }
}

// ---------------------------------------------------------------------------
// Shared detection result card widget
// ---------------------------------------------------------------------------
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
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF757575),
            ),
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
