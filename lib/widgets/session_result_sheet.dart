import 'package:flutter/material.dart';

/// Content shown in the bottom sheet after a practice session ends.
///
/// The sheet always fills the screen width and keeps a screen-relative,
/// stable height so consecutive sessions open at the same size.
class SessionResultSheet extends StatelessWidget {
  const SessionResultSheet({
    super.key,
    required this.letters,
    required this.target,
    this.savedVideoPath,
  });

  static const Color _homeGreen = Color(0xFF2E7D32);
  static const Color _homeLightGreen = Color(0xFFE8F5E9);

  /// Predicted letters of the session, in order.
  final List<String> letters;

  /// Target letter for validation mode; empty for free practice.
  final String target;

  /// Local path of the saved session video, when one was recorded.
  final String? savedVideoPath;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final minHeight = screenHeight * 0.50;
    final maxHeight = screenHeight * 0.85;
    final sequence = letters.join();
    final validationTotal = letters.length;
    final validationCorrect =
        target.isEmpty ? 0 : letters.where((label) => label == target).length;
    final validationAccuracy = validationTotal == 0
        ? 0.0
        : validationCorrect / validationTotal * 100;

    return SizedBox(
      key: const ValueKey('session-result-sheet'),
      width: double.infinity,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.task_alt_rounded, size: 52, color: _homeGreen),
                const SizedBox(height: 12),
                Text(
                  target.isEmpty ? 'Hasil sesi' : 'Hasil uji target $target',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                if (sequence.isEmpty)
                  Text(
                    'Belum ada huruf yang stabil.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        sequence,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 6,
                            ),
                      ),
                    ),
                  ),
                if (letters.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    target.isEmpty
                        ? '${letters.length} huruf dikenali tanpa spasi'
                        : '${letters.length} percobaan stabil direkam',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: letters
                        .map((letter) => Chip(label: Text(letter)))
                        .toList(),
                  ),
                ],
                if (target.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _homeLightGreen,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      validationTotal == 0
                          ? 'Validasi target $target: belum ada prediksi stabil.'
                          : 'Validasi target $target: $validationCorrect/$validationTotal benar (${validationAccuracy.toStringAsFixed(1)}%).',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
                if (savedVideoPath != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Video tersimpan di:\n$savedVideoPath',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
