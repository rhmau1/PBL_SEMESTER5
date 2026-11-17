import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/sign_prediction.dart';
import 'image_preprocessor.dart';
import 'photo_recovery_preprocessor.dart';
import 'still_image_hand_detector.dart';
import 'static_image_prediction_policy.dart';

enum SignModel {
  modelC(
    id: 'camera_robust_v1',
    name: 'Model C',
    assetPath: 'assets/models/model_float16.tflite',
    inputSize: 28,
    inputChannels: 1,
  ),
  modelE(
    id: 'model_e',
    name: 'Model E',
    assetPath: 'assets/models/e/model_e_float16.tflite',
    inputSize: 96,
    inputChannels: 3,
  );

  const SignModel({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.inputSize,
    required this.inputChannels,
  });

  final String id;
  final String name;
  final String assetPath;
  final int inputSize;
  final int inputChannels;
}

class _LoadedSignModel {
  const _LoadedSignModel({
    required this.interpreter,
    required this.isolateInterpreter,
  });

  final Interpreter interpreter;
  final IsolateInterpreter isolateInterpreter;
}

class SignClassifier {
  SignClassifier._();

  static final SignClassifier instance = SignClassifier._();

  static const _labelsPath = 'assets/models/labels.json';
  // Experimental: reduces wrong accepts in the real-photo audit but rejects
  // many valid standardized inputs. Keep the established orientation default.
  static const _useOrientationEnsemble = bool.fromEnvironment(
    'STATIC_ORIENTATION_ENSEMBLE',
    defaultValue: false,
  );
  static const _landmarkReferencesPath =
      'assets/models/landmark_references.json';

  final Map<SignModel, _LoadedSignModel> _loadedModels = {};
  final Map<SignModel, Future<void>> _initializations = {};
  List<String> _labels = const [];
  Map<String, List<Offset>> _landmarkReferences = const {};
  img.Image? _lastContextInput;
  img.Image? _lastTightInput;
  SignPrediction? _lastContextPrediction;
  SignPrediction? _lastTightPrediction;
  SignPrediction? _lastMirroredContextPrediction;
  SignPrediction? _lastMirroredTightPrediction;
  SignPrediction? _lastLandmarkPrediction;
  List<Offset> _lastInputLandmarks = const [];
  bool _lastUsedPaddingRetry = false;
  SignPrediction? _lastFullImagePrediction;
  PhotoRecoveryInputs? _lastPhotoRecoveryInputs;
  SignPrediction? _lastPhotoRecoveryContextPrediction;
  SignPrediction? _lastPhotoRecoveryTightPrediction;
  SignPrediction? _lastPhotoRecoveryFullPrediction;
  bool _lastPhotoRecoveryApplied = false;

  bool get isReady => isReadyFor(SignModel.modelC);
  bool isReadyFor(SignModel model) =>
      _loadedModels.containsKey(model) && _labels.isNotEmpty;
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
  bool get lastUsedPaddingRetry => _lastUsedPaddingRetry;
  SignPrediction? get lastFullImagePrediction => _lastFullImagePrediction;
  List<int>? get lastPhotoRecoveryContextInputPng =>
      _lastPhotoRecoveryInputs == null
      ? null
      : img.encodePng(_lastPhotoRecoveryInputs!.context);
  List<int>? get lastPhotoRecoveryTightInputPng =>
      _lastPhotoRecoveryInputs == null
      ? null
      : img.encodePng(_lastPhotoRecoveryInputs!.tight);
  List<int>? get lastPhotoRecoveryFullInputPng =>
      _lastPhotoRecoveryInputs == null
      ? null
      : img.encodePng(_lastPhotoRecoveryInputs!.full);
  SignPrediction? get lastPhotoRecoveryContextPrediction =>
      _lastPhotoRecoveryContextPrediction;
  SignPrediction? get lastPhotoRecoveryTightPrediction =>
      _lastPhotoRecoveryTightPrediction;
  SignPrediction? get lastPhotoRecoveryFullPrediction =>
      _lastPhotoRecoveryFullPrediction;
  Rect? get lastPhotoRecoveryBounds =>
      _lastPhotoRecoveryInputs?.foregroundBounds;
  bool get lastPhotoRecoveryApplied => _lastPhotoRecoveryApplied;

