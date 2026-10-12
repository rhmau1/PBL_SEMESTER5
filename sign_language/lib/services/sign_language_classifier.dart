import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Result from sign-language classification.
class ClassificationResult {
  final String gesture;
  final double confidence;

  const ClassificationResult({required this.gesture, required this.confidence});

  @override
  String toString() => 'ClassificationResult(gesture: $gesture, '
      'confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
}

/// Singleton classifier that wraps the TFLite sign-language model.
///
/// **Model contract** (from `model_metadata.json`):
/// - Input : `[1, 28, 28, 1]`  float32, pixel values in [0, 255]
///   (rescaling 1/255 is built into every ensemble member).
/// - Output: `[1, 24]`         float32, softmax probabilities.
class SignLanguageClassifier {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static SignLanguageClassifier? _instance;
  static SignLanguageClassifier get instance {
    _instance ??= SignLanguageClassifier._();
    return _instance!;
  }

  SignLanguageClassifier._();

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isReady = false;

  bool get isReady => _isReady;
  List<String> get labels => List.unmodifiable(_labels);

  // ── Initialization ─────────────────────────────────────────────────────────

  /// Load the model and labels from assets. Safe to call multiple times.
  Future<void> initialize() async {
    if (_isReady) return;

    // Load labels
    final labelsJson = await rootBundle.loadString('assets/models/labels.json');
    // Simple parse – just extract the "labels" array
    final labelsData = _parseLabels(labelsJson);
    _labels = labelsData;

    // Load TFLite model
    _interpreter =
        await Interpreter.fromAsset('assets/models/model_float16.tflite');

    _isReady = true;
  }

  /// Parse labels from the JSON string.
  List<String> _parseLabels(String json) {
    // Minimal JSON parsing for the labels array
    final start = json.indexOf('"labels"');
    if (start == -1) return [];

    final arrayStart = json.indexOf('[', start);
    final arrayEnd = json.indexOf(']', arrayStart);
    if (arrayStart == -1 || arrayEnd == -1) return [];

    final arrayStr = json.substring(arrayStart + 1, arrayEnd);
    final labels = <String>[];
    final regex = RegExp(r'"([^"]+)"');
    for (final match in regex.allMatches(arrayStr)) {
      labels.add(match.group(1)!);
    }
    return labels;
  }

  // ── Classification from image file ─────────────────────────────────────────

  /// Classify a sign language gesture from an image file (photo or uploaded).
  Future<ClassificationResult?> classifyImageFile(File imageFile) async {
    if (!_isReady || _interpreter == null) return null;

    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    return _classifyImage(decoded);
  }

  /// Classify from raw image bytes (e.g. from an asset picker).
  Future<ClassificationResult?> classifyImageBytes(Uint8List imageBytes) async {
    if (!_isReady || _interpreter == null) return null;

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    return _classifyImage(decoded);
  }

  // ── Classification from camera frame ───────────────────────────────────────

  /// Classify a sign language gesture from a CameraImage (live preview frame).
  /// Works on Android (YUV420) and iOS (bgra8888).
  Future<ClassificationResult?> classifyCameraImage(CameraImage cameraImage) async {
    if (!_isReady || _interpreter == null) return null;

    final grayscale = _cameraImageToGrayscale(cameraImage);
    if (grayscale == null) return null;

    return _classifyImage(grayscale);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// Convert a CameraImage to a grayscale `img.Image`.
  img.Image? _cameraImageToGrayscale(CameraImage image) {
    try {
      final int width = image.width;
      final int height = image.height;

      img.Image grayscale;

      if (Platform.isAndroid) {
        // Android: YUV420 – the Y plane is already luminance
        final yPlane = image.planes[0];
        grayscale = img.Image(width: width, height: height, numChannels: 1);
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final int index = y * yPlane.bytesPerRow + x;
            if (index < yPlane.bytes.length) {
              final lum = yPlane.bytes[index];
              grayscale.setPixelRgb(x, y, lum, lum, lum);
            }
          }
        }
      } else if (Platform.isIOS) {
        // iOS: BGRA8888
        final plane = image.planes[0];
        grayscale = img.Image(width: width, height: height, numChannels: 1);
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final int index = y * plane.bytesPerRow + x * 4;
            if (index + 2 < plane.bytes.length) {
              final b = plane.bytes[index];
              final g = plane.bytes[index + 1];
              final r = plane.bytes[index + 2];
              // Standard luminance formula
              final lum = (0.299 * r + 0.587 * g + 0.114 * b).round();
              grayscale.setPixelRgb(x, y, lum, lum, lum);
            }
          }
        }
      } else {
        return null;
      }

      return grayscale;
    } catch (_) {
      return null;
    }
  }

  /// Core classification logic: resize to 28×28 grayscale, run inference.
  ClassificationResult? _classifyImage(img.Image image) {
    try {
      // Convert to grayscale if needed
      final grayscale = img.grayscale(image);

      // Resize to 28×28
      final resized = img.copyResize(
        grayscale,
        width: 28,
        height: 28,
        interpolation: img.Interpolation.linear,
      );

      // Build input tensor [1, 28, 28, 1] with float32 values in [0, 255]
      final input = List.generate(
        1,
        (_) => List.generate(
          28,
          (y) => List.generate(
            28,
            (x) {
              final pixel = resized.getPixel(x, y);
              // Use the red channel (which equals all channels in grayscale)
              return [pixel.r.toDouble()];
            },
          ),
        ),
      );

      // Output: [1, 24]
      final output = List.generate(1, (_) => List.filled(24, 0.0));

      // Run inference
      _interpreter!.run(input, output);

      // Find the class with highest probability
      final probabilities = output[0];
      int maxIndex = 0;
      double maxProb = probabilities[0];
      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIndex = i;
        }
      }

      if (maxIndex < _labels.length) {
        return ClassificationResult(
          gesture: _labels[maxIndex],
          confidence: maxProb,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Dispose the interpreter and free resources.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isReady = false;
    _instance = null;
  }
}
