import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/models/hand_landmark_frame.dart';
import 'package:sign_language/services/jz_sequence_preprocessor.dart';

List<HandLandmarkPoint> _hand({double x = 0.2}) => List.generate(
  21,
  (index) => HandLandmarkPoint(
    x: x + index * 0.006,
    y: 0.5 - index * 0.008,
    z: index * 0.001,
  ),
);

List<HandLandmarkFrame> _frames(
  int count, {
  Set<int> missing = const {},
  List<int>? timestamps,
  List<HandLandmarkPoint>? hand,
}) => List.generate(
  count,
  (index) => HandLandmarkFrame(
    timestampMs: timestamps?[index] ?? index * 67,
    width: 640,
    height: 480,
    hands: missing.contains(index)
        ? []
        : [hand ?? _hand(x: 0.2 + index * 0.005)],
  ),
);

Matcher _rejects(String code) => throwsA(
  isA<JzSequenceException>().having((error) => error.code, 'code', code),
);

void main() {
  const preprocessor = JzSequencePreprocessor();

  test('matches the actual NumPy training function over all 3072 features', () {
    final fixture = jsonDecode(
      File('test/fixtures/jz_preprocessing_numpy.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(
      fixture['generator'],
      'docs/training/j_dan_z/dynamic_training.py::_make_features',
    );
    final frames = (fixture['frames'] as List).map((value) {
      final frame = value as Map<String, dynamic>;
      return HandLandmarkFrame(
        timestampMs: frame['timestamp_ms'] as int,
        width: frame['width'] as int,
        height: frame['height'] as int,
        hands: (frame['hands'] as List)
            .map(
              (hand) => (hand as List)
                  .map(
                    (point) => HandLandmarkPoint(
                      x: ((point as List)[0] as num).toDouble(),
                      y: (point[1] as num).toDouble(),
                      z: (point[2] as num).toDouble(),
                    ),
                  )
                  .toList(),
            )
            .toList(),
      );
    }).toList();
    final prepared = preprocessor.prepare(frames);
    final expected = fixture['expected'] as List;
    expect(prepared.features, hasLength(48));
    var maximumDifference = 0.0;
    for (var row = 0; row < 48; row++) {
      expect(prepared.features[row], hasLength(64));
      for (var column = 0; column < 64; column++) {
        maximumDifference = math.max(
          maximumDifference,
          (prepared.features[row][column] -
                  (expected[row][column] as num).toDouble())
              .abs(),
        );
      }
    }
    expect(maximumDifference, lessThanOrEqualTo(0.000001));
    expect(prepared.sampledFrames, 12);
    expect(prepared.detectedFrames, 9);
    expect(prepared.detectionFraction, 0.75);
    final quality = fixture['quality'] as Map<String, dynamic>;
    expect(prepared.durationSeconds, quality['sampled_duration_seconds']);
    expect(
      prepared.longestMissingGapSeconds,
      closeTo(quality['longest_missing_gap_seconds'] as double, 1e-12),
    );
    expect(prepared.palmScale, closeTo(quality['palm_scale'] as double, 1e-8));
    expect(prepared.anchor, quality['anchor_xyz']);
    expect(prepared.features.first[63], 0.0);
    expect(prepared.features.last[63], 0.0);
    expect(prepared.features.any((row) => row[63] > 0 && row[63] < 1), isTrue);
    // The fixed clip anchor retains wrist movement. A per-frame anchor would
    // incorrectly make every wrist coordinate zero.
    expect(
      prepared.features.last[0] - prepared.features.first[0],
      greaterThan(1),
    );
    expect(prepared.quality['detected_frames'], 9);
  });

  test('uses acquisition time, independent of the timestamp origin', () {
    final frames = _frames(10);
    final shifted = frames
        .map(
          (frame) => HandLandmarkFrame(
            timestampMs: frame.timestampMs + 900000,
            width: frame.width,
            height: frame.height,
            hands: frame.hands,
          ),
        )
        .toList();
    expect(
      preprocessor.prepare(shifted).features,
      preprocessor.prepare(frames).features,
    );
  });

  test('fresh no-hand observations remain missing, not cached landmarks', () {
    final prepared = preprocessor.prepare(_frames(10, missing: {4, 5}));
    expect(prepared.sampledFrames, 10);
    expect(prepared.detectedFrames, 8);
    expect(prepared.detectionFraction, 0.8);
    expect(prepared.features.any((row) => row[63] == 0), isTrue);
    expect(prepared.features.any((row) => row[63] == 1), isTrue);
    expect(prepared.longestMissingGapSeconds, closeTo(0.134, 1e-12));
  });

  test('rejects empty, single-frame, and insufficient-duration clips', () {
    expect(() => preprocessor.prepare([]), _rejects('clip_too_short'));
    expect(() => preprocessor.prepare(_frames(1)), _rejects('clip_too_short'));
    expect(
      () =>
          preprocessor.prepare(_frames(6, timestamps: [0, 10, 20, 30, 40, 50])),
      _rejects('clip_too_short'),
    );
  });

  test('rejects fewer than six detected samples and an empty camera', () {
    expect(
      () => preprocessor.prepare(_frames(6, missing: {2})),
      _rejects('too_few_detected_samples'),
    );
    expect(
      () => preprocessor.prepare(
        _frames(10, missing: Set.from(List.generate(10, (i) => i))),
      ),
      _rejects('too_few_detected_samples'),
    );
  });

  test('rejects a detection fraction below the training contract', () {
    expect(
      () => preprocessor.prepare(_frames(12, missing: {0, 2, 4, 6, 8, 10})),
      _rejects('too_many_missing_detections'),
    );
  });

  test('rejects long continuous detection gaps despite enough detections', () {
    expect(
      () => preprocessor.prepare(
        _frames(
          30,
          missing: Set.from(List.generate(10, (index) => index + 10)),
        ),
      ),
      _rejects('missing_gap_too_long'),
    );
  });

  test('rejects long unreported capture holes as a runtime quality guard', () {
    // Stricter than Python _make_features: runtime capture can stall, unlike
    // the training decoder which records each requested fresh observation.
    expect(
      () => preprocessor.prepare(
        _frames(7, timestamps: [0, 67, 134, 201, 268, 335, 1000]),
      ),
      _rejects('sampling_gap_too_long'),
    );
  });

  test('rejects repeated, backwards, and negative acquisition timestamps', () {
    for (final times in [
      [0, 67, 134, 134, 268, 335],
      [0, 67, 134, 133, 268, 335],
      [-1, 67, 134, 201, 268, 335],
    ]) {
      expect(
        () => preprocessor.prepare(_frames(6, timestamps: times)),
        _rejects('stale_timestamp'),
      );
    }
  });

  test('rejects geometry changes instead of mixing camera orientations', () {
    final frames = _frames(10);
    frames[5] = HandLandmarkFrame(
      timestampMs: frames[5].timestampMs,
      width: 480,
      height: 640,
      hands: frames[5].hands,
    );
    expect(() => preprocessor.prepare(frames), _rejects('geometry_changed'));
    frames[0] = HandLandmarkFrame(
      timestampMs: 0,
      width: 0,
      height: 480,
      hands: frames[0].hands,
    );
    expect(() => preprocessor.prepare(frames), _rejects('invalid_geometry'));
  });

  test('rejects incomplete, nonfinite, and degenerate hand geometry', () {
    expect(
      () => preprocessor.prepare(_frames(6, hand: _hand().sublist(0, 20))),
      _rejects('invalid_landmarks'),
    );
    final invalidHand = _hand();
    invalidHand[3] = const HandLandmarkPoint(x: double.nan, y: 0.1, z: 0);
    expect(
      () => preprocessor.prepare(_frames(6, hand: invalidHand)),
      _rejects('invalid_landmarks'),
    );
    expect(
      () => preprocessor.prepare(
        _frames(
          6,
          hand: List.filled(21, const HandLandmarkPoint(x: 0.2, y: 0.3, z: 0)),
        ),
      ),
      _rejects('invalid_palm_scale'),
    );
  });

  test('copies incoming lists and protects prepared tensors from mutation', () {
    final hand = _hand();
    final hands = [hand];
    final frame = HandLandmarkFrame(
      timestampMs: 0,
      width: 640,
      height: 480,
      hands: hands,
    );
    hand.clear();
    hands.clear();
    expect(frame.hands.single, hasLength(21));
    expect(() => frame.hands.clear(), throwsUnsupportedError);
    expect(() => frame.hands.single.clear(), throwsUnsupportedError);
    final prepared = preprocessor.prepare(_frames(6));
    expect(() => prepared.features.clear(), throwsUnsupportedError);
    expect(() => prepared.features.first.clear(), throwsUnsupportedError);
    expect(() => prepared.anchor.clear(), throwsUnsupportedError);
  });
}