  Future<void> initialize({SignModel model = SignModel.modelC}) {
    if (isReadyFor(model)) return Future<void>.value();
    return _initializations.putIfAbsent(model, () {
      return _load(model).catchError((Object error, StackTrace stackTrace) {
        _initializations.remove(model);
        Error.throwWithStackTrace(error, stackTrace);
      });
    });
  }

  Future<void> _load(SignModel model) async {
    if (_labels.isEmpty) {
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
    }
    final options = InterpreterOptions()..threads = 4;
    final interpreter = await Interpreter.fromAsset(
      model.assetPath,
      options: options,
    );
    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;
    if (!_sameShape(inputShape, <int>[
          1,
          model.inputSize,
          model.inputSize,
          model.inputChannels,
        ]) ||
        !_sameShape(outputShape, <int>[1, _labels.length])) {
      interpreter.close();
      throw StateError(
        'Kontrak ${model.name} tidak sesuai: input $inputShape, '
        'output $outputShape.',
      );
    }
    try {
      final isolateInterpreter = await IsolateInterpreter.create(
        address: interpreter.address,
        debugName: 'LatihIsyarat-${model.id}',
      );
      _loadedModels[model] = _LoadedSignModel(
        interpreter: interpreter,
        isolateInterpreter: isolateInterpreter,
      );
    } catch (_) {
      interpreter.close();
      rethrow;
    }
  }

  Future<SignPrediction> classifyFile(
    String path, {
    SignModel model = SignModel.modelC,
  }) async {
    _clearImageDiagnostics();
    const detector = StillImageHandDetector();
    final image = await detector.loadImage(path);
    final detection = await detector.detectWithDetails(image);
    _lastUsedPaddingRetry = detection.usedPaddingRetry;
    if (!isReadyFor(model)) await initialize(model: model);
    var prediction = await _classifyHandCrops(
      model == SignModel.modelC
          ? ImagePreprocessor.imageToGrayHandCrops(
              image,
              normalizedLandmarks: detection.landmarks,
            )
          : ImagePreprocessor.imageToRgbHandCrops(
              image,
              normalizedLandmarks: detection.landmarks,
            ),
      model,
      true,
    );
    if (model == SignModel.modelC && detection.usedPaddingRetry) {
      final full = await _classifyModelImage(
        ImagePreprocessor.toModelImage(image),
        model,
      );
      _lastFullImagePrediction = full;
      prediction = StaticImagePredictionPolicy.confirmRecoveredHand(
        _labels,
        prediction,
        full,
      );
    }
    if (model != SignModel.modelC || prediction.confidence >= 0.60) {
      return prediction;
    }
    final recovery = await compute(
      PhotoRecoveryPreprocessor.prepare,
      PhotoRecoveryRequest(image, detection.landmarks),
    );
    if (recovery == null) return prediction;
    _lastPhotoRecoveryInputs = recovery;
    final full =
        _lastFullImagePrediction ??
        await _classifyModelImage(recovery.full, model);
    final context = await _classifyModelImage(recovery.context, model);
    final tight = await _classifyModelImage(recovery.tight, model);
    _lastPhotoRecoveryFullPrediction = full;
    _lastPhotoRecoveryContextPrediction = context;
    _lastPhotoRecoveryTightPrediction = tight;
    final recovered = StaticImagePredictionPolicy.recoverUncertainPhoto(
      _labels,
      primary: prediction,
      full: full,
      context: context,
      tight: tight,
    );
    _lastPhotoRecoveryApplied = !identical(recovered, prediction);
    return recovered;
  }

  Future<SignPrediction> classifyUploadFile(
    String path, {
    SignModel model = SignModel.modelC,
  }) => classifyFile(path, model: model);

