import 'package:flutter/material.dart';

import '../models/history_item.dart';
import '../screens/camera_screen.dart';
import '../screens/upload_screen.dart';

class DetectionPage extends StatefulWidget {
  const DetectionPage({
    super.key,
    this.cameraEnabled = true,
    this.onResultSaved,
    this.onBusyChanged,
  });

  final bool cameraEnabled;
  final Future<void> Function(HistoryItem)? onResultSaved;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  int _selectedTab = 0;
  bool _busy = false;

  void _setBusy(bool value) {
    if (!mounted || value == _busy) return;
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
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
          : (selection) => setState(() => _selectedTab = selection.single),
      style: isCamera
          ? ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFF236B55)
                    : const Color(0xDD101714),
              ),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
            )
          : null,
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
          topOverlayHeight: 52,
          onResultSaved: widget.onResultSaved,
          onBusyChanged: _setBusy,
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 16,
          right: 16,
          child: Center(child: selector),
        ),
      ],
    );
  }
}
