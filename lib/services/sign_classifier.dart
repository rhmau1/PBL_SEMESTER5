import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../models/sign_prediction.dart';
import 'svm_hog_input.dart';
import 'svm_hog_model.dart';

enum SignModel {
  svmHog(id: 'svm_hog_augmented_c100_scale', name: 'SVM + HOG');

  const SignModel({required this.id, required this.name});

  final String id;
  final String name;
}

class SignClassifier {
  SignClassifier._();

  static final SignClassifier instance = SignClassifier._();
  Future<({Isolate isolate, SendPort port})>? _worker;

  Future<void> initialize({SignModel model = SignModel.svmHog}) async {
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

  Future<SignPrediction> classifyFile(
    String path, {
    SignModel model = SignModel.svmHog,
  }) async {
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

  Future<SignPrediction> classifyUploadFile(
    String path, {
    SignModel model = SignModel.svmHog,
  }) => classifyFile(path, model: model);

  Future<SignPrediction?> classifyLuma({
    required Uint8List bytes,
    required int width,
    required int height,
    required int stride,
    required int pixelStride,
    required int rotation,
  }) => _classify((bytes, width, height, stride, pixelStride, rotation));

  Future<SignPrediction?> _classify(Object input) async {
    final worker = await _getWorker();
    final pending = _worker;
    final replies = ReceivePort();
    try {
      worker.port.send((replies.sendPort, input));
      final result = await replies.first.timeout(const Duration(seconds: 10));
      if (result is String) throw FormatException(result);
      return result as SignPrediction?;
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
        final crops = SvmHogInput.handCrops(image);
        if (crops.isEmpty) {
          reply.send(null);
          return;
        }
        final first = model.predict(SvmHogModel.hog(crops[0]));
        final second = model.predict(SvmHogModel.hog(crops[1]));
        reply.send(
          SignPrediction(
            label: first.label,
            confidence: null,
            scores: first.scores,
            agreement: first.label == second.label,
          ),
        );
      } catch (_) {
        reply.send('Gambar gagal diproses.');
      }
    });
  }
}
