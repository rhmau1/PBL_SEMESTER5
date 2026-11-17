import 'package:flutter/services.dart';

import '../models/hand_landmark_frame.dart';

/// A separate VIDEO tracker. It never reuses the static CNN's landmarks.
abstract interface class JzHandDetector {
  Future<void> startClip();

  Future<HandLandmarkFrame> detectFrame(
    Uint8List uprightJpeg, {
    required int timestampMs,
  });

  Future<void> finishClip();

  Future<void> dispose();
}

class PlatformJzHandDetector implements JzHandDetector {
  PlatformJzHandDetector({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('latih_isyarat/dynamic_hand_landmarker');

  final MethodChannel _channel;

  @override
  Future<void> startClip() async {
    await _channel.invokeMethod<Object?>('startClip');
  }

  @override
  Future<HandLandmarkFrame> detectFrame(
    Uint8List uprightJpeg, {
    required int timestampMs,
  }) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'detectFrame',
      {'bytes': uprightJpeg, 'timestampMs': timestampMs},
    );
    if (response == null || response['timestampMs'] != timestampMs) {
      throw const FormatException('Waktu hasil MediaPipe tidak sesuai frame.');
    }
    final width = response['width'];
    final height = response['height'];
    final hands = response['hands'];
    if (width is! int || height is! int || hands is! List) {
      throw const FormatException('Hasil MediaPipe tidak dapat dibaca.');
    }
    final parsedHands = <List<HandLandmarkPoint>>[];
    for (final hand in hands) {
      if (hand is! List || hand.length != 21) {
        throw const FormatException(
          'MediaPipe harus mengirim 21 titik tangan.',
        );
      }
      final points = <HandLandmarkPoint>[];
      for (final point in hand) {
        if (point is! List ||
            point.length != 3 ||
            point.any((value) => value is! num || !value.isFinite)) {
          throw const FormatException('Koordinat MediaPipe tidak valid.');
        }
        points.add(
          HandLandmarkPoint(
            x: (point[0] as num).toDouble(),
            y: (point[1] as num).toDouble(),
            z: (point[2] as num).toDouble(),
          ),
        );
      }
      parsedHands.add(points);
    }
    return HandLandmarkFrame(
      timestampMs: timestampMs,
      width: width,
      height: height,
      hands: parsedHands,
    );
  }

  @override
  Future<void> finishClip() async {
    await _channel.invokeMethod<Object?>('finishClip');
  }

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod<Object?>('dispose');
  }
}
