import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_language/main.dart';
import 'package:sign_language/services/onboarding_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kamus membuka petunjuk huruf A', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(onboardingCompletedPreferenceKey, true);

    await tester.pumpWidget(
      const ProviderScope(child: MyApp(cameraEnabled: false)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kamus Isyarat'));
    await tester.pumpAndSettle();
    expect(find.text('Rumus Sign Language'), findsOneWidget);

    await tester.tap(find.text('A').first);
    await tester.pumpAndSettle();
    expect(find.text('Bentuk tangan huruf A'), findsOneWidget);
  });
}
