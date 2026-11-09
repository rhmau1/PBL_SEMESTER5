import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/sign_prediction.dart';
import 'image_preprocessor.dart';
import 'still_image_hand_detector.dart';
import 'static_image_prediction_policy.dart';

class SignClassifier {
  SignClassifier._();

  static final SignClassifier instance = SignClassifier._();

  static const _modelPath = 'assets/models/model_float16.tflite';
  static const _labelsPath = 'assets/models/labels.json';
  // Experimental: reduces wrong accepts in the real-photo audit but rejects
  // many valid standardized inputs. Keep the established orientation default.
  static const _useOrientationEnsemble = bool.fromEnvironment(
    'STATIC_ORIENTATION_ENSEMBLE',
    defaultValue: false,
  );
  static const _landmarkReferencesPath =
      'assets/models/landmark_references.json';

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  List<String> _labels = const [];
  Map<String, List<Offset>> _landmarkReferences = const {};
  Future<void>? _initialization;
  img.Image? _lastContextInput;
  img.Image? _lastTightInput;
  SignPrediction? _lastContextPrediction;
  SignPrediction? _lastTightPrediction;
  SignPrediction? _lastMirroredContextPrediction;
  SignPrediction? _lastMirroredTightPrediction;
  SignPrediction? _lastLandmarkPrediction;
  List<Offset> _lastInputLandmarks = const [];

  bool get isReady =>
      _interpreter != null && _isolateInterpreter != null && _labels.isNotEmpty;
  List<String> get labels => List.unmodifiable(_labels);
  List<int>? get lastContextInputPng =>
      _lastContextInput == null ? null : img.encodePng(_lastContextInput!);
  List<int>? get lastTightInputPng =>
      _lastTightInput == null ? null : img.encodePng(_lastTightInput!);
  SignPrediction? get lastContextPrediction => _lastContextPrediction;
  SignPrediction? get lastTightPrediction => _lastTightPrediction;
  SignPrediction? get lastMirroredContextPrediction =>
      _lastMirroredContextPrediction;
  SignPrediction? get lastMirroredTightPrediction =>
      _lastMirroredTightPrediction;
  SignPrediction? get lastLandmarkPrediction => _lastLandmarkPrediction;
  List<Offset> get lastInputLandmarks => _lastInputLandmarks;
  bool get usesOrientationEnsemble => _useOrientationEnsemble;

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    final labelsJson = jsonDecode(await rootBundle.loadString(_labelsPath));
    _labels = List<String>.from(labelsJson['labels'] as List<dynamic>);
    final referencesJson = jsonDecode(
      await rootBundle.loadString(_landmarkReferencesPath),
    ) as Map<String, dynamic>;
    final references = referencesJson['labels'] as Map<String, dynamic>;
    _landmarkReferences = Map<String, List<Offset>>.unmodifiable(
      references.map(
        (label, value) => MapEntry(
          label,
          (value as List<dynamic>)
              .map((point) {
                final coordinates = point as List<dynamic>;
                return Offset(
                  (coordinates[0] as num).toDouble(),
                  (coordinates[1] as num).toDouble(),
                );
              })
              .toList(growable: false),
        ),
      ),
    );

    final options = InterpreterOptions()..threads = 4;
    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

