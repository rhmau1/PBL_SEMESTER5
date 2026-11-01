import 'dart:math' as math;
import 'dart:typed_data';

import '../models/hand_landmark_frame.dart';

class JzSequenceException implements Exception {
  const JzSequenceException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'JzSequenceException($code): $message';
}

/// The exact tensor and observation quality used for one complete J/Z clip.
class JzPreparedSequence {
  JzPreparedSequence({
    required List<List<double>> features,
    required this.sampledFrames,
    required this.detectedFrames,
    required this.durationSeconds,
    required this.longestMissingGapSeconds,
    required this.palmScale,
    required List<double> anchor,
  }) : features = List.unmodifiable(
         features.map((row) => List<double>.unmodifiable(row)),
       ),
       anchor = List.unmodifiable(anchor);

  final List<List<double>> features;
  final int sampledFrames;
  final int detectedFrames;
  final double durationSeconds;
  final double longestMissingGapSeconds;
  final double palmScale;
  final List<double> anchor;

  double get detectionFraction => detectedFrames / sampledFrames;

  Map<String, Object> get quality => {
    'sampled_frames': sampledFrames,
    'detected_frames': detectedFrames,
    'detection_fraction': detectionFraction,
    'sampled_duration_seconds': durationSeconds,
    'longest_missing_gap_seconds': longestMissingGapSeconds,
    'palm_scale': palmScale,
    'anchor_xyz': anchor,
  };
}

/// Matches dynamic_training.py's _make_features and its MediaPipe hand choice.
///
/// Supply fresh observations sampled at approximately [sampleFps], including
/// no-hand observations. This does not duplicate cached landmarks, infer a
/// missing observation from a cached result, or trim gesture boundaries.
class JzSequencePreprocessor {
  const JzSequencePreprocessor();

  static const featureVersion = 'jz_fixed_clip_anchor_palm_scale_v1';
  static const sequenceLength = 48;
  static const featureCount = 64;
  static const sampleFps = 15.0;
  static const minimumDetectedSamples = 6;
  static const minimumDetectedFraction = 0.60;
  static const maximumMissingGapSeconds = 0.55;
  static const minimumDurationSeconds = 0.25;

  JzPreparedSequence prepare(List<HandLandmarkFrame> frames) {
    if (frames.length < 2) {
      throw const JzSequenceException(
        'clip_too_short',
        'Diperlukan beberapa frame baru untuk membaca gerakan J atau Z.',
      );
    }
    _validateFrames(frames);

    final firstTimestamp = frames.first.timestampMs;
    final times = frames
        .map((frame) => (frame.timestampMs - firstTimestamp) / 1000.0)
        .toList(growable: false);
    final duration = times.last;
    if (duration < minimumDurationSeconds) {
      throw const JzSequenceException(
        'clip_too_short',
        'Durasi gerakan kurang dari 0,25 detik.',
      );
    }

    final observed = <Float32List>[];
    final observedTimes = <double>[];
    final presence = <double>[];
    HandLandmarkPoint? previousWrist;
    final aspectRatio = _f32(frames.first.width / frames.first.height);
    for (var i = 0; i < frames.length; i++) {
      final hands = frames[i].hands;
      if (hands.isEmpty) {
        presence.add(0.0);
        continue;
      }
      final selected = _selectHand(hands, previousWrist);
      previousWrist = selected.first;
      // MediaPipe returns float32 coordinates. Retain the training pipeline's
      // float32 rounding before normalization and subsequent interpolation.
      final coordinates = Float32List(63);
      for (var landmark = 0; landmark < 21; landmark++) {
        final point = selected[landmark];
        coordinates[landmark * 3] = _f32(point.x) * aspectRatio;
        coordinates[landmark * 3 + 1] = point.y;
        coordinates[landmark * 3 + 2] = _f32(point.z) * aspectRatio;
      }
      observed.add(coordinates);
      observedTimes.add(times[i]);
      presence.add(1.0);
    }
    if (observed.length < minimumDetectedSamples) {
      throw const JzSequenceException(
        'too_few_detected_samples',
        'Tangan harus terdeteksi pada sedikitnya 6 frame baru.',
      );
    }
    if (observed.length / frames.length < minimumDetectedFraction) {
      throw const JzSequenceException(
        'too_many_missing_detections',
        'Tangan tidak cukup terlihat selama gerakan.',
      );
    }
    final longestGap = _longestMissingGap(times, presence);
    if (longestGap > maximumMissingGapSeconds) {
      throw const JzSequenceException(
        'missing_gap_too_long',
        'Tangan hilang lebih dari 0,55 detik selama gerakan.',
      );
    }
    // The training decoder always recorded each scheduled observation. A long
    // hole in the supplied timeline must not become invented hand visibility.
    for (var i = 1; i < times.length; i++) {
      if (times[i] - times[i - 1] > maximumMissingGapSeconds) {
        throw const JzSequenceException(
          'sampling_gap_too_long',
          'Aliran frame terputus lebih dari 0,55 detik.',
        );
      }
    }

    final palmDistances = observed.map(_palmDistance).toList();
    final scale = _f32(_median(palmDistances));
    if (!scale.isFinite || scale < 0.005) {
      throw const JzSequenceException(
        'invalid_palm_scale',
        'Ukuran landmark telapak tangan tidak valid.',
      );
    }
    final anchor = List<double>.generate(
      3,
      (coordinate) =>
          _median(observed.take(3).map((frame) => frame[coordinate]).toList()),
      growable: false,
    );
    for (final frame in observed) {
      for (var i = 0; i < 63; i++) {
        frame[i] = _f32(frame[i] - anchor[i % 3]) / scale;
      }
    }
    final features = List<List<double>>.generate(sequenceLength, (row) {
      final time = duration * row / (sequenceLength - 1);
      return List<double>.generate(featureCount, (column) {
        final value = column == 63
            ? _interpolate(time, times, (index) => presence[index])
            : _interpolate(
                time,
                observedTimes,
                (index) => observed[index][column],
              );
        final result = _f32(value);
        if (!result.isFinite) {
          throw const JzSequenceException(
            'nonfinite_features',
            'Fitur gerakan tidak valid.',
          );
        }
        return result;
      }, growable: false);
    }, growable: false);
    return JzPreparedSequence(
      features: features,
      sampledFrames: frames.length,
      detectedFrames: observed.length,
      durationSeconds: duration,
      longestMissingGapSeconds: longestGap,
      palmScale: scale,
      anchor: anchor,
    );
  }

