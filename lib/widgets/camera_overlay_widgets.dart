import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/sign_classifier.dart';

const _modelSelectionBlue = Color(0xFF2864F0);

class RoundCameraButton extends StatelessWidget {
  const RoundCameraButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _modelSelectionBlue,
        disabledBackgroundColor: Colors.white,
        disabledForegroundColor: const Color(0xFF9AAAC4),
        minimumSize: const Size.square(48),
        shape: const CircleBorder(),
        elevation: 2,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class DetectionFrame extends StatelessWidget {
  const DetectionFrame({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(
          constraints.maxWidth * 0.9,
          constraints.maxHeight * 0.94,
        );
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    key: const ValueKey('camera-detection-frame'),
                    painter: _DashedRoundedBorderPainter(
                      color: colors.primary.withValues(alpha: 0.82),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 8,
                  right: 8,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.back_hand_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Posisikan tangan di sini',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(24)),
      );
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 16) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 9, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.active,
    required this.handDetected,
  });

  final bool active;
  final bool handDetected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active && handDetected
                  ? Icons.back_hand_rounded
                  : active
                  ? Icons.search_rounded
                  : Icons.pause_circle_outline,
              size: 10,
              color: active && handDetected
                  ? colors.primary
                  : active
                  ? const Color(0xFFE3A21A)
                  : const Color(0xFF7585A2),
            ),
            const SizedBox(width: 7),
            Text(
              active && handDetected
                  ? 'TANGAN TERDETEKSI'
                  : active
                  ? 'CARI TANGAN'
                  : 'SIAP',
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModelOption extends StatelessWidget {
  const ModelOption({
    super.key,
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final SignModel model;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: 0.55)
          : colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.memory_rounded,
                color: _modelSelectionBlue,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '24 huruf statis • Deteksi di perangkat',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: _modelSelectionBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActiveModelCard extends StatelessWidget {
  const ActiveModelCard({super.key, required this.onTap, required this.model});

  final VoidCallback? onTap;
  final String model;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const ValueKey('camera-model-selector'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.memory_rounded,
                color: _modelSelectionBlue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MODEL AI',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'LatihIsyarat $model',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more_rounded, color: _modelSelectionBlue),
            ],
          ),
        ),
      ),
    );
  }
}

class LiveResultCard extends StatelessWidget {
  const LiveResultCard({
    super.key,
    required this.active,
    required this.handDetected,
    required this.eventCount,
    required this.target,
    required this.latestPrediction,
    required this.correctCount,
    this.sessionSequence = '',
  });

  final bool active;
  final bool handDetected;
  final int eventCount;
  final String target;
  final String? latestPrediction;
  final int correctCount;
  final String sessionSequence;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final output = target.isNotEmpty
        ? (handDetected ? latestPrediction : null) ?? '—'
        : sessionSequence.isNotEmpty
        ? sessionSequence
        : active && handDetected
        ? 'Menganalisis...'
        : '—';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                  color: active ? colors.primary : colors.onSurfaceVariant,
                  size: 17,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    target.isNotEmpty
                        ? 'LIVE STREAM UJI HURUF $target'
                        : 'LIVE STREAM DETEKSI ISYARAT',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  active ? 'LIVE' : 'SIAP',
                  style: TextStyle(
                    color: active ? colors.primary : colors.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Text(
                output,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: output == '—'
                      ? colors.onSurfaceVariant
                      : colors.onSurface,
                  fontSize: target.isNotEmpty ? 22 : 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _description,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String get _description {
    if (target.isNotEmpty) {
      if (!active) {
        return 'Deteksi dimulai otomatis saat kamera siap; video tidak direkam.';
      }
      if (!handDetected) {
        return 'Gunakan latar polos dan pastikan tangan terlihat utuh.';
      }
      if (latestPrediction == null) {
        return 'Tahan pose sebentar sampai prediksi muncul.';
      }
      return '$correctCount/$eventCount percobaan stabil benar';
    }
    if (!active) {
      return 'Semua huruf stabil akan disusun setelah sesi diakhiri.';
    }
    if (!handDetected) {
      return 'Gunakan latar polos dan pastikan tangan terlihat utuh.';
    }
    return '$eventCount huruf tersimpan. Hasil disembunyikan sampai sesi diakhiri.';
  }
}
