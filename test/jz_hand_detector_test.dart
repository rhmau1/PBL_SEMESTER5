import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/services/jz_hand_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('latih_isyarat/dynamic_hand_landmarker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'bridge preserves xyz, unclamped positions and source timestamp',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method != 'detectFrame') return {'status': 'ok'};
        expect(call.arguments['timestampMs'], 134);
        return {
          'timestampMs': 134,
          'width': 640,
          'height': 480,
          'hands': [
            List.generate(21, (_) => [-0.02, 1.01, -0.15]),
          ],
        };
      });
      final detector = PlatformJzHandDetector();
      await detector.startClip();
      final frame = await detector.detectFrame(Uint8List(4), timestampMs: 134);
      expect(frame.timestampMs, 134);
      expect(frame.hands.single.first.x, -0.02);
      expect(frame.hands.single.first.y, 1.01);
      expect(frame.hands.single.first.z, -0.15);
      await detector.finishClip();
      expect(calls, ['startClip', 'detectFrame', 'finishClip']);
    },
  );

  test('fresh no-hand observation remains an empty observation', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'timestampMs': 67,
        'width': 640,
        'height': 480,
        'hands': <dynamic>[],
      },
    );
    final frame = await PlatformJzHandDetector().detectFrame(
      Uint8List(4),
      timestampMs: 67,
    );
    expect(frame.hands, isEmpty);
  });

  test(
    'stale results and non-finite or incomplete hands are rejected',
    () async {
      for (final data in [
        {'timestampMs': 0, 'width': 640, 'height': 480, 'hands': <dynamic>[]},
        {
          'timestampMs': 67,
          'width': 640,
          'height': 480,
          'hands': [
            [0.1, 0.2],
          ],
        },
        {
          'timestampMs': 67,
          'width': 640,
          'height': 480,
          'hands': [
            List.generate(21, (_) => [double.nan, 0.2, 0.3]),
          ],
        },
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => data);
        await expectLater(
          PlatformJzHandDetector().detectFrame(Uint8List(4), timestampMs: 67),
          throwsFormatException,
        );
      }
    },
  );
}