  void _validateFrames(List<HandLandmarkFrame> frames) {
    var previousTimestamp = -1;
    final width = frames.first.width;
    final height = frames.first.height;
    if (width <= 0 || height <= 0) {
      throw const JzSequenceException(
        'invalid_geometry',
        'Ukuran gambar landmark harus lebih dari nol.',
      );
    }
    for (final frame in frames) {
      if (frame.timestampMs < 0 || frame.timestampMs <= previousTimestamp) {
        throw const JzSequenceException(
          'stale_timestamp',
          'Timestamp frame harus bertambah dan tidak boleh digunakan ulang.',
        );
      }
      previousTimestamp = frame.timestampMs;
      if (frame.width != width || frame.height != height) {
        throw const JzSequenceException(
          'geometry_changed',
          'Orientasi atau ukuran gambar berubah. Mulai ulang gerakannya.',
        );
      }
      for (final hand in frame.hands) {
        if (hand.length != 21 ||
            hand.any(
              (point) =>
                  !point.x.isFinite || !point.y.isFinite || !point.z.isFinite,
            )) {
          throw const JzSequenceException(
            'invalid_landmarks',
            'Setiap tangan harus memiliki 21 landmark bernilai valid.',
          );
        }
      }
    }
  }

  List<HandLandmarkPoint> _selectHand(
    List<List<HandLandmarkPoint>> hands,
    HandLandmarkPoint? previousWrist,
  ) {
    var selected = hands.first;
    var best = previousWrist == null
        ? _area(selected)
        : _wristDistanceSquared(selected.first, previousWrist);
    for (final candidate in hands.skip(1)) {
      final score = previousWrist == null
          ? _area(candidate)
          : _wristDistanceSquared(candidate.first, previousWrist);
      if (previousWrist == null ? score > best : score < best) {
        selected = candidate;
        best = score;
      }
    }
    return selected;
  }

  double _area(List<HandLandmarkPoint> hand) {
    var minX = hand.first.x;
    var maxX = minX;
    var minY = hand.first.y;
    var maxY = minY;
    for (final point in hand.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }
    return (maxX - minX) * (maxY - minY);
  }

  double _wristDistanceSquared(HandLandmarkPoint a, HandLandmarkPoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return dx * dx + dy * dy;
  }

  double _palmDistance(Float32List frame) {
    final dx = _f32(frame[27] - frame[0]);
    final dy = _f32(frame[28] - frame[1]);
    final dz = _f32(frame[29] - frame[2]);
    final sum = _f32(_f32(_f32(dx * dx) + _f32(dy * dy)) + _f32(dz * dz));
    return _f32(math.sqrt(sum));
  }

  double _longestMissingGap(List<double> times, List<double> presence) {
    final steps = <double>[
      for (var i = 1; i < times.length; i++) times[i] - times[i - 1],
    ];
    final step = _median(steps);
    var longest = 0.0;
    var index = 0;
    while (index < times.length) {
      if (presence[index] == 1.0) {
        index++;
        continue;
      }
      final start = index;
      while (index < times.length && presence[index] == 0.0) {
        index++;
      }
      longest = math.max(longest, times[index - 1] - times[start] + step);
    }
    return longest;
  }

  double _median(List<double> values) {
    values.sort();
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2.0;
  }

  double _interpolate(
    double time,
    List<double> times,
    double Function(int) valueAt,
  ) {
    if (time <= times.first) return valueAt(0);
    if (time >= times.last) return valueAt(times.length - 1);
    var low = 0;
    var high = times.length - 1;
    while (high - low > 1) {
      final middle = (low + high) ~/ 2;
      if (times[middle] <= time) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final weight = (time - times[low]) / (times[high] - times[low]);
    return valueAt(low) + weight * (valueAt(high) - valueAt(low));
  }

  static double _f32(double value) => (Float32List(1)..[0] = value)[0];
}
