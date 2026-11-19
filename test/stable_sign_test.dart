import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/services/stable_sign.dart';

void main() {
  test('emits each stable pose once until the hand leaves the frame', () {
    final stable = StableSign();
    expect(stable.add('A', hasForeground: true), isNull);
    expect(stable.add('A', hasForeground: true), isNull);
    expect(stable.add('A', hasForeground: true), 'A');
    expect(stable.current, 'A');
    expect(stable.add('A', hasForeground: true), isNull);
    expect(stable.add(null, hasForeground: false), isNull);
    expect(stable.add(null, hasForeground: false), isNull);
    expect(stable.current, isNull);
    expect(stable.add('A', hasForeground: true), isNull);
    expect(stable.add('A', hasForeground: true), isNull);
    expect(stable.add('A', hasForeground: true), 'A');
  });
}
