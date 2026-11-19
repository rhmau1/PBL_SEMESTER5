/// Emits a letter when at least 3 of the last 4 frames agree on the same label,
/// and emits once per held pose until the hand leaves for 2 consecutive frames.
class StableSign {
  final List<String?> _window = [];
  String? _emitted;
  int _empty = 0;

  String? get current {
    final counts = <String, int>{};
    for (final item in _window) {
      if (item == null) continue;
      final next = (counts[item] ?? 0) + 1;
      if (next >= 3) return item;
      counts[item] = next;
    }
    return null;
  }

  String? add(String? label, {required bool hasForeground}) {
    if (!hasForeground && label == null) {
      _empty++;
      if (_empty >= 2) {
        _emitted = null;
        _window.clear();
      }
      return null;
    }
    _empty = 0;
    _window.add(label);
    if (_window.length > 4) {
      _window.removeAt(0);
    }

    final winner = current;
    if (winner == null || _emitted == winner) return null;
    return _emitted = winner;
  }

  void reset() {
    _window.clear();
    _emitted = null;
    _empty = 0;
  }
}