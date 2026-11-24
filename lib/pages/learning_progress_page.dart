import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/badge_item.dart';
import '../providers/gamification_provider.dart';
import '../widgets/badge_svg_icon.dart';
import '../widgets/badge_unlocked_dialog.dart';
import 'badges_page.dart';

class LearningProgressPage extends ConsumerWidget {
  const LearningProgressPage({super.key, this.onContinueLearning});

  final VoidCallback? onContinueLearning;

  static const _ink = Color(0xFF172642);
  static const _muted = Color(0xFF7585A2);
  static const _blue = Color(0xFF2864F0);
  static const _paleBlue = Color(0xFFEAF0FF);
  static const _border = Color(0xFFE8EDF5);

  static const _row1Letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K', 'L', 'M'
  ];
  static const _row2Letters = [
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(gamificationProvider);
    final seenNotifier = ref.watch(seenBadgesProvider.notifier);
    final seenBadges = ref.watch(seenBadgesProvider);

    final learnedCount = progress.practicedLetters.length;
    final totalLetters = progress.totalLetters; // 24 letters (no J and Z)
    final percent = progress.percentageLetters;
    final progressRatio = (learnedCount / totalLetters).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.canPop(context)
            ? Container(
                margin: const EdgeInsets.only(left: 12),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                  tooltip: 'Kembali',
                  onPressed: () => Navigator.pop(context),
                ),
              )
            : null,
        title: const Text(
          'Progres Belajar',
          style: TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: _border),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                children: [
                  // Card 1: Your alphabet journey
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A0E2343),
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Perjalanan Alfabetmu',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _paleBlue,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$percent%',
                                style: const TextStyle(
                                  color: _blue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$learnedCount dari $totalLetters huruf dipelajari',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Progress Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progressRatio,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFDCE6F5),
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(_blue),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Alphabet Grid: 2 clean rows of 13 letters
                        Row(
                          children: _row1Letters.map((letter) {
                            final isPracticed =
                                progress.isLetterPracticed(letter);
                            return Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 1.5),
                                child: _AlphabetChip(
                                  letter: letter,
                                  isPracticed: isPracticed,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: _row2Letters.map((letter) {
                            final isPracticed =
                                progress.isLetterPracticed(letter);
                            return Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 1.5),
                                child: _AlphabetChip(
                                  letter: letter,
                                  isPracticed: isPracticed,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        // Subtitle row: learned range and next lesson
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              progress.learnedSummaryText,
                              style: const TextStyle(
                                color: _blue,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Berikutnya: ${progress.nextLessonRange}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card 2: Streak Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A0E2343),
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  color: _blue,
                                  size: 22,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Streak ${progress.streakDays} Hari',
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${progress.totalXp} XP · ${progress.totalAttempts} sesi',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Streak Day Circles (Senin - Minggu: M, T, W, T, F, S, S)
                        Builder(
                          builder: (context) {
                            const dayNames = [
                              'M',
                              'T',
                              'W',
                              'T',
                              'F',
                              'S',
                              'S'
                            ];
                            final currentWeekday = DateTime.now().weekday; // 1 (Mon) .. 7 (Sun)

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(7, (index) {
                                final weekday = index + 1;
                                final isPassed = weekday <= currentWeekday &&
                                    (currentWeekday - weekday) < progress.streakDays;

                                return Column(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isPassed
                                            ? _blue
                                            : const Color(0xFFF1F5F9),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isPassed
                                              ? _blue
                                              : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Center(
                                        child: isPassed
                                            ? const Icon(Icons.check_rounded,
                                                size: 18, color: Colors.white)
                                            : const Text('·',
                                                style: TextStyle(
                                                    fontSize: 22,
                                                    color: Color(0xFF94A3B8))),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      dayNames[index],
                                      style: TextStyle(
                                        color: isPassed ? _ink : _muted,
                                        fontSize: 11,
                                        fontWeight: isPassed
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            );
                          },
                        ),
                        const SizedBox(height: 14),

                        Text(
                          progress.streakDays > 0
                              ? 'Kamu sudah latihan hari ini. Pertahankan streak besok!'
                              : 'Mulai latihan hari ini untuk membangun streak!',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Section 3: Your Badges Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Lencana Pencapaian',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BadgesPage(
                                onContinueLearning: onContinueLearning,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          child: Text(
                            'Lihat semua · ${progress.unlockedCount} / ${progress.totalBadgesCount}',
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Horizontal Badges Row
                  SizedBox(
                    height: 154,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: BadgeItem.allBadges.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final badge = BadgeItem.allBadges[index];
                        final isUnlocked = badge.isUnlocked(progress);
                        final isNew = isUnlocked &&
                            !seenBadges.contains(badge.id);

                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          child: InkWell(
                            onTap: () {
                              seenNotifier.markBadgeSeen(badge.id);
                              BadgeUnlockedDialog.show(
                                context,
                                badge: badge,
                                progress: progress,
                                onContinueLearning: onContinueLearning,
                              );
                            },
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              width: 120,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: isNew
                                      ? const Color(0xFFDECFF2)
                                      : _border,
                                  width: isNew ? 1.5 : 1.0,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  BadgeSvgIcon(
                                    badge: badge,
                                    size: 50,
                                    isUnlocked: isUnlocked,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    badge.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isUnlocked ? _ink : _muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isNew
                                        ? 'Baru diraih!'
                                        : (isUnlocked ? 'Diraih' : 'Terkunci'),
                                    style: TextStyle(
                                      color: isNew
                                          ? const Color(0xFF7D3EC0)
                                          : (isUnlocked
                                              ? const Color(0xFF00A879)
                                              : _muted),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Section 4: Recent Sessions
                  const Text(
                    'Sesi Terakhir',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (progress.recentHistory.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _border),
                      ),
                      child: const Center(
                        child: Text(
                          'Belum ada sesi latihan. Mulai sekarang untuk meraih XP!',
                          style: TextStyle(color: _muted, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ...progress.recentHistory.map((item) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: _paleBlue,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.menu_book_rounded,
                                color: _blue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Huruf ${item.gesture}',
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${item.date} · ${item.time}',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _paleBlue,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '+60 XP',
                                style: TextStyle(
                                  color: _blue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),

            // Bottom Sticky Button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: _border)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                    onContinueLearning?.call();
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Lanjut Latihan · Huruf ${progress.nextLessonRange}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlphabetChip extends StatelessWidget {
  const _AlphabetChip({
    required this.letter,
    required this.isPracticed,
  });

  final String letter;
  final bool isPracticed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: isPracticed
            ? const Color(0xFF2864F0)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPracticed
              ? const Color(0xFF2864F0)
              : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: isPracticed ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 12.5,
            fontWeight: isPracticed ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
