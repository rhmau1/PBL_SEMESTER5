import 'badge_item.dart';
import 'history_item.dart';

class GamificationProgress {
  final int totalAttempts;
  final Set<String> practicedLetters;
  final int streakDays;
  final int totalXp;
  final List<HistoryItem> recentHistory;
  final List<String> practicedDates;

  const GamificationProgress({
    required this.totalAttempts,
    required this.practicedLetters,
    required this.streakDays,
    required this.totalXp,
    required this.recentHistory,
    required this.practicedDates,
  });

  const GamificationProgress.empty()
      : totalAttempts = 0,
        practicedLetters = const {},
        streakDays = 0,
        totalXp = 0,
        recentHistory = const [],
        practicedDates = const [];

  List<BadgeItem> get unlockedBadges =>
      BadgeItem.allBadges.where((b) => b.isUnlocked(this)).toList();

  List<BadgeItem> get lockedBadges =>
      BadgeItem.allBadges.where((b) => !b.isUnlocked(this)).toList();

  BadgeItem? get nextBadge {
    final locked = lockedBadges;
    return locked.isNotEmpty ? locked.first : null;
  }

  int get unlockedCount => unlockedBadges.length;
  int get totalBadgesCount => BadgeItem.allBadges.length;

  int get percentageLetters =>
      ((practicedLetters.length / 24) * 100).clamp(0, 100).round();

  bool isLetterPracticed(String letter) =>
      practicedLetters.contains(letter.toUpperCase());

  factory GamificationProgress.fromHistory(List<HistoryItem> history) {
    if (history.isEmpty) {
      return const GamificationProgress.empty();
    }

    final letters = <String>{};
    final letterRegex = RegExp(r'[A-Za-z]');

    for (final item in history) {
      for (final char in item.gesture.split('')) {
        if (letterRegex.hasMatch(char)) {
          letters.add(char.toUpperCase());
        }
      }
    }

    // Extract unique dates sorted descending
    final rawDates = <String>{};
    for (final item in history) {
      if (item.date.isNotEmpty) {
        rawDates.add(item.date);
      }
    }
    final sortedDates = rawDates.toList()..sort((a, b) => b.compareTo(a));

    final streak = _calculateStreak(sortedDates);
    final xp = (history.length * 20) + (letters.length * 20);

    return GamificationProgress(
      totalAttempts: history.length,
      practicedLetters: letters,
      streakDays: streak,
      totalXp: xp,
      recentHistory: history.take(5).toList(),
      practicedDates: sortedDates,
    );
  }

  static int _calculateStreak(List<String> sortedDescDates) {
    if (sortedDescDates.isEmpty) return 0;

    final parsedDates = <DateTime>[];
    for (final dateStr in sortedDescDates) {
      try {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          parsedDates.add(DateTime(year, month, day));
        }
      } catch (_) {
        // Skip unparseable date formats
      }
    }

    if (parsedDates.isEmpty) return sortedDescDates.length;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final mostRecent = parsedDates.first;
    // Streak is active if most recent is today or yesterday
    if (mostRecent.isBefore(yesterday)) {
      return 0;
    }

    var streak = 1;
    var current = mostRecent;

    for (var i = 1; i < parsedDates.length; i++) {
      final prev = parsedDates[i];
      final difference = current.difference(prev).inDays;
      if (difference == 1) {
        streak++;
        current = prev;
      } else if (difference == 0) {
        // Same day, continue
        continue;
      } else {
        break;
      }
    }

    return streak;
  }
}
