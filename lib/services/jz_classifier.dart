import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/jz_prediction.dart';

/// Transport seam for tests. Production uses a dedicated TFLite isolate.
abstract interface class JzScoreRunner {
  Future<List<double>> run(List<List<double>> features);
  Future<void> close();
}

typedef JzScoreRunnerFactory = Future<JzScoreRunner> Function();

/// Independent J/Z model. It does not modify the existing static classifier.
class JzClassifier {
  JzClassifier({JzScoreRunnerFactory? scoreRunnerFactory})
    : _scoreRunnerFactory = scoreRunnerFactory ?? _TfliteJzRunner.load;

  static const modelAssetPath = 'assets/models/jz/model_float16.tflite';
  static const sequenceLength = 48;
  static const featureCount = 64;

  final JzScoreRunnerFactory _scoreRunnerFactory;
  JzScoreRunner? _runner;
  Future<void>? _initialization;
  Future<void>? _closing;
  Future<void> _inferenceTail = Future<void>.value();
  bool _closed = false;

  bool get isReady => !_closed && _runner != null;

  Future<void> initialize() {
    if (_closed) return Future<void>.error(_closedError());
    if (_runner != null) return Future<void>.value();
    return _initialization ??= _load();
  }

  Future<void> _load() async {
    try {
      final runner = await Future<JzScoreRunner>.sync(_scoreRunnerFactory);
      if (_closed) {
        await runner.close();
        throw _closedError();
      }
      _runner = runner;
    } finally {
      // A failed load can be retried while the classifier remains open.
      _initialization = null;
    }
  }

  /// Accepts already-normalized features in the bundled preprocessing contract.
  /// Calls are serialized because TFLite shares one interpreter and its buffers.
  Future<JzPrediction> classifyFeatures(List<List<double>> features) async {
    if (_closed) throw _closedError();
    final snapshot = _validatedSnapshot(features);
    await initialize();
    if (_closed) throw _closedError();
    final runner = _runner!;
    final inference = _inferenceTail.then((_) async {
      if (_closed) throw _closedError();
      return JzPrediction.fromScores(await runner.run(snapshot));
    });
    _inferenceTail = inference.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return inference;
  }

  /// Terminal and idempotent. Waits for initialization/running inference before
  /// freeing native resources. Create a new instance to begin another lifecycle.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    try {
      await _initialization;
    } catch (_) {
      // Failed initialization already closes any partially created native model.
    }
    await _inferenceTail;
    final runner = _runner;
    _runner = null;
    await runner?.close();
  }

  static StateError _closedError() => StateError('Model J/Z sudah ditutup.');

  static List<List<double>> _validatedSnapshot(List<List<double>> features) {
    if (features.length != sequenceLength) {
      throw ArgumentError('Model J/Z membutuhkan 48 sampel temporal.');
    }
    return List<List<double>>.generate(sequenceLength, (frame) {
      final values = features[frame];
      if (values.length != featureCount ||
          values.any(
            (value) => !value.isFinite || value.abs() > 3.4028234663852886e38,
          )) {
        throw ArgumentError(
          'Sampel J/Z harus berisi 64 fitur bernilai finite.',
        );
      }
      return List<double>.unmodifiable(values);
    }, growable: false);
  }
}

class _TfliteJzRunner implements JzScoreRunner {
  _TfliteJzRunner(this._interpreter, this._isolate);

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  static Future<JzScoreRunner> load() async {
    Interpreter? interpreter;
    IsolateInterpreter? isolate;
    try {
      final data = await rootBundle.load(JzClassifier.modelAssetPath);
      interpreter = Interpreter.fromBuffer(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        options: InterpreterOptions()..threads = 2,
      );
      final inputs = interpreter.getInputTensors();
      final outputs = interpreter.getOutputTensors();
      if (inputs.length != 1 ||
          outputs.length != 1 ||
          !_sameShape(inputs.single.shape, const [1, 48, 64]) ||
          !_sameShape(outputs.single.shape, const [1, 3]) ||
          inputs.single.type != TensorType.float32 ||
          outputs.single.type != TensorType.float32) {
        throw StateError('Kontrak tensor model J/Z tidak sesuai.');
      }
      isolate = await IsolateInterpreter.create(
        address: interpreter.address,
        debugName: 'LatihIsyaratJzClassifier',
      );
      return _TfliteJzRunner(interpreter, isolate);
    } catch (_) {
      await isolate?.close();
      interpreter?.close();
      rethrow;
    }
  }

  static bool _sameShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  @override
  Future<List<double>> run(List<List<double>> features) async {
    final output = <List<double>>[List<double>.filled(3, 0)];
    await _isolate.run(<List<List<double>>>[features], output);
    return output.single;
  }

  @override
  Future<void> close() async {
    try {
      await _isolate.close();
    } finally {
      _interpreter.close();
    }
  }
}
