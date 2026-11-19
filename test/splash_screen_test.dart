import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/screens/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('splash shows the mascot and opens the destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          duration: const Duration(seconds: 1),
          nextScreen: const Scaffold(body: Text('Home destination')),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    expect(find.text('Home destination'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Home destination'), findsOneWidget);
  });

  testWidgets('first launch opens onboarding after the logo splash', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          duration: const Duration(seconds: 1),
          nextScreen: const Scaffold(body: Text('Home destination')),
          firstLaunchScreen: const Scaffold(body: Text('Pengenalan awal')),
        ),
      ),
    );
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(Text), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Pengenalan awal'), findsOneWidget);
    expect(find.text('Home destination'), findsNothing);
  });

  testWidgets('completed onboarding opens home after the logo splash', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          duration: const Duration(seconds: 1),
          nextScreen: const Scaffold(body: Text('Home destination')),
          firstLaunchScreen: const Scaffold(body: Text('Pengenalan awal')),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Home destination'), findsOneWidget);
    expect(find.text('Pengenalan awal'), findsNothing);
  });
}
