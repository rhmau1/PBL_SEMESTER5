import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_item.dart';
import '../services/database_helper.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider harus di-override di ProviderScope.',
  );
});

final historyStoreProvider = Provider<HistoryStore>(
  (ref) => DatabaseHelper.instance,
);

/// Operasi diurutkan: load saat startup tidak dapat menimpa hasil save terbaru.
/// Future gagal tetap dilempar ke pemanggil agar UI bisa menampilkan kegagalan.
class HistoryNotifier extends StateNotifier<AsyncValue<List<HistoryItem>>> {
  final HistoryStore _db;
  Future<void> _pending = Future<void>.value();
  List<HistoryItem> _snapshot = const [];

  HistoryNotifier(this._db) : super(const AsyncValue.loading()) {
    unawaited(loadHistory().catchError((Object _, StackTrace _) {}));
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) async {
      try {
        await operation();
      } catch (error, stack) {
        if (mounted) state = AsyncValue.error(error, stack);
        Error.throwWithStackTrace(error, stack);
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _publishAll() async {
    final items = await _db.getAllHistory();
    _publishSnapshot(items);
  }

  void _publishSnapshot(List<HistoryItem> items) {
    _snapshot = List<HistoryItem>.unmodifiable(items);
    if (mounted) state = AsyncValue.data(_snapshot);
  }

  Future<void> _refreshAfterCommit() async {
    try {
      await _publishAll();
    } catch (_) {
      // The write has already committed. Keep its known result instead of
      // reporting a failed save/delete that would invite duplicate retries.
      // An explicit refresh can reload other rows when reading recovers.
    }
  }

  Future<void> loadHistory() => _enqueue(_publishAll);

  Future<void> addHistory(HistoryItem item) => _enqueue(() async {
    final inserted = await _db.insertHistory(item);
    _publishSnapshot([inserted, ..._snapshot]);
    await _refreshAfterCommit();
  });

  Future<void> removeHistory(int id) => _enqueue(() async {
    await _db.deleteHistory(id);
    _publishSnapshot(_snapshot.where((item) => item.id != id).toList());
    await _refreshAfterCommit();
  });

  Future<void> clearAllHistory() => _enqueue(() async {
    await _db.deleteAllHistory();
    _publishSnapshot(const []);
    await _refreshAfterCommit();
  });
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, AsyncValue<List<HistoryItem>>>(
      (ref) => HistoryNotifier(ref.watch(historyStoreProvider)),
    );
