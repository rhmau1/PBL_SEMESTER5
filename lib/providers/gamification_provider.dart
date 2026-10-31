import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/badge_item.dart';
import '../models/gamification_progress.dart';
import 'history_provider.dart';

final gamificationProvider = Provider<GamificationProgress>((ref) {
  final historyAsync = ref.watch(historyProvider);
  final items = historyAsync.valueOrNull ?? const [];
  return GamificationProgress.fromHistory(items);
});

class NewlyUnlockedBadgesNotifier extends StateNotifier<Set<String>> {
  NewlyUnlockedBadgesNotifier() : super(const {});

  void markBadgeSeen(String badgeId) {
    state = {...state, badgeId};
  }

  void markAllSeen(Iterable<String> badgeIds) {
    state = {...state, ...badgeIds};
  }

  bool isNewlyUnlocked(BadgeItem badge, GamificationProgress progress) {
    return badge.isUnlocked(progress) && !state.contains(badge.id);
  }
}

final seenBadgesProvider =
    StateNotifierProvider<NewlyUnlockedBadgesNotifier, Set<String>>((ref) {
  return NewlyUnlockedBadgesNotifier();
});
