import 'package:shared_preferences/shared_preferences.dart';

const onboardingCompletedPreferenceKey = 'onboarding_completed';

Future<bool> hasCompletedOnboarding() async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.getBool(onboardingCompletedPreferenceKey) ?? false;
}

Future<void> markOnboardingCompleted() async {
  final preferences = await SharedPreferences.getInstance();
  final saved = await preferences.setBool(
    onboardingCompletedPreferenceKey,
    true,
  );
  if (!saved) {
    throw StateError('Status pengenalan awal gagal disimpan.');
  }
}
