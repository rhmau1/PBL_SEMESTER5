import 'package:flutter/material.dart';

import '../models/badge_item.dart';
import '../models/gamification_progress.dart';
import '../pages/badges_page.dart';
import 'badge_svg_icon.dart';

class BadgeUnlockedDialog extends StatelessWidget {
  const BadgeUnlockedDialog({
    super.key,
    required this.badge,
    required this.progress,
    this.onContinueLearning,
    this.onViewBadges,
  });

  final BadgeItem badge;
  final GamificationProgress progress;
  final VoidCallback? onContinueLearning;
  final VoidCallback? onViewBadges;

  static const _ink = Color(0xFF172642);
  static const _muted = Color(0xFF7585A2);
  static const _blue = Color(0xFF2864F0);
  static const _paleBlue = Color(0xFFEAF0FF);

  static Future<void> show(
    BuildContext context, {
    required BadgeItem badge,
    required GamificationProgress progress,
    VoidCallback? onContinueLearning,
    VoidCallback? onViewBadges,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => BadgeUnlockedDialog(
        badge: badge,
        progress: progress,
        onContinueLearning: onContinueLearning,
        onViewBadges: onViewBadges,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = badge.isUnlocked(progress);
    final next = progress.nextBadge;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                    tooltip: 'Tutup',
                  ),
                  Expanded(
                    child: Text(
                      isUnlocked ? 'Your achievement' : 'Badge details',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // Balance back button
                ],
              ),
              const SizedBox(height: 14),

              // Badge Status Chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isUnlocked ? _paleBlue : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUnlocked
                          ? Icons.auto_awesome_rounded
                          : Icons.lock_outline_rounded,
                      color: isUnlocked ? _blue : const Color(0xFF64748B),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isUnlocked ? 'BADGE UNLOCKED' : 'BADGE LOCKED',
                      style: TextStyle(
                        color: isUnlocked ? _blue : const Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                isUnlocked
                    ? 'A little practice. A big\nachievement.'
                    : 'Tantangan Menanti!\nTerus Berlatih.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),

              // Center Illustration
              Center(
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isUnlocked
                            ? _blue.withValues(alpha: 0.14)
                            : const Color(0x0C0E2343),
                        blurRadius: 36,
                        spreadRadius: 6,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: BadgeSvgIcon(
                    badge: badge,
                    size: 190,
                    isUnlocked: isUnlocked,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Badge Name
              Text(
                badge.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),

              // Badge Description
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  badge.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Status Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isUnlocked
                          ? const Color(0xFFE8F8EE)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUnlocked
                              ? Icons.check_rounded
                              : Icons.lock_outline_rounded,
                          size: 13,
                          color: isUnlocked
                              ? const Color(0xFF00A879)
                              : const Color(0xFF7585A2),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isUnlocked ? 'Earned' : 'Locked',
                          style: TextStyle(
                            color: isUnlocked
                                ? const Color(0xFF00A879)
                                : const Color(0xFF7585A2),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isUnlocked
                        ? '${progress.unlockedCount} of ${progress.totalBadgesCount} badges earned'
                        : badge.progressText(progress),
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Next Stop / Requirement Card
              if (!isUnlocked) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE8EDF5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _paleBlue,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.track_changes_rounded,
                            color: _blue, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Syarat Membuka Badge',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              badge.requirement,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ] else if (next != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE8EDF5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _paleBlue,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.flag_rounded,
                            color: _blue, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next stop: ${next.title}',
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              next.progressText(progress),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Primary Continue Button
              SizedBox(
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
                    Navigator.pop(context);
                    onContinueLearning?.call();
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Continue learning',
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
              const SizedBox(height: 10),

              // Secondary View Badges Button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    if (onViewBadges != null) {
                      onViewBadges!();
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BadgesPage(),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'View my badges',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