  Future<SignPrediction> classifyCameraFrame(
    CameraImage cameraImage, {
    required int rotationDegrees,
    required bool mirrorHorizontally,
    required List<Offset> normalizedLandmarks,
    SignModel model = SignModel.modelC,
  }) async {
    if (!isReadyFor(model)) await initialize(model: model);
    final crops = model == SignModel.modelC
        ? ImagePreprocessor.cameraImageToGrayCrops(
            cameraImage,
            rotationDegrees: rotationDegrees,
            mirrorHorizontally: mirrorHorizontally,
            normalizedLandmarks: normalizedLandmarks,
          )
        : ImagePreprocessor.cameraImageToRgbCrops(
            cameraImage,
            rotationDegrees: rotationDegrees,
            mirrorHorizontally: mirrorHorizontally,
            normalizedLandmarks: normalizedLandmarks,
          );
    return _classifyHandCrops(crops, model, false);
  }

  Future<SignPrediction> _classifyHandCrops(
    CameraFrameCrops crops,
    SignModel model,
    bool verifyBothCrops,
  ) async {
    _clearPhotoRecoveryDiagnostics();
    final contextInput = _toModelImage(crops.context, model);
    final contextPrediction = await _classifyModelImage(contextInput, model);
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
        model,
      );
      _lastMirroredContextPrediction = mirrored;
      context = StaticImagePredictionPolicy.averageOrientations(
        _labels,
        contextPrediction,
        mirrored,
      );
    }
    if (!verifyBothCrops && context.confidence >= 0.90) return context;

    final tightInput = _lastTightInput = _toModelImage(crops.tight, model);
    final tightPrediction = await _classifyModelImage(tightInput, model);
    _lastTightPrediction = tightPrediction;
    var tight = tightPrediction;
    if (_useOrientationEnsemble) {
      final mirrored = await _classifyModelImage(
        img.flipHorizontal(img.Image.from(_lastTightInput!)),
        model,
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
    SignModel model = SignModel.modelC,
  }) {
    if (!isReadyFor(model)) {
      throw StateError('Model belum siap.');
    }

    final modelImage = model == SignModel.modelC
        ? ImagePreprocessor.toModelImage(
            image,
            cropFraction: cropFraction,
            normalizedCrop: normalizedCrop,
          )
        : ImagePreprocessor.toModelRgbImage(
            image,
            cropFraction: cropFraction,
            normalizedCrop: normalizedCrop,
          );
    return _classifyModelImage(modelImage, model);
  }

  img.Image _toModelImage(img.Image image, SignModel model) =>
      model == SignModel.modelC
      ? ImagePreprocessor.toModelImage(image)
      : ImagePreprocessor.toModelRgbImage(image);

  Future<SignPrediction> _classifyModelImage(
    img.Image modelImage,
    SignModel model,
  ) async {
    final loadedModel = _loadedModels[model];
    if (loadedModel == null) {
      throw StateError('Model belum siap.');
    }

    final input = model == SignModel.modelC
        ? ImagePreprocessor.modelImageToInput(modelImage)
        : ImagePreprocessor.rgbImageToInput(modelImage);
    final output = <List<double>>[List<double>.filled(_labels.length, 0)];
    await loadedModel.isolateInterpreter.run(input, output);
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
    for (final model in _loadedModels.values) {
      await model.isolateInterpreter.close();
      model.interpreter.close();
    }
    _loadedModels.clear();
    _initializations.clear();
    _clearImageDiagnostics();
  }

  void _clearImageDiagnostics() {
    _clearPhotoRecoveryDiagnostics();
    _lastUsedPaddingRetry = false;
    _lastFullImagePrediction = null;
    _lastContextInput = null;
    _lastTightInput = null;
    _lastContextPrediction = null;
    _lastTightPrediction = null;
    _lastMirroredContextPrediction = null;
    _lastMirroredTightPrediction = null;
    _lastLandmarkPrediction = null;
    _lastInputLandmarks = const [];
  }

  void _clearPhotoRecoveryDiagnostics() {
    _lastPhotoRecoveryInputs = null;
    _lastPhotoRecoveryContextPrediction = null;
    _lastPhotoRecoveryTightPrediction = null;
    _lastPhotoRecoveryFullPrediction = null;
    _lastPhotoRecoveryApplied = false;
  }

  static bool _sameShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }
}
