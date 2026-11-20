import 'dart:typed_data';

import '../models/sign_prediction.dart';
import 'still_image_hand_detector.dart';
import 'svm_hog_classifier.dart';

enum SignModel {
  svmHog(id: 'svm_hog', name: 'SVM Hybrid (HOG+Contour+MediaPipe)');

  const SignModel({required this.id, required this.name});

  final String id;
  final String name;
}

class SignClassifier {
  SignClassifier._();

  static final SignClassifier instance = SignClassifier._();
  final _backend = SvmHogClassifier.instance;
  final _stillDetector = const StillImageHandDetector();

  Future<void> initialize({SignModel model = SignModel.svmHog}) =>
      _backend.initialize();

  Future<SignPrediction> classifyFile(
    String path, {
    SignModel model = SignModel.svmHog,
  }) async {
    try {
      final image = await _stillDetector.loadImage(path);
      final landmarks = await _stillDetector.detect(image);
      final pts = landmarks
          .map((p) => (x: p.dx, y: p.dy))
          .toList(growable: false);
      return _adapt(await _backend.classifyFileWithLandmarks(path, pts));
    } on HandImageException {
      return _adapt(await _backend.classifyFile(path));
    }
  }

  Future<SignPrediction> classifyUploadFile(
    String path, {
    SignModel model = SignModel.svmHog,
  }) => classifyFile(path, model: model);

  Future<SignPrediction?> classifyLumaWithLandmarks({
    required Uint8List bytes,
    required int width,
    required int height,
    required int stride,
    required int pixelStride,
    required int rotation,
    required List<({double x, double y})> landmarks,
  }) async {
    final result = await _backend.classifyLumaWithLandmarks(
      bytes: bytes,
      width: width,
      height: height,
      stride: stride,
      pixelStride: pixelStride,
      rotation: rotation,
      landmarks: landmarks,
    );
    return result == null ? null : _adapt(result);
  }

  Future<SignPrediction?> classifyLuma({
    required Uint8List bytes,
    required int width,
    required int height,
    required int stride,
    required int pixelStride,
    required int rotation,
  }) async {
    final result = await _backend.classifyLuma(
      bytes: bytes,
      width: width,
      height: height,
      stride: stride,
      pixelStride: pixelStride,
      rotation: rotation,
    );
    return result == null ? null : _adapt(result);
  }

  SignPrediction _adapt(SvmHogPrediction result) => SignPrediction(
    label: result.label,
    confidence: null,
    scores: result.scores,
    agreement: result.accepted,
  );
}