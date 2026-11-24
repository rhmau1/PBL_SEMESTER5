import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/badge_item.dart';
import '../models/gamification_progress.dart';
import '../pages/learning_progress_page.dart';
import '../providers/gamification_provider.dart';
import '../services/llm_autocorrect_service.dart';
import 'badge_svg_icon.dart';
import 'badge_unlocked_dialog.dart';

const _ink = Color(0xFF172642);
const _muted = Color(0xFF7585A2);
const _blue = Color(0xFF2864F0);
const _border = Color(0xFFE8EDF5);

class SessionCompleteSheet extends ConsumerStatefulWidget {
  const SessionCompleteSheet({
    super.key,
    required this.displayedPredictions,
    required this.target,
    required this.validationCorrect,
    required this.validationTotal,
    required this.validationAccuracy,
    this.savedVideoPath,
    this.autocorrectFuture,
    this.onContinue,
    this.onViewProgress,
  });

  final List<String> displayedPredictions;
  final String target;
  final int validationCorrect;
  final int validationTotal;
  final double validationAccuracy;
  final String? savedVideoPath;
  final Future<AutocorrectResult>? autocorrectFuture;
  final VoidCallback? onContinue;
  final VoidCallback? onViewProgress;

  @override
  ConsumerState<SessionCompleteSheet> createState() =>
      _SessionCompleteSheetState();
}

class _SessionCompleteSheetState extends ConsumerState<SessionCompleteSheet> {
  late String _activeSequence;

  @override
  void initState() {
    super.initState();
    _activeSequence = widget.displayedPredictions.join();
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(gamificationProvider);
    final isTargetMode = widget.target.isNotEmpty;

    // Detect unique supported letters from this session (A..Y excluding J, Z)
    final supportedSet = GamificationProgress.supportedAlphabet.toSet();
    final sessionUniqueLetters = widget.displayedPredictions
        .map((s) => s.toUpperCase())
        .where((s) => supportedSet.contains(s))
        .toSet()
        .toList();

    // Letters to display in chips row (fallback to representative letters if empty)
    final lettersToShow = sessionUniqueLetters.isNotEmpty
        ? sessionUniqueLetters.take(5).toList()
        : (widget.displayedPredictions.isNotEmpty
            ? widget.displayedPredictions
                .where((s) => supportedSet.contains(s.toUpperCase()))
                .take(5)
                .toList()
            : ['K', 'L', 'M', 'N', 'O']);

    // Letter progress text based on 24 letters
    final currentTotalLearned = progress.practicedLetters.length;
    final prevLettersCount =
        (currentTotalLearned - lettersToShow.length).clamp(0, 24);
    final progressPercentage = progress.percentageLetters > 0
        ? progress.percentageLetters
        : ((lettersToShow.length / 24) * 100).round();

    // Badge to feature in card
    final unlockedBadges = progress.unlockedBadges;
    final badgeToFeature = unlockedBadges.isNotEmpty
        ? unlockedBadges.last
        : (progress.nextBadge ?? BadgeItem.allBadges.first);
    final isBadgeUnlocked = badgeToFeature.isUnlocked(progress);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar: Close 'X' and Title
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F9),
                    shape: BoxShape.circle,
                    border: Border.all(color: _border),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _ink,
                      size: 20,
                    ),
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Session complete',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 36), // Balance close button
              ],
            ),
            const SizedBox(height: 16),

            // Green Check Circle
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFFE3F8EF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF10AD7E),
                size: 30,
              ),
            ),
            const SizedBox(height: 12),

            // Main Heading
            const Text(
              'Look how far you’ve come!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isTargetMode
                  ? 'Target: Huruf ${widget.target}'
                  : 'Sesi latihan huruf selesai',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 16),

            // Clean XP Banner (replaces quiz answers and time)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF0FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt_rounded, color: _blue, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '+60 XP didapatkan!',
                    style: TextStyle(
                      color: _blue,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Card: Letters Learned (24 letters curriculum)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x080E2343),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${lettersToShow.length} new letters learned',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF0FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${currentTotalLearned > 0 ? currentTotalLearned : lettersToShow.length} / 24',
                          style: const TextStyle(
                            color: _blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Letter Chips spanning row
                  Row(
                    children: lettersToShow.map((letter) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF0FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            letter,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: currentTotalLearned > 0
                          ? (currentTotalLearned / 24).clamp(0.0, 1.0)
                          : (lettersToShow.length / 24).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: const Color(0xFFDCE6F5),
                      valueColor: const AlwaysStoppedAnimation<Color>(_blue),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Alphabet progress: $prevLettersCount → ${currentTotalLearned > 0 ? currentTotalLearned : lettersToShow.length} letters · $progressPercentage% complete',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Card: Featured Badge Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF6FE),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2D6F7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isBadgeUnlocked ? 'NEW BADGE EARNED' : 'NEXT BADGE TO EARN',
                    style: const TextStyle(
                      color: Color(0xFF7D3EC0),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      BadgeSvgIcon(
                        badge: badgeToFeature,
                        size: 54,
                        isUnlocked: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              badgeToFeature.title,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              badgeToFeature.requirement,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                BadgeUnlockedDialog.show(
                                  context,
                                  badge: badgeToFeature,
                                  progress: progress,
                                  isNewUnlock: isBadgeUnlocked,
                                  onContinueLearning: widget.onContinue,
                                );
                              },
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Meet your new badge',
                                    style: TextStyle(
                                      color: _blue,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 14,
                                    color: _blue,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Card: Streak Row
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    color: _blue,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${progress.streakDays > 0 ? progress.streakDays : 5}-day streak. High five!',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${progress.totalXp > 0 ? progress.totalXp : 360} total XP · Your daily goal is complete.',
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

            // Autocorrect Results Section (if LLM returned suggestions)
            if (widget.autocorrectFuture != null)
              FutureBuilder<AutocorrectResult>(
                future: widget.autocorrectFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _blue,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Memeriksa saran kata via AI...',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final result = snapshot.data;
                  if (result == null || !result.hasSuggestions) {
                    return const SizedBox.shrink();
                  }

                  return Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F5FF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFD6E4FF)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Saran Kata AI Gemini (tap untuk pilih):',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final word in result.suggestions)
                              ChoiceChip(
                                label: Text(word),
                                selected: _activeSequence == word,
                                selectedColor: _blue,
                                backgroundColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: _activeSequence == word
                                      ? Colors.white
                                      : _blue,
                                  fontWeight: FontWeight.w800,
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    _activeSequence = _activeSequence == word
                                        ? widget.displayedPredictions.join()
                                        : word;
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 16),

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
                  widget.onContinue?.call();
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
            const SizedBox(height: 8),

            // Secondary View Progress Link
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: _blue,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  if (widget.onViewProgress != null) {
                    widget.onViewProgress!();
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LearningProgressPage(
                          onContinueLearning: widget.onContinue,
                        ),
                      ),
                    );
                  }
                },
                child: const Text(
                  'View my progress',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