    final inputShape = _interpreter!.getInputTensor(0).shape;
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    if (!_sameShape(inputShape, const [1, 28, 28, 1]) ||
        !_sameShape(outputShape, <int>[1, _labels.length])) {
      _interpreter!.close();
      _interpreter = null;
      throw StateError(
        'Kontrak model tidak sesuai: input $inputShape, output $outputShape.',
      );
    }
    _isolateInterpreter = await IsolateInterpreter.create(
      address: _interpreter!.address,
      debugName: 'LatihIsyaratClassifier',
    );
  }

  Future<SignPrediction> classifyFile(String path) async {
    const detector = StillImageHandDetector();
    final image = await detector.loadImage(path);
    final landmarks = await detector.detect(image);
    if (!isReady) await initialize();
    return _classifyHandCrops(
      ImagePreprocessor.imageToGrayHandCrops(
        image,
        normalizedLandmarks: landmarks,
      ),
    );
  }

  Future<SignPrediction> classifyUploadFile(String path) => classifyFile(path);

  Future<SignPrediction> classifyCameraFrame(
    CameraImage cameraImage, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    required List<Offset> normalizedLandmarks,
  }) async {
    if (!isReady) await initialize();
    final crops = ImagePreprocessor.cameraImageToGrayCrops(
      cameraImage,
      rotationDegrees: rotationDegrees,
      mirrorHorizontally: mirrorHorizontally,
      normalizedLandmarks: normalizedLandmarks,
    );
    return _classifyHandCrops(crops);
  }

  Future<SignPrediction> _classifyHandCrops(CameraFrameCrops crops) async {
    final contextInput = ImagePreprocessor.toModelImage(crops.context);
    final contextPrediction = await _classifyModelImage(contextInput);
    final landmarkPrediction = _classifyLandmarks(crops.orientedLandmarks);
    _lastContextInput = contextInput;
    _lastTightInput = null;
    _lastContextPrediction = contextPrediction;
    _lastTightPrediction = null;
    _lastMirroredContextPrediction = null;
    _lastMirroredTightPrediction = null;
    _lastLandmarkPrediction = landmarkPrediction;
    _lastInputLandmarks = List<Offset>.unmodifiable(crops.orientedLandmarks);
    var context = contextPrediction;
    if (_useOrientationEnsemble) {
      final mirrored = await _classifyModelImage(
        img.flipHorizontal(img.Image.from(contextInput)),
      );
      _lastMirroredContextPrediction = mirrored;
      context = StaticImagePredictionPolicy.averageOrientations(
        _labels,
        contextPrediction,
        mirrored,
      );
    }
    if (context.confidence >= 0.90) return context;

    final tightPrediction = await _classifyModelImage(
      _lastTightInput = ImagePreprocessor.toModelImage(crops.tight),
    );
    _lastTightPrediction = tightPrediction;
    var tight = tightPrediction;
    if (_useOrientationEnsemble) {
      final mirrored = await _classifyModelImage(
        img.flipHorizontal(img.Image.from(_lastTightInput!)),
      );
      _lastMirroredTightPrediction = mirrored;
      tight = StaticImagePredictionPolicy.averageOrientations(
        _labels,
        tightPrediction,
        mirrored,
      );
    }
    return StaticImagePredictionPolicy.combineCrops(_labels, context, tight);
  }

  Future<SignPrediction> classifyImage(
    img.Image image, {
    double cropFraction = 1,
    Rect? normalizedCrop,
  }) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('Model belum siap.');
    }

    final modelImage = ImagePreprocessor.toModelImage(
      image,
      cropFraction: cropFraction,
      normalizedCrop: normalizedCrop,
    );
    return _classifyModelImage(modelImage);
  }

  Future<SignPrediction> _classifyModelImage(img.Image modelImage) async {
    final isolateInterpreter = _isolateInterpreter;
    if (isolateInterpreter == null) {
      throw StateError('Model belum siap.');
    }

    final input = ImagePreprocessor.modelImageToInput(modelImage);
    final output = <List<double>>[List<double>.filled(_labels.length, 0)];
    await isolateInterpreter.run(input, output);
    return _predictionFromScores(List<double>.from(output.first));
  }

  SignPrediction _predictionFromScores(List<double> scores) {
    return StaticImagePredictionPolicy.fromScores(_labels, scores);
  }

  SignPrediction? _classifyLandmarks(List<Offset> landmarks) {
    if (landmarks.length != 21 || _landmarkReferences.isEmpty) return null;
    final feature = _normalizeLandmarks(landmarks);
    final distances = <double>[];
    for (final label in _labels) {
      final reference = _landmarkReferences[label];
      if (reference == null || reference.length != 21) return null;
      final normal = _normalizeLandmarks(reference);
      final mirrored = _normalizeLandmarks(
        reference
            .map((point) => Offset(1 - point.dx, point.dy))
            .toList(growable: false),
      );
      distances.add(
        math.min(
          _meanSquaredDistance(feature, normal),
          _meanSquaredDistance(feature, mirrored),
        ),
      );
    }

    final minimumDistance = distances.reduce(math.min);
    final weights = distances
        .map((distance) => math.exp(-(distance - minimumDistance) / 0.06))
        .toList(growable: false);
    final total = weights.fold<double>(0, (sum, value) => sum + value);
    if (!total.isFinite || total <= 0) return null;
    return _predictionFromScores(
      weights.map((weight) => weight / total).toList(growable: false),
    );
  }

  static List<double> _normalizeLandmarks(List<Offset> landmarks) {
    final wrist = landmarks[0];
    final scale = (landmarks[9] - wrist).distance;
    if (scale <= 0.000001) return List<double>.filled(42, 0);
    return landmarks
        .expand(
          (point) => <double>[
            (point.dx - wrist.dx) / scale,
            (point.dy - wrist.dy) / scale,
          ],
        )
        .toList(growable: false);
  }

  static double _meanSquaredDistance(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var index = 0; index < a.length; index++) {
      final difference = a[index] - b[index];
      sum += difference * difference;
    }
    return sum / a.length;
  }

  Future<void> close() async {
    await _isolateInterpreter?.close();
    _isolateInterpreter = null;
    _interpreter?.close();
    _interpreter = null;
    _initialization = null;
    _lastContextInput = null;
    _lastTightInput = null;
    _lastContextPrediction = null;
    _lastTightPrediction = null;
    _lastMirroredContextPrediction = null;
    _lastMirroredTightPrediction = null;
    _lastLandmarkPrediction = null;
    _lastInputLandmarks = const [];
  }

  static bool _sameShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }
}
