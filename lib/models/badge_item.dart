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
        BadgeTier.keepLearning => 'Sesi pertama selesai',
        BadgeTier.good => 'Pencapaian 5 huruf tercapai',
        BadgeTier.excellent => 'Pencapaian 15 huruf tercapai',
        BadgeTier.perfect => 'Seluruh 24 huruf dikuasai',
        BadgeTier.impossible => 'Semua huruf + streak 7 hari tercapai',
      };
    }

    final letterCount = progress.practicedLetters.length;
    return switch (tier) {
      BadgeTier.keepLearning => '0 / 1 sesi selesai',
      BadgeTier.good => '$letterCount / 5 huruf · sisa ${5 - letterCount}',
      BadgeTier.excellent =>
        '$letterCount / 15 huruf · sisa ${15 - letterCount}',
      BadgeTier.perfect =>
        '$letterCount / 24 huruf · sisa ${24 - letterCount}',
      BadgeTier.impossible =>
        '$letterCount / 24 huruf · ${progress.streakDays} / 7 hari',
    };
  }

  static const List<BadgeItem> allBadges = [
    BadgeItem(
      tier: BadgeTier.keepLearning,
      id: 'keep_learning',
      title: 'Terus Belajar',
      requirement: 'Selesaikan sesi latihan pertamamu.',
      description: 'Selesaikan sesi latihan pertamamu.',
      assetPath: 'assets/badges/keep_learning.svg',
    ),
    BadgeItem(
      tier: BadgeTier.good,
      id: 'good',
      title: 'Bagus',
      requirement: 'Pelajari 5 huruf alfabet.',
      description:
          'Kamu telah mempelajari 5 huruf alfabet. Selangkah lebih dekat untuk berkomunikasi dengan lancar.',
      assetPath: 'assets/badges/good.svg',
      targetLetters: 5,
    ),
    BadgeItem(
      tier: BadgeTier.excellent,
      id: 'excellent',
      title: 'Luar Biasa',
      requirement: 'Pelajari 15 huruf alfabet.',
      description:
          'Kamu telah mempelajari 15 huruf alfabet. Itu 15 cara baru untuk terhubung.',
      assetPath: 'assets/badges/excellent.svg',
      targetLetters: 15,
    ),
    BadgeItem(
      tier: BadgeTier.perfect,
      id: 'perfect',
      title: 'Sempurna',
      requirement: 'Kuasai seluruh 24 huruf alfabet.',
      description:
          'Kamu telah mempelajari seluruh 24 huruf alfabet. Dedikasi dan penguasaan sejati!',
      assetPath: 'assets/badges/perfect.svg',
      targetLetters: 24,
    ),
    BadgeItem(
      tier: BadgeTier.impossible,
      id: 'impossible',
      title: 'Mustahil',
      requirement: 'Kuasai seluruh 24 huruf + streak 7 hari.',
      description:
          'Kamu telah menguasai seluruh 24 huruf dan mempertahankan streak 7 hari. Sungguh pencapaian legendaris!',
      assetPath: 'assets/badges/impossible.svg',
      targetLetters: 24,
      targetStreak: 7,
    ),
  ];
}
