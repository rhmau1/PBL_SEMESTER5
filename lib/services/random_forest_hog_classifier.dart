import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';

import 'hog_image_input.dart';
import 'random_forest_hog_model.dart';

class RandomForestHogPrediction {
  const RandomForestHogPrediction({
    required this.label,
    required this.scores,
    required this.accepted,
  });

  final String label;
  final List<double> scores;
  final bool accepted;
}

class RandomForestHogClassifier {
  RandomForestHogClassifier._();

  static final RandomForestHogClassifier instance =
      RandomForestHogClassifier._();
  static const modelId = 'random_forest_hog';
  Future<({Isolate isolate, SendPort port})>? _worker;

  Future<void> initialize() async {
    await _getWorker();
  }

  Future<({Isolate isolate, SendPort port})> _getWorker() async {
    final pending = _worker ??= _startWorker();
    try {
      return await pending;
    } catch (_) {
      if (identical(pending, _worker)) _worker = null;
      rethrow;
    }
  }

  Future<({Isolate isolate, SendPort port})> _startWorker() async {
    final replies = ReceivePort();
    Isolate? isolate;
    try {
      final data = await rootBundle.load(
        'assets/models/random_forest_hog.bin.gz',
      );
      isolate = await Isolate.spawn(
        _serve,
        (
          replies.sendPort,
          TransferableTypedData.fromList([
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ]),
        ),
        onExit: replies.sendPort,
        errorsAreFatal: true,
      );
      final ready = await replies.first.timeout(const Duration(seconds: 20));
      if (ready is! SendPort) {
        throw StateError('Model Random Forest HOG gagal dimuat.');
      }
      return (isolate: isolate, port: ready);
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      replies.close();
    }
  }

  Future<RandomForestHogPrediction> classifyFileWithLandmarks(
    String path,
    List<({double x, double y})> landmarks,
  ) async {
    if (!await File(path).exists()) {
      throw const FormatException('File gambar tidak ditemukan.');
    }
    final coordinates = landmarks
        .map((point) => (point.x, point.y))
        .toList(growable: false);
    final prediction = await _classify((path, coordinates));
    if (prediction == null) {
      throw const FormatException('Area tangan gagal diproses.');
    }
    return prediction;
  }

  Future<RandomForestHogPrediction?> classifyLumaWithLandmarks({
    required Uint8List bytes,
    required int width,
    required int height,
    required int stride,
    required int pixelStride,
    required int rotation,
    required List<({double x, double y})> landmarks,
  }) {
    final coordinates = landmarks
        .map((point) => (point.x, point.y))
        .toList(growable: false);
    return _classify((
      bytes,
      width,
      height,
      stride,
      pixelStride,
      rotation,
      coordinates,
    ));
  }

  Future<RandomForestHogPrediction> classifyFile(String path) async {
    if (!await File(path).exists()) {
      throw const FormatException('File gambar tidak ditemukan.');
    }
    final prediction = await _classify(path);
    if (prediction == null) {
      throw const FormatException(
        'Area tangan tidak ditemukan. Arahkan tangan ke tengah kamera.',
      );
    }
    return prediction;
  }

  Future<RandomForestHogPrediction?> classifyLuma({
    required Uint8List bytes,
    required int width,
    required int height,
    required int stride,
    required int pixelStride,
    required int rotation,
  }) => _classify((bytes, width, height, stride, pixelStride, rotation));

  Future<RandomForestHogPrediction?> _classify(Object input) async {
    final worker = await _getWorker();
    final pending = _worker;
    final replies = ReceivePort();
    try {
      worker.port.send((replies.sendPort, input));
      final result = await replies.first.timeout(const Duration(seconds: 10));
      if (result is String) throw FormatException(result);
      return result as RandomForestHogPrediction?;
    } on TimeoutException {
      if (identical(pending, _worker)) {
        worker.isolate.kill(priority: Isolate.immediate);
        _worker = null;
      }
      throw StateError('Waktu pemrosesan gambar habis.');
    } finally {
      replies.close();
    }
  }

  static void _serve((SendPort, TransferableTypedData) setup) {
    final model = RandomForestHogModel(setup.$2.materialize().asUint8List());
    final messages = ReceivePort();
    setup.$1.send(messages.sendPort);
    messages.listen((message) {
      final (reply, input) = message as (SendPort, Object);
      try {
        reply.send(_predict(model, input));
      } catch (failure) {
        reply.send('Gambar gagal diproses: $failure');
      }
    });
  }

  static Object? _predict(RandomForestHogModel model, Object input) {
    if (input is (String, List<(double, double)>)) {
      final (path, coordinates) = input;
      final image = HogImageInput.decode(File(path).readAsBytesSync());
      if (image == null) return 'Format gambar tidak dapat dibaca.';
      final xs = coordinates.map((point) => point.$1);
      final ys = coordinates.map((point) => point.$2);
      final crops = HogImageInput.prepareHandCropFromNormalizedRoi(
        image,
        normLeft: xs.reduce((a, b) => a < b ? a : b),
        normTop: ys.reduce((a, b) => a < b ? a : b),
        normRight: xs.reduce((a, b) => a > b ? a : b),
        normBottom: ys.reduce((a, b) => a > b ? a : b),
        tightFraming: true,
      );
      return _predictCrops(model, crops);
    }
    if (input is (Uint8List, int, int, int, int, int, List<(double, double)>)) {
      final (bytes, width, height, stride, pixelStride, rotation, coordinates) =
          input;
      final image = HogImageInput.fromLuma(
        bytes,
        width,
        height,
        stride,
        pixelStride,
        rotation,
      );
      if (image == null) return null;
      final xs = coordinates.map((point) => point.$1);
      final ys = coordinates.map((point) => point.$2);
      final crops = HogImageInput.prepareHandCropFromNormalizedRoi(
        image,
        normLeft: xs.reduce((a, b) => a < b ? a : b),
        normTop: ys.reduce((a, b) => a < b ? a : b),
        normRight: xs.reduce((a, b) => a > b ? a : b),
        normBottom: ys.reduce((a, b) => a > b ? a : b),
        tightFraming: true,
      );
      return _predictCrops(model, crops);
    }

    final img.Image? image;
    final bool isPhoto;
    if (input is String) {
      image = HogImageInput.decode(File(input).readAsBytesSync());
      isPhoto = true;
    } else if (input is (Uint8List, int, int, int, int, int)) {
      final (bytes, width, height, stride, pixelStride, rotation) = input;
      image = HogImageInput.fromLuma(
        bytes,
        width,
        height,
        stride,
        pixelStride,
        rotation,
      );
      isPhoto = false;
    } else {
      return 'Format input gambar tidak didukung.';
    }
    if (image == null) return 'Format gambar tidak dapat dibaca.';
    final prepared = HogImageInput.prepareHandCrops(
      image,
      tightFraming: isPhoto,
      includePhotoChecks: isPhoto,
    );
    if (prepared.rejection != null) {
      return isPhoto ? prepared.rejection : null;
    }
    return _predictCrops(model, prepared.crops);
  }

  static RandomForestHogPrediction _predictCrops(
    RandomForestHogModel model,
    List<Uint8List> crops,
  ) {
    final result = model.predictCrops(crops);
    return RandomForestHogPrediction(
      label: result.label,
      scores: result.scores,
      accepted: result.accepted,
    );
  }
}
