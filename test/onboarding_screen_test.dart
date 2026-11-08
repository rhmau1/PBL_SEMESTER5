import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_language/screens/onboarding_screen.dart';
import 'package:sign_language/services/onboarding_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('onboarding has four slides and completes into the home screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          nextScreen: const Scaffold(body: Text('Beranda siap')),
        ),
      ),
    );

    expect(
      find.text('Belajar isyarat, selangkah demi selangkah'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Slide 1 dari 4'), findsOneWidget);
    for (var index = 1; index < 4; index++) {
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('onboarding-title-$index')), findsOneWidget);
    }

    expect(find.text('Mulai Belajar'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();

    expect(find.text('Beranda siap'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(onboardingCompletedPreferenceKey), isTrue);
  });

  testWidgets('onboarding can be skipped and remembered', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          nextScreen: const Scaffold(body: Text('Beranda siap')),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.text('Beranda siap'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(onboardingCompletedPreferenceKey), isTrue);
  });

  testWidgets('onboarding slides can be changed with a swipe', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          nextScreen: const Scaffold(body: Text('Beranda siap')),
        ),
      ),
    );

    await tester.fling(
      find.byKey(const ValueKey('onboarding-pages')),
      const Offset(-500, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('onboarding-title-1')), findsOneWidget);
    expect(find.bySemanticsLabel('Slide 2 dari 4'), findsOneWidget);
  });

  testWidgets('onboarding visuals fit a compact phone width', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          nextScreen: const Scaffold(body: Text('Beranda siap')),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (var index = 1; index < 4; index++) {
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pumpAndSettle();
      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Slide $index');
    }
  });
}
