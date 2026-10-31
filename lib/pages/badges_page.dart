import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/badge_item.dart';
import '../providers/gamification_provider.dart';
import '../widgets/badge_svg_icon.dart';
import '../widgets/badge_unlocked_dialog.dart';

class BadgesPage extends ConsumerWidget {
  const BadgesPage({super.key, this.onContinueLearning});

  final VoidCallback? onContinueLearning;

  static const _ink = Color(0xFF172642);
  static const _muted = Color(0xFF7585A2);
  static const _blue = Color(0xFF2864F0);
  static const _paleBlue = Color(0xFFEAF0FF);
  static const _border = Color(0xFFE8EDF5);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(gamificationProvider);
    final seenNotifier = ref.watch(seenBadgesProvider.notifier);
    final seenBadges = ref.watch(seenBadgesProvider);

    final unlockedCount = progress.unlockedCount;
    final totalBadges = progress.totalBadgesCount;
    final remainingCount = totalBadges - unlockedCount;
    final progressRatio = totalBadges == 0 ? 0.0 : unlockedCount / totalBadges;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                tooltip: 'Kembali',
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          'My badges',
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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  // Header Title & Counter Badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Text(
                          'Small signs. Big wins.',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _paleBlue,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '$unlockedCount / $totalBadges',
                          style: const TextStyle(
                            color: _blue,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  const Text(
                    'Meet your learning companions. Every badge celebrates a step forward.',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progressRatio,
                      minHeight: 7,
                      backgroundColor: const Color(0xFFDCE6F5),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(_blue),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Progress Summary
                  Text(
                    remainingCount > 0
                        ? '$unlockedCount earned · $remainingCount more adventures ahead'
                        : 'All $unlockedCount badges unlocked! Incredible achievement!',
                    style: const TextStyle(
                      color: _blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Badges List
                  for (final badge in BadgeItem.allBadges) ...[
                    _BadgeListCard(
                      badge: badge,
                      isUnlocked: badge.isUnlocked(progress),
                      isNew: badge.isUnlocked(progress) &&
                          !seenBadges.contains(badge.id),
                      progressText: badge.progressText(progress),
                      onTap: () {
                        seenNotifier.markBadgeSeen(badge.id);
                        BadgeUnlockedDialog.show(
                          context,
                          badge: badge,
                          progress: progress,
                          onContinueLearning: () {
                            if (onContinueLearning != null) {
                              onContinueLearning!();
                            } else if (Navigator.canPop(context)) {
                              Navigator.pop(context);
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 12),
                  // Footnote
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_rounded,
                          color: Color(0xFF3475FF), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'No rush. Every little practice counts.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    if (onContinueLearning != null) {
                      onContinueLearning!();
                    } else if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Keep learning',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
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

class _BadgeListCard extends StatelessWidget {
  const _BadgeListCard({
    required this.badge,
    required this.isUnlocked,
    required this.isNew,
    required this.progressText,
    required this.onTap,
  });

  final BadgeItem badge;
  final bool isUnlocked;
  final bool isNew;
  final String progressText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // If it's unlocked and new, give it a soft lavender accent border/bg
    final highlight = isUnlocked && isNew;

    return Material(
      color: highlight ? const Color(0xFFFBF8FE) : Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: highlight
                  ? const Color(0xFFDECFF2)
                  : const Color(0xFFE8EDF5),
              width: highlight ? 1.5 : 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0E2343),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Badge SVG Illustration
              BadgeSvgIcon(
                badge: badge,
                size: 58,
                isUnlocked: isUnlocked,
              ),
              const SizedBox(width: 14),

              // Title and Requirements
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badge.title,
                      style: TextStyle(
                        color: isUnlocked
                            ? const Color(0xFF172642)
                            : const Color(0xFF8B9BB5),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      badge.requirement,
                      style: const TextStyle(
                        color: Color(0xFF7585A2),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progressText,
                      style: TextStyle(
                        color: isUnlocked
                            ? const Color(0xFF00A879)
                            : const Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Status Pill
              _StatusPill(
                isUnlocked: isUnlocked,
                isNew: isNew,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.isUnlocked,
    required this.isNew,
  });

  final bool isUnlocked;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    if (!isUnlocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F4F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 13, color: Color(0xFF7585A2)),
            SizedBox(width: 4),
            Text(
              'Locked',
              style: TextStyle(
                color: Color(0xFF7585A2),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (isNew) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEFE6FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded,
                size: 13, color: Color(0xFF7D3EC0)),
            SizedBox(width: 4),
            Text(
              'Earned · New',
              style: TextStyle(
                color: Color(0xFF7D3EC0),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F8EE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded,
              size: 13, color: Color(0xFF00A879)),
          SizedBox(width: 4),
          Text(
            'Earned',
            style: TextStyle(
              color: Color(0xFF00A879),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
