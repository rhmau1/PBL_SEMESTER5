/// Emits a letter after three matching samples and once per held pose.
class StableSign {
  String? _candidate;
  String? _emitted;
  int _matches = 0;
  int _empty = 0;

  String? get current => _matches >= 3 ? _candidate : null;

  String? add(String? label, {required bool hasForeground}) {
    if (label == null) {
      _candidate = null;
      _matches = 0;
      _empty = hasForeground ? 0 : _empty + 1;
      if (_empty >= 2) _emitted = null;
      return null;
    }
    _empty = 0;
    if (_candidate == label) {
      if (_matches < 3) _matches++;
    } else {
      _candidate = label;
      _matches = 1;
    }
    if (_matches < 3 || _emitted == label) return null;
    return _emitted = label;
  }

  void reset() {
    _candidate = null;
    _emitted = null;
    _matches = 0;
    _empty = 0;
  }
}
