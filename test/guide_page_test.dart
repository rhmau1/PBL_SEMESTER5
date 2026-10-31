import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/main.dart';
import 'package:sign_language/pages/dictionary_page.dart';
import 'package:sign_language/pages/guide_page.dart';

void main() {
  Widget createHost(Widget child) {
    return MaterialApp(
      home: child,
      theme: ThemeData(
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
    );
  }

  Future<void> expectVisible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(finder, findsOneWidget);
  }

  group('GuidePage Content and Completeness', () {
    testWidgets('renders all required guide sections, features, and disclaimer', (
      tester,
    ) async {
      await tester.pumpWidget(
        createHost(
          const GuidePage(),
        ),
      );
      await tester.pumpAndSettle();

      // Title & Header
      expect(find.text('Panduan Penggunaan'), findsOneWidget);
      expect(
        find.textContaining('Belajar Bahasa Isyarat'),
        findsWidgets,
      );

      // Section: Fitur-fitur utama
      expect(find.text('Fitur-Fitur Utama'), findsOneWidget);

      // Fitur 1: Deteksi Video
      expect(
        find.textContaining('Deteksi dengan Video'),
        findsOneWidget,
      );
      expect(find.text('Mode Latihan Bebas'), findsOneWidget);
      expect(find.text('Mode Uji per Huruf'), findsOneWidget);
      expect(
        find.textContaining('24 Abjad Didukung (Tanpa J & Z)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('belum didukung karena membutuhkan deteksi gerakan tangan dinamis'),
        findsOneWidget,
      );

      // Fitur 2: Deteksi Foto
      await expectVisible(
        tester,
        find.textContaining('Deteksi dari Foto (Mode Foto)'),
      );

      // Fitur 3: Upload Gambar
      await expectVisible(
        tester,
        find.textContaining('Deteksi dari Upload Gambar'),
      );

      // Fitur 4: Riwayat Deteksi Otomatis
      await expectVisible(
        tester,
        find.textContaining('Riwayat Deteksi Otomatis'),
      );
      expect(
        find.textContaining('otomatis tersimpan ke halaman Riwayat Deteksi'),
        findsOneWidget,
      );

      // Fitur 5: Kamus Isyarat
      await expectVisible(
        tester,
        find.textContaining('Kamus Isyarat Lengkap (A–Z)'),
      );

      // Disclaimer & Akurasi
      await expectVisible(
        tester,
        find.text('PENTING: DISCLAIMER AKURASI'),
      );
      expect(
        find.text('Model Bisa Saja Salah Mendeteksi'),
        findsOneWidget,
      );
      expect(
        find.textContaining('belum tentu 100% benar'),
        findsOneWidget,
      );
      expect(
        find.textContaining('cek manual di halaman Kamus Isyarat'),
        findsOneWidget,
      );

      // Rekomendasi / Tips
      await expectVisible(
        tester,
        find.text('Tips & Rekomendasi Penggunaan'),
      );
      await expectVisible(
        tester,
        find.textContaining('Pencahayaan yang Terang & Cukup'),
      );
      await expectVisible(
        tester,
        find.textContaining('Area Tangan Terlihat Jelas & Tidak Terpotong'),
      );
      await expectVisible(
        tester,
        find.textContaining('Latar Belakang Sederhana & Tidak Ramai'),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('quick action buttons trigger navigation and pop page', (
      tester,
    ) async {
      int? navigatedIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GuidePage(
                          onNavigate: (index) => navigatedIndex = index,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(GuidePage), findsOneWidget);
      await expectVisible(tester, find.text('Buka Kamus'));
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buka Kamus'));
      await tester.pumpAndSettle();
      expect(find.byType(GuidePage), findsNothing);
      expect(navigatedIndex, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly without overflow across 360 and 411 widths', (
      tester,
    ) async {
      for (final size in const [Size(360, 800), Size(411, 915)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          createHost(
            GuidePage(onNavigate: (_) {}),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(GuidePage), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Scroll all the way down
        await tester.drag(find.byType(ListView), const Offset(0, -1000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Navigation Integration', () {
    testWidgets('Home page card opens GuidePage', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MyApp(cameraEnabled: false)),
      );
      await tester.pumpAndSettle();

      // Drag down on home list to see Panduan action card
      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pumpAndSettle();

      final guideCard = find.text('Panduan Penggunaan');
      expect(guideCard, findsWidgets);

      // Tap on the action card
      await tester.tap(guideCard.first);
      await tester.pumpAndSettle();

      expect(find.byType(GuidePage), findsOneWidget);
      expect(find.text('TENTANG APLIKASI'), findsOneWidget);

      // Back button pops back to Home
      final backButton = find.byTooltip('Kembali');
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(find.byType(GuidePage), findsNothing);
      expect(find.text('LatihIsyarat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home page header help icon opens GuidePage', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MyApp(cameraEnabled: false)),
      );
      await tester.pumpAndSettle();

      final headerHelp = find.byTooltip('Panduan Penggunaan');
      expect(headerHelp, findsOneWidget);

      await tester.tap(headerHelp);
      await tester.pumpAndSettle();

      expect(find.byType(GuidePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DictionaryPage help icon opens GuidePage', (tester) async {
      await tester.pumpWidget(
        createHost(const DictionaryPage()),
      );
      await tester.pumpAndSettle();

      final helpBtn = find.byTooltip('Panduan Penggunaan');
      expect(helpBtn, findsOneWidget);

      await tester.tap(helpBtn);
      await tester.pumpAndSettle();

      expect(find.byType(GuidePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
