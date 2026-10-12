import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_item.dart';
import '../services/database_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SharedPreferences provider – berguna untuk menyimpan flag / setting ringan.
// ─────────────────────────────────────────────────────────────────────────────

/// Provider untuk instance SharedPreferences.
/// Harus di-override di main.dart agar sudah terinisialisasi saat app start.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider harus di-override di ProviderScope.',
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// History Notifier + Provider  (Riverpod StateNotifier)
// ─────────────────────────────────────────────────────────────────────────────

/// State notifier yang mengelola list [HistoryItem].
/// Semua perubahan langsung di-sync ke SQLite via [DatabaseHelper].
class HistoryNotifier extends StateNotifier<AsyncValue<List<HistoryItem>>> {
  final DatabaseHelper _db;

  HistoryNotifier(this._db) : super(const AsyncValue.loading()) {
    loadHistory();
  }

  /// Muat semua history dari SQLite.
  Future<void> loadHistory() async {
    try {
      state = const AsyncValue.loading();
      final items = await _db.getAllHistory();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Tambah satu record baru ke history.
  Future<void> addHistory(HistoryItem item) async {
    try {
      final inserted = await _db.insertHistory(item);
      // Tambahkan di awal list (terbaru di atas)
      state = AsyncValue.data([inserted, ...state.value ?? []]);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Hapus satu record berdasarkan id.
  Future<void> removeHistory(int id) async {
    try {
      await _db.deleteHistory(id);
      final current = state.value ?? [];
      state = AsyncValue.data(current.where((h) => h.id != id).toList());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Hapus semua history.
  Future<void> clearAllHistory() async {
    try {
      await _db.deleteAllHistory();
      state = const AsyncValue.data([]);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Provider utama untuk history. Gunakan `ref.watch(historyProvider)` di widget.
final historyProvider =
    StateNotifierProvider<HistoryNotifier, AsyncValue<List<HistoryItem>>>(
  (ref) => HistoryNotifier(DatabaseHelper.instance),
);
