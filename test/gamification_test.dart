import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/main.dart';
import 'package:sign_language/models/gamification_progress.dart';
import 'package:sign_language/models/history_item.dart';
import 'package:sign_language/pages/badges_page.dart';
import 'package:sign_language/pages/learning_progress_page.dart';
import 'package:sign_language/providers/history_provider.dart';
import 'package:sign_language/services/database_helper.dart';

class _FakeHistoryStore implements HistoryStore {
  final List<HistoryItem> rows;
  _FakeHistoryStore([this.rows = const []]);

  @override
  Future<List<HistoryItem>> getAllHistory() async => List.of(rows);
  @override
  Future<HistoryItem> insertHistory(HistoryItem item) async => item;
  @override
  Future<int> deleteHistory(int id) async => 1;
  @override
  Future<int> deleteAllHistory() async => rows.length;
}

void main() {
  group('GamificationProgress Unit Tests', () {
    test('empty history gives 0 progress and 0 badges', () {
      final progress = GamificationProgress.fromHistory([]);
      expect(progress.totalAttempts, 0);
      expect(progress.practicedLetters, isEmpty);
      expect(progress.streakDays, 0);
      expect(progress.unlockedCount, 0);
      expect(progress.unlockedBadges, isEmpty);
      expect(progress.nextBadge?.id, 'keep_learning');
    });

    test('1 detection unlocks Keep learning badge', () {
      final items = [
        HistoryItem.fromDetection(
          gesture: 'A',
          confidence: 0.95,
          source: 'video',
        ),
      ];
      final progress = GamificationProgress.fromHistory(items);
      expect(progress.totalAttempts, 1);
      expect(progress.practicedLetters, {'A'});
      expect(progress.unlockedCount, 1);
      expect(progress.unlockedBadges.first.id, 'keep_learning');
      expect(progress.nextBadge?.id, 'good');
    });

    test('5 unique letters unlock Good badge', () {
      final items = ['A', 'B', 'C', 'D', 'E'].map((letter) {
        return HistoryItem.fromDetection(
          gesture: letter,
          confidence: 0.9,
          source: 'photo',
        );
      }).toList();

      final progress = GamificationProgress.fromHistory(items);
      expect(progress.practicedLetters.length, 5);
      expect(progress.unlockedCount, 2); // keep_learning + good
      expect(
        progress.unlockedBadges.map((b) => b.id).toSet(),
        {'keep_learning', 'good'},
      );
      expect(progress.nextBadge?.id, 'excellent');
    });

    test('15 unique letters unlock Excellent badge', () {
      final letters = 'ABCDEFGHIKLMNOP'.split(''); // 15 letters
      final items = letters.map((l) {
        return HistoryItem.fromDetection(
          gesture: l,
          confidence: 0.9,
          source: 'video',
        );
      }).toList();

      final progress = GamificationProgress.fromHistory(items);
      expect(progress.practicedLetters.length, 15);
      expect(progress.unlockedCount, 3); // keep_learning + good + excellent
      expect(
        progress.unlockedBadges.map((b) => b.id).toSet(),
        {'keep_learning', 'good', 'excellent'},
      );
      expect(progress.nextBadge?.id, 'perfect');
    });

    test('24 letters unlock Perfect badge', () {
      final letters = 'ABCDEFGHIKLMNOPQRSTUVWXY'.split(''); // 24 letters
      final items = letters.map((l) {
        return HistoryItem.fromDetection(
          gesture: l,
          confidence: 0.9,
          source: 'video',
        );
      }).toList();

      final progress = GamificationProgress.fromHistory(items);
      expect(progress.practicedLetters.length, 24);
      expect(progress.unlockedCount, 4); // keep, good, excellent, perfect
      expect(
        progress.unlockedBadges.map((b) => b.id).toSet(),
        {'keep_learning', 'good', 'excellent', 'perfect'},
      );
      expect(progress.nextBadge?.id, 'impossible');
    });
  });

  group('BadgesPage UI Tests', () {
    testWidgets('renders all 5 badges and progress metrics', (tester) async {
      final items = [
        HistoryItem.fromDetection(
          gesture: 'ABCDE',
          confidence: 0.92,
          source: 'video',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            historyStoreProvider.overrideWithValue(_FakeHistoryStore(items)),
          ],
          child: const MaterialApp(
            home: BadgesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header
      expect(find.text('Small signs. Big wins.'), findsOneWidget);
      expect(find.text('2 / 5'), findsOneWidget); // keep_learning + good

      // Badge Titles visible at top
      expect(find.text('Keep learning'), findsWidgets);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Excellent'), findsOneWidget);

      // Status pills
      expect(find.textContaining('Earned'), findsWidgets);
      expect(find.text('Locked'), findsWidgets);
      // Tapping an unlocked badge opens details
      await tester.tap(find.text('Good'));
      await tester.pumpAndSettle();

      expect(find.text('Your achievement'), findsOneWidget);
      expect(find.text('BADGE UNLOCKED'), findsOneWidget);
      expect(find.textContaining('A little practice'), findsOneWidget);

      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();

      // Scroll down to check remaining badges
      await tester.scrollUntilVisible(
        find.text('Perfect'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Perfect'), findsOneWidget);

      // Tapping a locked badge shows locked details
      await tester.tap(find.text('Perfect'));
      await tester.pumpAndSettle();

      expect(find.text('Badge details'), findsOneWidget);
      expect(find.text('BADGE LOCKED'), findsOneWidget);
      expect(find.textContaining('Tantangan Menanti'), findsOneWidget);

      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Impossible'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Impossible'), findsOneWidget);
    });
  });

  group('LearningProgressPage UI Tests', () {
    testWidgets('renders alphabet journey, streak, and recent sessions', (
      tester,
    ) async {
      final items = [
        HistoryItem.fromDetection(
          gesture: 'AB',
          confidence: 0.9,
          source: 'video',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            historyStoreProvider.overrideWithValue(_FakeHistoryStore(items)),
          ],
          child: const MaterialApp(
            home: LearningProgressPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My learning progress'), findsOneWidget);
      expect(find.text('Your alphabet journey'), findsOneWidget);
      expect(find.textContaining('letters learned'), findsOneWidget);

      // Alphabet pills
      expect(find.text('A'), findsWidgets);
      expect(find.text('B'), findsWidgets);
      expect(find.text('Z'), findsOneWidget);

      // Streak card
      expect(find.textContaining('streak'), findsWidgets);

      // Scroll to badges section
      await tester.scrollUntilVisible(
        find.text('Your badges'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Your badges'), findsOneWidget);
      expect(find.textContaining('View all'), findsOneWidget);

      // Tapping View all opens BadgesPage
      await tester.tap(find.textContaining('View all'));
      await tester.pumpAndSettle();
      expect(find.byType(BadgesPage), findsOneWidget);
    });
  });

  group('Home to Gamification Navigation Test', () {
    testWidgets('HomePage card opens LearningProgressPage', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MyApp(cameraEnabled: false)),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pumpAndSettle();

      final gamificationCard = find.text('Progres Belajar & Badges');
      expect(gamificationCard, findsOneWidget);

      await tester.tap(gamificationCard);
      await tester.pumpAndSettle();

      expect(find.byType(LearningProgressPage), findsOneWidget);
      expect(find.text('Your alphabet journey'), findsOneWidget);
    });

    testWidgets('HomePage header badge icon opens LearningProgressPage', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(child: MyApp(cameraEnabled: false)),
      );
      await tester.pumpAndSettle();

      final headerBadge = find.byTooltip('Progres Belajar & Badges');
      expect(headerBadge, findsOneWidget);

      await tester.tap(headerBadge);
      await tester.pumpAndSettle();

      expect(find.byType(LearningProgressPage), findsOneWidget);
      expect(find.text('Your alphabet journey'), findsOneWidget);
    });
  });
}
