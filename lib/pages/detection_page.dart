import 'package:flutter/material.dart';

import '../models/history_item.dart';
import '../screens/camera_screen.dart';
import '../screens/upload_screen.dart';

/// Vertical gap between the status bar and the detection selector overlay.
const double detectionOverlayGap = 8;

/// Height reserved for the detection selector overlay inside the camera view.
const double detectionOverlayHeight = 52;

class DetectionPage extends StatefulWidget {
  const DetectionPage({
    super.key,
    this.cameraEnabled = true,
    this.onResultSaved,
    this.onBusyChanged,
    this.onCameraActiveChanged,
  });

  final bool cameraEnabled;
  final Future<void> Function(HistoryItem)? onResultSaved;
  final ValueChanged<bool>? onBusyChanged;
  final ValueChanged<bool>? onCameraActiveChanged;

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  // Warna hijau utama yang sama persis dengan HomePage
  static const Color _homeGreen = Color(0xFF2E7D32);
  static const Color _homeLightGreen = Color(0xFFE8F5E9);

  int _selectedTab = 0;
  bool _busy = false;

  void _setBusy(bool value) {
    if (!mounted || value == _busy) return;
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
  }

  void _setTab(int tab) {
    setState(() => _selectedTab = tab);
    widget.onCameraActiveChanged?.call(tab != 2);
  }

  @override
  Widget build(BuildContext context) {
    final isCamera = _selectedTab != 2;
    final selector = SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 0,
          icon: Icon(Icons.videocam_outlined),
          label: Text('Video'),
        ),
        ButtonSegment(
          value: 1,
          icon: Icon(Icons.camera_alt_outlined),
          label: Text('Foto'),
        ),
        ButtonSegment(
          value: 2,
          icon: Icon(Icons.photo_library_outlined),
          label: Text('Upload'),
        ),
      ],
      selected: {_selectedTab},
      onSelectionChanged: _busy
          ? null
          : (selection) => _setTab(selection.single),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _homeGreen;
          }
          return isCamera ? const Color(0xDD101714) : Colors.white;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return isCamera ? Colors.white : _homeGreen;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(color: isCamera ? Colors.white24 : _homeLightGreen),
        ),
      ),
    );

    if (!isCamera) {
      return SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: selector,
            ),
            Expanded(
              child: UploadScreen(
                onResultSaved: widget.onResultSaved,
                onBusyChanged: _setBusy,
              ),
            ),
          ],
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraScreen(
          // Keep one lifecycle queue while switching between camera modes.
          key: const ValueKey('detection-camera'),
          cameraEnabled: widget.cameraEnabled,
          photoMode: _selectedTab == 1,
          topOverlayHeight: detectionOverlayHeight,
          onResultSaved: widget.onResultSaved,
          onBusyChanged: _setBusy,
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + detectionOverlayGap,
          left: 16,
          right: 16,
          child: Center(child: selector),
        ),
      ],
    );
  }
}
