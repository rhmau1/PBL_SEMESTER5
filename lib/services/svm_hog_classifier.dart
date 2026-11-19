import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'svm_hog_input.dart';
import 'svm_hog_model.dart';

class SvmHogPrediction {
  const SvmHogPrediction({
    required this.label,
    required this.scores,
    required this.accepted,
  });

  final String label;
  final List<double> scores;
  final bool accepted;
}

class SvmHogClassifier {
  SvmHogClassifier._();

  static final SvmHogClassifier instance = SvmHogClassifier._();
  static const modelId = 'svm_hog_augmented_c100_scale';
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
      final data = await rootBundle.load('assets/models/svm_hog.bin.gz');
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
        throw StateError('Model SVM-HOG gagal dimuat.');
      }
      return (isolate: isolate, port: ready);
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      replies.close();
    }
  }

  Future<SvmHogPrediction> classifyFile(String path) async {
    if (!await File(path).exists()) {
      throw const FormatException('File gambar tidak ditemukan.');
    }
    final prediction = await _classify(path);
    if (prediction == null) {
      throw const FormatException(
        'Area tangan tidak ditemukan. Gunakan satu tangan dan latar polos.',
      );
    }
    return prediction;
  }

  Future<SvmHogPrediction?> classifyLuma({
    required Uint8List bytes,
    required int width,
    required int height,
    required int stride,
    required int pixelStride,
    required int rotation,
  }) => _classify((bytes, width, height, stride, pixelStride, rotation));

  Future<SvmHogPrediction?> _classify(Object input) async {
    final worker = await _getWorker();
    final pending = _worker;
    final replies = ReceivePort();
    try {
      worker.port.send((replies.sendPort, input));
      final result = await replies.first.timeout(const Duration(seconds: 10));
      if (result is String) throw FormatException(result);
      return result as SvmHogPrediction?;
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
    final model = SvmHogModel(setup.$2.materialize().asUint8List());
    final messages = ReceivePort();
    setup.$1.send(messages.sendPort);
    messages.listen((message) {
      final (reply, input) = message as (SendPort, Object);
      try {
        final image = switch (input) {
          String path => SvmHogInput.decode(File(path).readAsBytesSync()),
          (
            Uint8List bytes,
            int width,
            int height,
            int stride,
            int pixelStride,
            int rotation,
          ) =>
            SvmHogInput.fromLuma(
              bytes,
              width,
              height,
              stride,
              pixelStride,
              rotation,
            ),
          _ => null,
        };
        if (image == null) {
          reply.send('Format gambar tidak dapat dibaca.');
          return;
        }
        final (
          crops: crops,
          rejection: rejection,
        ) = SvmHogInput.prepareHandCrops(
          image,
          tightFraming: input is String,
          includePhotoChecks: input is String,
        );
        if (rejection != null) {
          reply.send(input is String ? rejection : null);
          return;
        }
        final prediction = model.predictCrops(crops);
        reply.send(
          SvmHogPrediction(
            label: prediction.label,
            scores: prediction.scores,
            accepted: prediction.accepted,
          ),
        );
      } catch (_) {
        reply.send('Gambar gagal diproses.');
      }
    });
  }
}
