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
  static const modelId = 'svm_multimodal_contour_v3';
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
        throw StateError('Model SVM gagal dimuat.');
      }
      return (isolate: isolate, port: ready);
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      replies.close();
    }
  }



  /// Hybrid 1867-dim classification on a photo file using MediaPipe 21 landmarks.
  Future<SvmHogPrediction> classifyFileWithLandmarks(
    String path,
    List<({double x, double y})> landmarks,
  ) async {
    if (!await File(path).exists()) {
      throw const FormatException('File gambar tidak ditemukan.');
    }
    final coords = landmarks.map((p) => (p.x, p.y)).toList(growable: false);
    final prediction = await _classify((path, coords));
    if (prediction == null) {
      throw const FormatException('Area tangan gagal diproses.');
    }
    return prediction;
  }

  /// Hybrid 1867-dim classification on a live luma frame using MediaPipe 21 landmarks.
  Future<SvmHogPrediction?> classifyLumaWithLandmarks({
    required Uint8List bytes,
    required int width,
    required int height,
    required int stride,
    required int pixelStride,
    required int rotation,
    required List<({double x, double y})> landmarks,
  }) {
    final coords = landmarks.map((p) => (p.x, p.y)).toList(growable: false);
    return _classify((bytes, width, height, stride, pixelStride, rotation, coords));
  }

  /// Classify directly from 21 MediaPipe hand landmarks (52 geometric features).
  Future<SvmHogPrediction> classifyLandmarks(
    List<({double x, double y})> landmarks,
  ) async {
    final coords = landmarks.map((p) => (p.x, p.y)).toList(growable: false);
    final prediction = await _classify(coords);
    if (prediction == null) {
      throw const FormatException('Landmark tangan gagal diproses.');
    }
    return prediction;
  }

  Future<SvmHogPrediction> classifyFile(String path) async {
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


  /// Classify a photo file using normalized MediaPipe ROI (0.0..1.0).
  Future<SvmHogPrediction> classifyFileWithNormalizedRoi(
    String path, {
    required double normLeft,
    required double normTop,
    required double normRight,
    required double normBottom,
  }) async {
    if (!await File(path).exists()) {
      throw const FormatException('File gambar tidak ditemukan.');
    }
    final prediction = await _classify((
      path,
      normLeft,
      normTop,
      normRight,
      normBottom,
    ));
    if (prediction == null) {
      throw const FormatException('Area tangan pada ROI gagal diproses.');
    }
    return prediction;
  }

  /// Classify a photo file using an external MediaPipe hand bounding box (pixel coords).
  Future<SvmHogPrediction> classifyFileWithRoi(
    String path, {
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) async {
    if (!await File(path).exists()) {
      throw const FormatException('File gambar tidak ditemukan.');
    }
    final prediction = await _classify((path, left, top, right, bottom));
    if (prediction == null) {
      throw const FormatException('Area tangan pada ROI gagal diproses.');
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


  /// Classify a live camera luma frame using normalized MediaPipe ROI (0.0..1.0).
  Future<SvmHogPrediction?> classifyLumaWithNormalizedRoi({
    required Uint8List bytes,
    required int width,
    required int height,
    required int stride,
    required int pixelStride,
    required int rotation,
    required double normLeft,
    required double normTop,
    required double normRight,
    required double normBottom,
  }) => _classify((
        bytes,
        width,
        height,
        stride,
        pixelStride,
        rotation,
        normLeft,
        normTop,
        normRight,
        normBottom,
      ));

  /// Classify a live camera luma frame using an external MediaPipe hand bounding box.
  Future<SvmHogPrediction?> classifyLumaWithRoi({
    required Uint8List bytes,
    required int width,
    required int height,
    required int stride,
    required int pixelStride,
    required int rotation,
    required int left,
    required int top,
    required int right,
    required int bottom,
  }) => _classify((
        bytes,
        width,
        height,
        stride,
        pixelStride,
        rotation,
        left,
        top,
        right,
        bottom,
      ));

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
        // -1. Hybrid 1867-dim (HOG + LBP + Hu + Contour + MediaPipe Landmarks)

        if (input is (String, List<(double, double)>)) {
          final (path, coords) = input;
          final pts = coords.map((e) => (x: e.$1, y: e.$2)).toList(growable: false);
          if (model.featureCount == SvmHogModel.landmarkFeatureCount) {
            final p = model.predictLandmarks(pts);
            reply.send(SvmHogPrediction(label: p.label, scores: p.scores, accepted: p.accepted));
            return;
          }
          final image = SvmHogInput.decode(File(path).readAsBytesSync());
          if (image == null) {
            reply.send('Format gambar tidak dapat dibaca.');
            return;
          }
          var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
          for (final p in pts) {
            if (p.x < minX) minX = p.x;
            if (p.y < minY) minY = p.y;
            if (p.x > maxX) maxX = p.x;
            if (p.y > maxY) maxY = p.y;
          }
          final crops = SvmHogInput.prepareHandCropFromNormalizedRoi(
            image,
            normLeft: minX,
            normTop: minY,
            normRight: maxX,
            normBottom: maxY,
            tightFraming: true,
          );
          final p = model.featureCount == SvmHogModel.hybridFeatureCount
              ? model.predictCropsWithLandmarks(crops, pts)
              : model.predictCrops(crops);
          reply.send(SvmHogPrediction(label: p.label, scores: p.scores, accepted: p.accepted));
          return;
        }
        if (input is (Uint8List, int, int, int, int, int, List<(double, double)>)) {
          final (bytes, width, height, stride, pixelStride, rotation, coords) = input;
          final pts = coords.map((e) => (x: e.$1, y: e.$2)).toList(growable: false);
          if (model.featureCount == SvmHogModel.landmarkFeatureCount) {
            final p = model.predictLandmarks(pts);
            reply.send(SvmHogPrediction(label: p.label, scores: p.scores, accepted: p.accepted));
            return;
          }
          final image = SvmHogInput.fromLuma(bytes, width, height, stride, pixelStride, rotation);
          if (image == null) {
            reply.send('Format gambar tidak dapat dibaca.');
            return;
          }
          var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
          for (final p in pts) {
            if (p.x < minX) minX = p.x;
            if (p.y < minY) minY = p.y;
            if (p.x > maxX) maxX = p.x;
            if (p.y > maxY) maxY = p.y;
          }
          final crops = SvmHogInput.prepareHandCropFromNormalizedRoi(
            image,
            normLeft: minX,
            normTop: minY,
            normRight: maxX,
            normBottom: maxY,
            tightFraming: true,
          );
          final p = model.featureCount == SvmHogModel.hybridFeatureCount
              ? model.predictCropsWithLandmarks(crops, pts)
              : model.predictCrops(crops);
          reply.send(SvmHogPrediction(label: p.label, scores: p.scores, accepted: p.accepted));
          return;
        }

        // 0. Direct MediaPipe 21-landmark classification (52 features)

        if (input is List<(double, double)>) {
          if (model.featureCount != SvmHogModel.landmarkFeatureCount) {
            reply.send('Model svm_hog.bin.gz belum diganti ke model landmark 52 fitur.');
            return;
          }
          final pts = input
              .map((e) => (x: e.$1, y: e.$2))
              .toList(growable: false);
          final prediction = model.predictLandmarks(pts);
          reply.send(
            SvmHogPrediction(
              label: prediction.label,
              scores: prediction.scores,
              accepted: prediction.accepted,
            ),
          );
          return;
        }

        // 1. Optional MediaPipe ROI paths

        if (input is (String, double, double, double, double)) {
          final (path, normLeft, normTop, normRight, normBottom) = input;
          final image = SvmHogInput.decode(File(path).readAsBytesSync());
          if (image == null) {
            reply.send('Format gambar tidak dapat dibaca.');
            return;
          }
          final crops = SvmHogInput.prepareHandCropFromNormalizedRoi(
            image,
            normLeft: normLeft,
            normTop: normTop,
            normRight: normRight,
            normBottom: normBottom,
            tightFraming: true,
          );
          final prediction = model.predictCrops(crops);
          reply.send(
            SvmHogPrediction(
              label: prediction.label,
              scores: prediction.scores,
              accepted: prediction.accepted,
            ),
          );
          return;
        }

        if (input is (String, int, int, int, int)) {
          final (path, left, top, right, bottom) = input;
          final image = SvmHogInput.decode(File(path).readAsBytesSync());
          if (image == null) {
            reply.send('Format gambar tidak dapat dibaca.');
            return;
          }
          final crops = SvmHogInput.prepareHandCropFromRoi(
            image,
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            tightFraming: true,
          );
          final prediction = model.predictCrops(crops);
          reply.send(
            SvmHogPrediction(
              label: prediction.label,
              scores: prediction.scores,
              accepted: prediction.accepted,
            ),
          );
          return;
        }
        if (input is (Uint8List, int, int, int, int, int, int, int, int, int)) {
          final (
            bytes,
            width,
            height,
            stride,
            pixelStride,
            rotation,
            left,
            top,
            right,
            bottom,
          ) = input;
          final image = SvmHogInput.fromLuma(
            bytes,
            width,
            height,
            stride,
            pixelStride,
            rotation,
          );
          if (image == null) {
            reply.send('Format gambar tidak dapat dibaca.');
            return;
          }
          final crops = SvmHogInput.prepareHandCropFromRoi(
            image,
            left: left,
            top: top,
            right: right,
            bottom: bottom,
            tightFraming: false,
          );
          final prediction = model.predictCrops(crops);
          reply.send(
            SvmHogPrediction(
              label: prediction.label,
              scores: prediction.scores,
              accepted: prediction.accepted,
            ),
          );
          return;
        }


        if (input
            is (
              Uint8List,
              int,
              int,
              int,
              int,
              int,
              double,
              double,
              double,
              double,
            )) {
          final (
            bytes,
            width,
            height,
            stride,
            pixelStride,
            rotation,
            normLeft,
            normTop,
            normRight,
            normBottom,
          ) = input;
          final image = SvmHogInput.fromLuma(
            bytes,
            width,
            height,
            stride,
            pixelStride,
            rotation,
          );
          if (image == null) {
            reply.send('Format gambar tidak dapat dibaca.');
            return;
          }
          final crops = SvmHogInput.prepareHandCropFromNormalizedRoi(
            image,
            normLeft: normLeft,
            normTop: normTop,
            normRight: normRight,
            normBottom: normBottom,
            tightFraming: false,
          );
          final prediction = model.predictCrops(crops);
          reply.send(
            SvmHogPrediction(
              label: prediction.label,
              scores: prediction.scores,
              accepted: prediction.accepted,
            ),
          );
          return;
        }

        // 2. Standard automatic contour/skin segmentation paths
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
        if (model.featureCount == SvmHogModel.hybridFeatureCount) {
          reply.send(
            input is String
                ? 'Tangan tidak terdeteksi oleh MediaPipe. Pastikan seluruh jari terlihat jelas.'
                : null,
          );
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