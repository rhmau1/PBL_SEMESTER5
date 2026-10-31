import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/main.dart';
import 'package:sign_language/models/history_item.dart';
import 'package:sign_language/providers/history_provider.dart';
import 'package:sign_language/screens/camera_screen.dart';
import 'package:sign_language/services/database_helper.dart';

class _ShellHistoryStore implements HistoryStore {
  final List<HistoryItem> rows = [];

  @override
  Future<List<HistoryItem>> getAllHistory() async => List.of(rows);

  @override
  Future<HistoryItem> insertHistory(HistoryItem item) async {
    final saved = item.copyWith(id: rows.length + 1);
    rows.insert(0, saved);
    return saved;
  }

  @override
  Future<int> deleteHistory(int id) async {
    rows.removeWhere((item) => item.id == id);
    return 1;
  }

  @override
  Future<int> deleteAllHistory() async {
    final count = rows.length;
    rows.clear();
    return count;
  }
}

Future<void> _showApp(WidgetTester tester, {_ShellHistoryStore? store}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        historyStoreProvider.overrideWithValue(store ?? _ShellHistoryStore()),
      ],
      child: const MyApp(cameraEnabled: false),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _navigate(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(BottomNavigationBar), findsOneWidget);
}

void main() {
  testWidgets('Home menu opens camera Video, Foto, and Upload', (tester) async {
    await _showApp(tester);
    expect(find.text('Deteksi Kamera'), findsOneWidget);
    expect(find.text('Kamus Isyarat'), findsOneWidget);
    expect(find.text('Riwayat Deteksi'), findsOneWidget);
    await tester.tap(find.text('Deteksi Kamera'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Foto'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    var camera = tester.widget<CameraScreen>(find.byType(CameraScreen));
    expect(camera.cameraEnabled, isFalse);
    expect(camera.photoMode, isFalse);

    await tester.tap(find.text('Foto'));
    await tester.pumpAndSettle();
    camera = tester.widget<CameraScreen>(find.byType(CameraScreen));
    expect(camera.photoMode, isTrue);
    expect(find.text('Kamera dinonaktifkan untuk pengujian.'), findsOneWidget);

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.byType(CameraScreen), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home upload action opens the Upload detection mode', (
    tester,
  ) async {
    await _showApp(tester);
    final uploadAction = find.text('Deteksi dari upload');
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(uploadAction);
    await tester.pumpAndSettle();
    expect(find.byType(CameraScreen), findsNothing);
    expect(find.text('Uji Gambar'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kamus uses hand photos and opens letter instructions', (
    tester,
  ) async {
    await _showApp(tester);
    await tester.tap(find.text('Kamus Isyarat'));
    await tester.pumpAndSettle();
    expect(find.text('Rumus Sign Language'), findsOneWidget);
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(
      images.any(
        (image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName == 'assets/signs/a.png',
      ),
      isTrue,
    );
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.text('Bentuk tangan huruf A'), findsOneWidget);
    expect(
      find.text('Kepalkan tangan, ibu jari di sisi luar.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared navigation shows persistent history with one nav bar', (
    tester,
  ) async {
    final store = _ShellHistoryStore();
    await store.insertHistory(
      HistoryItem.fromDetection(
        gesture: 'ABC',
        confidence: 0.93,
        source: 'video',
      ),
    );
    await _showApp(tester, store: store);
    await tester.tap(find.text('Riwayat Deteksi'));
    await tester.pumpAndSettle();
    expect(find.text('ABC'), findsOneWidget);
    expect(find.textContaining('Keyakinan model: 93.0%'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    await _navigate(tester, 'Home');
    expect(find.text('Deteksi Kamera'), findsOneWidget);
    await _navigate(tester, 'Deteksi');
    expect(find.byType(CameraScreen), findsOneWidget);
    await _navigate(tester, 'Kamus');
    expect(find.text('Rumus Sign Language'), findsOneWidget);
    await _navigate(tester, 'Riwayat');
    expect(find.text('ABC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
