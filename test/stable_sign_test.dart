import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/services/stable_sign.dart';

void main() {
  test('counts a stable pose once and rearms after two empty samples', () {
    final state = StableSign();
    String? pose([String label = 'A']) => state.add(label, hasForeground: true);
    expect([pose(), pose(), pose(), pose()], [null, null, 'A', null]);
    state.add(null, hasForeground: true);
    expect(state.current, isNull);
    expect([pose(), pose(), pose()], [null, null, null]);
    expect(state.current, 'A');
    state.add(null, hasForeground: false);
    state.add(null, hasForeground: false);
    expect([pose(), pose(), pose()], [null, null, 'A']);
    expect([pose('B'), pose('B'), pose('B')], [null, null, 'B']);
    state.reset();
    expect(state.current, isNull);
  });
}
