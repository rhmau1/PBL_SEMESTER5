import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/badge_item.dart';

class BadgeSvgIcon extends StatelessWidget {
  const BadgeSvgIcon({
    super.key,
    required this.badge,
    this.size = 64,
    this.isUnlocked = true,
    this.showBackground = true,
  });

  final BadgeItem badge;
  final double size;
  final bool isUnlocked;
  final bool showBackground;

  Color get _backgroundColor {
    if (!isUnlocked) return const Color(0xFFF1F4F9);
    return switch (badge.tier) {
      BadgeTier.keepLearning => const Color(0xFFE8F8EE),
      BadgeTier.good => const Color(0xFFE8F4FC),
      BadgeTier.excellent => const Color(0xFFF5EEFA),
      BadgeTier.perfect => const Color(0xFFFFF7E6),
      BadgeTier.impossible => const Color(0xFFF2ECF9),
    };
  }

  Color get _borderColor {
    if (!isUnlocked) return const Color(0xFFE2E8F0);
    return switch (badge.tier) {
      BadgeTier.keepLearning => const Color(0xFFC6EED5),
      BadgeTier.good => const Color(0xFFCCE8FA),
      BadgeTier.excellent => const Color(0xFFE5D2F5),
      BadgeTier.perfect => const Color(0xFFFFE2A8),
      BadgeTier.impossible => const Color(0xFFDDCFF2),
    };
  }

  @override
  Widget build(BuildContext context) {
    final containerSize = size;
    final svgSize = size * 0.76;

    final svgWidget = SvgPicture.asset(
      badge.assetPath,
      width: svgSize,
      height: svgSize,
      fit: BoxFit.contain,
      placeholderBuilder: (context) => Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _borderColor,
          ),
        ),
      ),
    );

    if (!showBackground) {
      return Opacity(
        opacity: isUnlocked ? 1.0 : 0.45,
        child: svgWidget,
      );
    }

    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        color: _backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: _borderColor,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: isUnlocked ? 1.0 : 0.45,
          child: svgWidget,
        ),
      ),
    );
  }
}
