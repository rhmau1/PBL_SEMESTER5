import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

import '../models/sign_prediction.dart';
import 'sign_classifier.dart';

/// Keeps the existing static classifier and detector settings in one adapter.
/// The temporal model never feeds landmarks or predictions into this pipeline.
class StaticCameraPipeline {
  HandLandmarkerPlugin? _detector;
  bool _disposed = false;

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

  void detectHands(CameraImage image, int rotation) =>
      _detector!.processFrame(image, rotation);

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
    _detector?.dispose();
    _detector = null;
  }
}
