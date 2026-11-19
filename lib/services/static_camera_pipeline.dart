import 'dart:collection';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '../models/sign_prediction.dart';
import 'sign_classifier.dart';

/// A hand-detector result paired with the static-analysis generation that
/// requested it. This prevents an observation queued before a J/Z gesture
/// from being treated as the first observation after that gesture.
class StaticHandObservation {
  const StaticHandObservation({required this.generation, required this.hands});

  final int generation;
  final List<Hand> hands;
}

/// Keeps the existing static classifier and detector settings in one adapter.
/// The temporal model never feeds landmarks or predictions into this pipeline.
class StaticCameraPipeline {
  HandLandmarkerPlugin? _detector;
  bool _disposed = false;
  final Queue<int> _pendingGenerations = Queue<int>();

  Future<void> initialize() async {
    await SignClassifier.instance.initialize();
    if (_disposed) return;
    _detector ??= HandLandmarkerPlugin.create(
      numHands: 1,
      minHandDetectionConfidence: 0.35,
      delegate: HandLandmarkerDelegate.cpu,
    );
  }

  Stream<List<Hand>> get hands => _detector!.landmarkStream;

  Stream<StaticHandObservation> get generationObservations =>
      hands.map((hands) {
        final generation = _pendingGenerations.isEmpty
            ? -1
            : _pendingGenerations.removeFirst();
        return StaticHandObservation(generation: generation, hands: hands);
      });

  void detectHands(CameraImage image, int rotation) =>
      _detector!.processFrame(image, rotation);

  /// Starts a detector request and records which analysis generation owns it.
  /// The original [detectHands] method remains available for existing callers
  /// and test doubles.
  void detectHandsForGeneration(
    CameraImage image,
    int rotation,
    int generation,
  ) {
    _pendingGenerations.addLast(generation);
    try {
      detectHands(image, rotation);
    } catch (_) {
      _pendingGenerations.removeLast();
      rethrow;
    }
  }

  Future<SignPrediction> classify(
    CameraImage image, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    required List<Offset> normalizedLandmarks,
  }) => SignClassifier.instance.classifyCameraFrame(
    image,
    rotationDegrees: rotationDegrees,
    mirrorHorizontally: mirrorHorizontally,
    normalizedLandmarks: normalizedLandmarks,
  );

  void dispose() {
    _disposed = true;
    _pendingGenerations.clear();
    _detector?.dispose();
    _detector = null;
  }
}
