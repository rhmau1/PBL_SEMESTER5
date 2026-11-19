import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/onboarding_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.nextScreen,
    this.firstLaunchScreen,
    this.duration = const Duration(milliseconds: 1600),
  });

  final Widget nextScreen;
  final Widget? firstLaunchScreen;
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () => unawaited(_openNextScreen()));
  }

  Future<void> _openNextScreen() async {
    final firstLaunch = widget.firstLaunchScreen;
    final destination = firstLaunch != null && !await hasCompletedOnboarding()
        ? firstLaunch
        : widget.nextScreen;
    if (!mounted) return;
    await Navigator.of(context)
        .pushReplacement(MaterialPageRoute<void>(builder: (_) => destination));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SvgPicture.asset(
          'assets/logo/signy_maskot.svg',
          width: 240,
          height: 240,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
