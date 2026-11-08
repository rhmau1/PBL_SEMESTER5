import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/screens/splash_screen.dart';

void main() {
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
    expect(find.text('LatihIsyarat'), findsOneWidget);
    expect(find.text('Home destination'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Home destination'), findsOneWidget);
  });
}
