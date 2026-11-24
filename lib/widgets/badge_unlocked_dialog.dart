import 'package:flutter/material.dart';

import '../models/badge_item.dart';
import '../models/gamification_progress.dart';
import '../pages/badges_page.dart';
import 'badge_svg_icon.dart';

const _ink = Color(0xFF172642);
const _muted = Color(0xFF7585A2);
const _blue = Color(0xFF2864F0);
const _paleBlue = Color(0xFFEAF0FF);

class BadgeUnlockedDialog extends StatelessWidget {
  const BadgeUnlockedDialog({
    super.key,
    required this.badge,
    required this.progress,
    this.isNewUnlock = false,
    this.onContinueLearning,
    this.onViewBadges,
  });

  final BadgeItem badge;
  final GamificationProgress progress;
  final bool isNewUnlock;
  final VoidCallback? onContinueLearning;
  final VoidCallback? onViewBadges;

  static Future<void> show(
    BuildContext context, {
    required BadgeItem badge,
    required GamificationProgress progress,
    bool isNewUnlock = false,
    VoidCallback? onContinueLearning,
    VoidCallback? onViewBadges,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => BadgeUnlockedDialog(
        badge: badge,
        progress: progress,
        isNewUnlock: isNewUnlock,
        onContinueLearning: onContinueLearning,
        onViewBadges: onViewBadges,
      ),
    );
  }

  int _tierLevel(BadgeTier tier) {
    return switch (tier) {
      BadgeTier.keepLearning => 1,
      BadgeTier.good => 2,
      BadgeTier.excellent => 3,
      BadgeTier.perfect => 4,
      BadgeTier.impossible => 5,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = badge.isUnlocked(progress);
    final next = progress.nextBadge;
    final tierScore = _tierLevel(badge.tier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F7FC),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE8EDF5)),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: _ink, size: 20),
                      tooltip: 'Tutup',
                    ),
                  ),
                  Expanded(
                    child: Text(
                      isUnlocked
                          ? (isNewUnlock
                              ? 'Pencapaian Baru Anda'
                              : 'Detail Pencapaian')
                          : 'Detail Lencana',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 38), // Balance back button
                ],
              ),
              const SizedBox(height: 16),

              // Badge Status Pill
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
                      isUnlocked ? 'LENCANA TERBUKA' : 'LENCANA TERKUNCI',
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

              // Main Headline
              Text(
                isUnlocked
                    ? 'Latihan kecil. Pencapaian besar.'
                    : 'Tantangan Menanti!\nTerus Berlatih.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),

              // Hero Center Illustration with Decorative Sparkles
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow / burst effect
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: isUnlocked
                                ? const Color(0xFF7D3EC0).withValues(alpha: 0.16)
                                : const Color(0x0C0E2343),
                            blurRadius: 40,
                            spreadRadius: 8,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                    ),
                    // Centered Badge SVG
                    BadgeSvgIcon(
                      badge: badge,
                      size: 190,
                      isUnlocked: isUnlocked,
                    ),
                    // Decorative sparkle dots around illustration
                    if (isUnlocked) ...[
                      const Positioned(
                        top: 14,
                        right: 28,
                        child: Icon(Icons.star_rounded,
                            color: Color(0xFF9E6BE6), size: 18),
                      ),
                      const Positioned(
                        top: 48,
                        left: 20,
                        child: Icon(Icons.star_rounded,
                            color: Color(0xFFC7A8F5), size: 14),
                      ),
                      const Positioned(
                        bottom: 40,
                        right: 18,
                        child: Icon(Icons.star_rounded,
                            color: Color(0xFF9E6BE6), size: 14),
                      ),
                      const Positioned(
                        bottom: 60,
                        left: 12,
                        child: Icon(Icons.star_rounded,
                            color: Color(0xFF60A5FA), size: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Tier Stars Under Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final filled = isUnlocked && index < tierScore;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 20,
                      color: filled
                          ? const Color(0xFF8B5CF6)
                          : const Color(0xFFCBD5E1),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),

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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  badge.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 14,
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
                        horizontal: 10, vertical: 5),
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
                          isUnlocked ? 'Diraih hari ini' : 'Terkunci',
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
                        ? '${progress.unlockedCount} dari ${progress.totalBadgesCount} lencana diraih'
                        : badge.progressText(progress),
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Next Stop Card
              if (isUnlocked && next != null)
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
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _paleBlue,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.outlined_flag_rounded,
                            color: _blue, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Target berikutnya: ${next.title}',
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Kuasai seluruh 24 huruf · sisa ${24 - progress.practicedLetters.length} huruf!',
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
                )
              else if (!isUnlocked)
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
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _paleBlue,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.track_changes_rounded,
                            color: _blue, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Syarat Membuka Lencana',
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

              // Primary Continue Button
              SizedBox(
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
                    Navigator.pop(context);
                    onContinueLearning?.call();
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Lanjut latihan',
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
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _blue,
                    side: const BorderSide(color: Color(0xFFE8EDF5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
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
                    'Lihat lencana saya',
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
