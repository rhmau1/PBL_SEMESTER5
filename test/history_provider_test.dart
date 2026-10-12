import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/models/history_item.dart';
import 'package:sign_language/providers/history_provider.dart';
import 'package:sign_language/services/database_helper.dart';

HistoryItem result(String text) =>
    HistoryItem.fromDetection(gesture: text, confidence: 0.94, source: 'video');

class FakeHistoryStore implements HistoryStore {
  final List<HistoryItem> rows = [];
  Completer<void>? firstReadBarrier;
  bool failNextInsert = false;
  bool failNextRead = false;
  bool failDeletes = false;
  int _nextId = 1;
  int _reads = 0;

  @override
  Future<List<HistoryItem>> getAllHistory() async {
    if (failNextRead) {
      failNextRead = false;
      throw StateError('temporary read failure');
    }
    final snapshot = rows.reversed.toList();
    if (_reads++ == 0 && firstReadBarrier != null) {
      await firstReadBarrier!.future;
    }
    return snapshot;
  }

  @override
  Future<HistoryItem> insertHistory(HistoryItem item) async {
    if (failNextInsert) {
      failNextInsert = false;
      throw StateError('disk full');
    }
    final inserted = item.copyWith(id: _nextId++);
    rows.add(inserted);
    return inserted;
  }

  @override
  Future<int> deleteHistory(int id) async {
    if (failDeletes) throw StateError('database locked');
    final before = rows.length;
    rows.removeWhere((item) => item.id == id);
    return before - rows.length;
  }

  @override
  Future<int> deleteAllHistory() async {
    if (failDeletes) throw StateError('database locked');
    final count = rows.length;
    rows.clear();
    return count;
  }
}

void main() {
  test(
    'startup load cannot overwrite concurrent additions and removal',
    () async {
      final db = FakeHistoryStore()..firstReadBarrier = Completer<void>();
      await db.insertHistory(result('OLD'));
      final notifier = HistoryNotifier(db);
      addTearDown(notifier.dispose);
      await Future<void>.delayed(Duration.zero);
      final firstSave = notifier.addHistory(result('ABC'));
      final secondSave = notifier.addHistory(result('DEF'));
      final deletion = notifier.removeHistory(1);
      db.firstReadBarrier!.complete();
      await Future.wait([firstSave, secondSave, deletion]);
      expect(notifier.state.requireValue.map((item) => item.gesture), [
        'DEF',
        'ABC',
      ]);
      expect(db.rows.map((item) => item.gesture), ['ABC', 'DEF']);
    },
  );

  test('simultaneous save and clear obey call order', () async {
    final db = FakeHistoryStore();
    final notifier = HistoryNotifier(db);
    addTearDown(notifier.dispose);
    await Future.wait([
      notifier.addHistory(result('ABC')),
      notifier.clearAllHistory(),
      notifier.addHistory(result('XYZ')),
    ]);
    expect(notifier.state.requireValue.single.gesture, 'XYZ');
    expect(db.rows.single.gesture, 'XYZ');
  });

  test('failed save is reported and does not block future saves', () async {
    final db = FakeHistoryStore();
    final notifier = HistoryNotifier(db);
    addTearDown(notifier.dispose);
    await notifier.loadHistory();
    db.failNextInsert = true;
    await expectLater(notifier.addHistory(result('BAD')), throwsStateError);
    expect(notifier.state.hasError, isTrue);
    expect(db.rows, isEmpty);
    await notifier.addHistory(result('GOOD'));
    expect(notifier.state.requireValue.single.gesture, 'GOOD');
  });

  test(
    'failed delete preserves persistent data and future reload recovers',
    () async {
      final db = FakeHistoryStore();
      final notifier = HistoryNotifier(db);
      addTearDown(notifier.dispose);
      await notifier.addHistory(result('ABC'));
      db.failDeletes = true;
      await expectLater(notifier.removeHistory(1), throwsStateError);
      expect(db.rows.single.gesture, 'ABC');
      await notifier.loadHistory();
      expect(notifier.state.requireValue.single.gesture, 'ABC');
    },
  );

  test('another notifier restores the persistent sequence and score', () async {
    final db = FakeHistoryStore();
    final first = HistoryNotifier(db);
    await first.addHistory(result('HELLO'));
    first.dispose();
    final restored = HistoryNotifier(db);
    addTearDown(restored.dispose);
    await restored.loadHistory();
    expect(restored.state.requireValue.single.gesture, 'HELLO');
    expect(restored.state.requireValue.single.confidence, 0.94);
  });

  test('committed save stays successful when follow-up read fails', () async {
    final db = FakeHistoryStore();
    final notifier = HistoryNotifier(db);
    addTearDown(notifier.dispose);
    await notifier.loadHistory();
    db.failNextRead = true;
    await notifier.addHistory(result('ABC'));
    expect(notifier.state.hasError, isFalse);
    expect(notifier.state.requireValue.single.gesture, 'ABC');
    expect(db.rows, hasLength(1));
    await notifier.loadHistory();
    expect(notifier.state.requireValue.single.gesture, 'ABC');
    expect(db.rows, hasLength(1));
  });

  test('committed deletes stay successful when follow-up reads fail', () async {
    final db = FakeHistoryStore();
    final notifier = HistoryNotifier(db);
    addTearDown(notifier.dispose);
    await notifier.addHistory(result('ABC'));
    await notifier.addHistory(result('XYZ'));
    db.failNextRead = true;
    await notifier.removeHistory(1);
    expect(notifier.state.hasError, isFalse);
    expect(notifier.state.requireValue.single.gesture, 'XYZ');
    expect(db.rows.single.gesture, 'XYZ');
    db.failNextRead = true;
    await notifier.clearAllHistory();
    expect(notifier.state.hasError, isFalse);
    expect(notifier.state.requireValue, isEmpty);
    expect(db.rows, isEmpty);
  });
}
