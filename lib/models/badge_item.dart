import 'gamification_progress.dart';

enum BadgeTier {
  keepLearning,
  good,
  excellent,
  perfect,
  impossible,
}

class BadgeItem {
  final BadgeTier tier;
  final String id;
  final String title;
  final String requirement;
  final String description;
  final String assetPath;
  final int targetLetters;
  final int targetStreak;

  const BadgeItem({
    required this.tier,
    required this.id,
    required this.title,
    required this.requirement,
    required this.description,
    required this.assetPath,
    this.targetLetters = 0,
    this.targetStreak = 0,
  });

  bool isUnlocked(GamificationProgress progress) {
    return switch (tier) {
      BadgeTier.keepLearning => progress.totalAttempts >= 1,
      BadgeTier.good => progress.practicedLetters.length >= 5,
      BadgeTier.excellent => progress.practicedLetters.length >= 15,
      BadgeTier.perfect => progress.practicedLetters.length >= 24,
      BadgeTier.impossible =>
        progress.practicedLetters.length >= 24 && progress.streakDays >= 7,
    };
  }

  String progressText(GamificationProgress progress) {
    if (isUnlocked(progress)) {
      return switch (tier) {
        BadgeTier.keepLearning => 'First lesson completed',
        BadgeTier.good => '5-letter milestone reached',
        BadgeTier.excellent => '15-letter milestone reached',
        BadgeTier.perfect => 'All 24 letters mastered',
        BadgeTier.impossible => 'All letters + 7-day streak achieved',
      };
    }

    final letterCount = progress.practicedLetters.length;
    return switch (tier) {
      BadgeTier.keepLearning => '0 / 1 session completed',
      BadgeTier.good => '$letterCount / 5 letters · ${5 - letterCount} to go',
      BadgeTier.excellent =>
        '$letterCount / 15 letters · ${15 - letterCount} to go',
      BadgeTier.perfect =>
        '$letterCount / 24 letters · ${24 - letterCount} to go',
      BadgeTier.impossible =>
        '$letterCount / 24 letters · ${progress.streakDays} / 7 days',
    };
  }

  static const List<BadgeItem> allBadges = [
    BadgeItem(
      tier: BadgeTier.keepLearning,
      id: 'keep_learning',
      title: 'Keep learning',
      requirement: 'Complete your first lesson.',
      description:
          'Awal yang bagus! Kamu telah menyelesaikan sesi latihan pertamamu.',
      assetPath: 'assets/badges/keep_learning.svg',
    ),
    BadgeItem(
      tier: BadgeTier.good,
      id: 'good',
      title: 'Good',
      requirement: 'Learn 5 alphabet letters.',
      description:
          'Hebat! Kamu sudah mencoba 5 huruf alfabet berbeda.',
      assetPath: 'assets/badges/good.svg',
      targetLetters: 5,
    ),
    BadgeItem(
      tier: BadgeTier.excellent,
      id: 'excellent',
      title: 'Excellent',
      requirement: 'Learn 15 alphabet letters.',
      description:
          'Luar biasa! Kamu telah mempelajari 15 huruf alfabet. Itu 15 cara baru untuk terkoneksi.',
      assetPath: 'assets/badges/excellent.svg',
      targetLetters: 15,
    ),
    BadgeItem(
      tier: BadgeTier.perfect,
      id: 'perfect',
      title: 'Perfect',
      requirement: 'Learn all 24 alphabet letters.',
      description:
          'Sempurna! Kamu telah melatih seluruh 24 huruf yang tersedia pada sistem.',
      assetPath: 'assets/badges/perfect.svg',
      targetLetters: 24,
    ),
    BadgeItem(
      tier: BadgeTier.impossible,
      id: 'impossible',
      title: 'Impossible',
      requirement: 'Learn all 24 letters + reach a 7-day streak.',
      description:
          'Pencapaian legendaris! Kamu menguasai seluruh huruf dan konsisten berlatih selama 7 hari.',
      assetPath: 'assets/badges/impossible.svg',
      targetLetters: 24,
      targetStreak: 7,
    ),
  ];
}
