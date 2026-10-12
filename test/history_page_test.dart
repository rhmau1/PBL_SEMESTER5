import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/models/history_item.dart';
import 'package:sign_language/pages/history_page.dart';
import 'package:sign_language/providers/history_provider.dart';
import 'package:sign_language/services/database_helper.dart';

class _HistoryStore implements HistoryStore {
  final List<HistoryItem> rows = [
    HistoryItem.fromDetection(
      gesture: 'ABC',
      confidence: 0.95,
      source: 'video',
      videoPath: '/recordings/session.mp4',
    ).copyWith(id: 1),
  ];
  bool failDeletes = false;

  @override
  Future<List<HistoryItem>> getAllHistory() async => List.of(rows);

  @override
  Future<HistoryItem> insertHistory(HistoryItem item) async {
    rows.add(item);
    return item;
  }

  @override
  Future<int> deleteHistory(int id) async {
    if (failDeletes) throw StateError('disk error');
    rows.removeWhere((item) => item.id == id);
    return 1;
  }

  @override
  Future<int> deleteAllHistory() async {
    if (failDeletes) throw StateError('disk error');
    final count = rows.length;
    rows.clear();
    return count;
  }
}

Future<void> _showHistory(WidgetTester tester, _HistoryStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [historyStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(home: HistoryPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('history shows full sequence, source, score and detail', (
    tester,
  ) async {
    await _showHistory(tester, _HistoryStore());
    expect(find.text('ABC'), findsOneWidget);
    expect(find.textContaining('Latihan bebas'), findsOneWidget);
    expect(find.textContaining('Keyakinan model: 95.0%'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    await tester.tap(find.text('ABC'));
    await tester.pumpAndSettle();
    expect(find.text('Rata-rata keyakinan huruf: 95.0%'), findsOneWidget);
    expect(find.text('/recordings/session.mp4'), findsOneWidget);
  });

  testWidgets('delete confirmation waits for persistence before success', (
    tester,
  ) async {
    final store = _HistoryStore();
    await _showHistory(tester, store);
    await tester.tap(find.byTooltip('Hapus riwayat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Hapus'));
    await tester.pumpAndSettle();
    expect(store.rows, isEmpty);
    expect(find.text('Riwayat telah dihapus'), findsOneWidget);
    expect(find.text('Belum ada riwayat deteksi'), findsOneWidget);
  });

  testWidgets('failed delete keeps record and displays no success message', (
    tester,
  ) async {
    final store = _HistoryStore()..failDeletes = true;
    await _showHistory(tester, store);
    await tester.tap(find.byTooltip('Hapus semua riwayat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Hapus'));
    await tester.pumpAndSettle();
    expect(store.rows.single.gesture, 'ABC');
    expect(find.text('Riwayat gagal dihapus. Coba lagi.'), findsOneWidget);
    expect(find.text('Semua riwayat telah dihapus'), findsNothing);
  });
}
