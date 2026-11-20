import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sign_language/main.dart';
import 'package:sign_language/models/history_item.dart';
import 'package:sign_language/services/database_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MyApp(cameraEnabled: true)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> completeOnboarding(WidgetTester tester) async {
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final next = find.byKey(const ValueKey('onboarding-next'));
    if (next.evaluate().isNotEmpty) {
      for (var step = 0; step < 3; step++) {
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Mulai Belajar'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  }

  testWidgets('1. Splash dan onboarding empat langkah', (tester) async {
    await openApp(tester);
    expect(find.byType(SvgPicture), findsOneWidget);
    await completeOnboarding(tester);
    expect(find.text('LatihIsyarat'), findsOneWidget);
  });

  testWidgets('2. Beranda dan deteksi kamus, video, foto, upload', (
    tester,
  ) async {
    await openApp(tester);
    await completeOnboarding(tester);
    expect(find.text('Deteksi Kamera'), findsOneWidget);

    await tester.tap(find.text('Deteksi Kamera'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Video'), findsOneWidget);

    await tester.tap(find.text('Foto'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Foto'), findsWidgets);

    await tester.tap(find.text('Upload'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Upload'), findsWidgets);

    await tester.tap(find.text('Kamus'));
    await tester.pumpAndSettle();
    expect(find.text('Kamus Isyarat'), findsOneWidget);
  });

  testWidgets('3. Kamus membuka detail salah satu huruf', (tester) async {
    await openApp(tester);
    await completeOnboarding(tester);
    await tester.tap(find.text('Kamus'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dictionary-letter-A')));
    await tester.pumpAndSettle();
    expect(find.text('PANDUAN ASL'), findsOneWidget);
    expect(find.text('Bentuk tangan huruf A'), findsOneWidget);
    expect(find.text('Paham'), findsOneWidget);
  });

  testWidgets('4. Riwayat membuka detail dan menghapus item', (tester) async {
    await DatabaseHelper.instance.deleteAllHistory();
    await DatabaseHelper.instance.insertHistory(
      const HistoryItem(
        gesture: 'EspressoA',
        accuracy: '92.5%',
        date: '2026-11-20',
        time: '19:40',
        confidence: 0.925,
        source: 'photo',
        modelId: 'svm_hog',
      ),
    );

    await openApp(tester);
    await completeOnboarding(tester);
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('EspressoA'), findsOneWidget);

    await tester.tap(find.text('EspressoA'));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL DETEKSI'), findsOneWidget);
    expect(find.text('Sumber Media'), findsOneWidget);
    expect(find.text('Waktu Deteksi'), findsOneWidget);
    expect(find.text('Model Deteksi'), findsOneWidget);

    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('EspressoA'));
    await tester.pumpAndSettle();
    expect(find.text('Hapus riwayat?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Hapus'));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada riwayat deteksi'), findsOneWidget);
  });

  testWidgets('5. Progress membuka card badge dan View all badges', (
    tester,
  ) async {
    await openApp(tester);
    await completeOnboarding(tester);
    await tester.tap(find.byTooltip('Progres Belajar & Badges'));
    await tester.pumpAndSettle();
    expect(find.text('My learning progress'), findsOneWidget);
    expect(find.textContaining('streak'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Your badges'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(
      find.byKey(const ValueKey('progress-badge-card-keep_learning')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Keep learning'), findsWidgets);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('progress-view-all-badges')));
    await tester.pumpAndSettle();
    expect(find.text('My badges'), findsOneWidget);
  });

  testWidgets('6. Deteksi memilih latihan bebas dan uji per huruf', (
    tester,
  ) async {
    await openApp(tester);
    await completeOnboarding(tester);
    await tester.tap(find.text('Deteksi Kamera'));
    await tester.pump(const Duration(seconds: 2));

    final dropdown = find.byKey(const ValueKey('detection-mode-dropdown'));
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('MODE UJI: HURUF A').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('MODE UJI: HURUF A'), findsOneWidget);

    await tester.tap(dropdown);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('MODE: LATIHAN BEBAS').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('MODE: LATIHAN BEBAS'), findsOneWidget);
  });
}
