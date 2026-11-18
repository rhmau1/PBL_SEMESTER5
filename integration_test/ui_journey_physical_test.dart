import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sign_language/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UI journey covers all requested screens', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MyApp(cameraEnabled: true)),
    );

    // Splash screen.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SvgPicture), findsOneWidget);

    // First-launch onboarding: all four steps.
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('onboarding-title-0')), findsOneWidget);
    for (var step = 1; step < 4; step++) {
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('onboarding-title-$step')), findsOneWidget);
    }
    await tester.tap(find.text('Mulai Belajar'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Home.
    expect(find.text('LatihIsyarat'), findsOneWidget);
    expect(find.text('Deteksi Kamera'), findsOneWidget);

    // Detection: video, photo, and upload modes.
    await tester.tap(find.text('Deteksi Kamera'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Foto'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);

    await tester.tap(find.text('Foto'));
    await tester.pumpAndSettle();
    expect(find.text('Foto'), findsOneWidget);

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Upload'), findsOneWidget);

    // Dictionary and history bottom-navigation destinations.
    await tester.tap(find.text('Kamus'));
    await tester.pumpAndSettle();
    expect(find.text('Kamus Isyarat'), findsOneWidget);

    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.text('Riwayat'), findsWidgets);
    expect(find.text('Belum ada riwayat deteksi'), findsOneWidget);

    // Return Home, then open badges/streak and the Home guide.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Progres Belajar & Badges'));
    await tester.pumpAndSettle();
    expect(find.text('My learning progress'), findsOneWidget);
    expect(find.textContaining('streak', skipOffstage: false), findsWidgets);
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Panduan Penggunaan'));
    await tester.pumpAndSettle();
    expect(find.text('Panduan Penggunaan'), findsOneWidget);
    expect(
      find.text('Pelajari cara belajar & memaksimalkan deteksi'),
      findsOneWidget,
    );
  });
}
