import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/onboarding_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.nextScreen});

  final Widget nextScreen;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _blue = Color(0xFF2864F0);
  static const _ink = Color(0xFF172642);
  static const _muted = Color(0xFF7585A2);
  static const _background = Color(0xFFF4F7FC);
  static const _slides = [
    _OnboardingSlide(
      eyebrow: 'KENALI LATIHISYARAT',
      title: 'Belajar isyarat, selangkah demi selangkah',
      description: 'Latih pose huruf dengan kamera, pelajari contoh di Kamus, dan lihat perkembanganmu kapan saja.',
      visual: _SlideVisual.welcome,
    ),
    _OnboardingSlide(
      eyebrow: 'PILIH MODEL AI',
      title: 'Dua model, satu cara belajar',
      description: 'Pilih Model C atau Model E sebelum mendeteksi. Model yang dipilih akan digunakan untuk Video, Foto, dan Upload.',
      visual: _SlideVisual.models,
    ),
    _OnboardingSlide(
      eyebrow: 'MULAI BERLATIH',
      title: 'Gunakan mode yang paling nyaman',
      description: 'Latihan Bebas merangkai pose yang terdeteksi. Mode Uji per Huruf membantu fokus pada satu target. Kamu juga bisa memakai Foto atau Upload.',
      visual: _SlideVisual.practice,
    ),
    _OnboardingSlide(
      eyebrow: 'LIHAT PERKEMBANGAN',
      title: 'Cek hasil dan terus berlatih',
      description: 'Simpan hasil di Riwayat dan cocokkan pose dengan Kamus. Deteksi mendukung 24 pose huruf statis; J dan Z memerlukan gerakan.',
      visual: _SlideVisual.progress,
    ),
  ];

  final _pageController = PageController();
  int _currentPage = 0;
  bool _isCompleting = false;

  Future<void> _completeOnboarding() async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);
    try {
      await markOnboardingCompleted();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isCompleting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Pengenalan belum tersimpan: $error')),
        );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => widget.nextScreen),
    );
  }

  void _nextPage() {
    if (_currentPage == _slides.length - 1) {
      _completeOnboarding();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _slides.length - 1;
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Text(
                    'PENGENALAN',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('onboarding-skip'),
                    onPressed: _isCompleting ? null : _completeOnboarding,
                    child: const Text('Lewati'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const ValueKey('onboarding-pages'),
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemBuilder: (context, index) =>
                    _OnboardingPage(index: index, slide: _slides[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (index) => Semantics(
                        label: 'Slide ${index + 1} dari ${_slides.length}',
                        selected: _currentPage == index,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? _blue
                                : const Color(0xFFD8E1F0),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: OutlinedButton(
                          key: const ValueKey('onboarding-previous'),
                          onPressed: _currentPage == 0 || _isCompleting
                              ? null
                              : () => _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                ),
                          style: OutlinedButton.styleFrom(
                            shape: const CircleBorder(),
                            side: const BorderSide(color: Color(0xFFD8E1F0)),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: FilledButton(
                            key: const ValueKey('onboarding-next'),
                            onPressed: _isCompleting ? null : _nextPage,
                            style: FilledButton.styleFrom(
                              backgroundColor: _blue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isCompleting
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          isLastPage
                                              ? 'Mulai Belajar'
                                              : 'Lanjut',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        isLastPage
                                            ? Icons.rocket_launch_rounded
                                            : Icons.arrow_forward_rounded,
                                        size: 19,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.index, required this.slide});

  final int index;
  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visualHeight = (constraints.maxHeight * 0.48).clamp(210.0, 300.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: visualHeight,
                width: double.infinity,
                child: _OnboardingVisual(type: slide.visual),
              ),
              const SizedBox(height: 22),
              Text(
                '0${index + 1}  /  0${_OnboardingScreenState._slides.length}',
                style: const TextStyle(
                  color: _OnboardingScreenState._blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                slide.eyebrow,
                style: const TextStyle(
                  color: _OnboardingScreenState._muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                slide.title,
                key: ValueKey('onboarding-title-$index'),
                style: const TextStyle(
                  color: _OnboardingScreenState._ink,
                  fontSize: 27,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                slide.description,
                style: const TextStyle(
                  color: _OnboardingScreenState._muted,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OnboardingVisual extends StatelessWidget {
  const _OnboardingVisual({required this.type});

  final _SlideVisual type;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEAF0FF), Color(0xFFF8FAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFDCE6FF)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: switch (type) {
          _SlideVisual.welcome => const _WelcomeVisual(),
          _SlideVisual.models => const _ModelsVisual(),
          _SlideVisual.practice => const _PracticeVisual(),
          _SlideVisual.progress => const _ProgressVisual(),
        },
      ),
    );
  }
}

class _WelcomeVisual extends StatelessWidget {
  const _WelcomeVisual();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 24,
          left: 28,
          child: _Bubble(size: 18, color: Color(0xFFBFD3FF)),
        ),
        Positioned(
          right: 30,
          bottom: 30,
          child: _Bubble(size: 28, color: Color(0xFFD5E1FF)),
        ),
        Container(
          width: 182,
          height: 182,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(38),
            boxShadow: const [
              BoxShadow(
                color: Color(0x222864F0),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: SvgPicture.asset(
            'assets/logo/signy_maskot.svg',
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }
}

class _ModelsVisual extends StatelessWidget {
  const _ModelsVisual();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Row(
          children: const [
            Expanded(
              child: _ModelTile(
                name: 'Model C',
                detail: 'Grayscale',
                icon: Icons.memory_rounded,
                selected: true,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _ModelTile(
                name: 'Model E',
                detail: 'MobileNet V2',
                icon: Icons.auto_awesome_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.name,
    required this.detail,
    required this.icon,
    this.selected = false,
  });

  final String name;
  final String detail;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? _OnboardingScreenState._blue : Colors.white,
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x142864F0),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: const Color(0xFFEAF0FF),
            child: Icon(icon, color: _OnboardingScreenState._blue),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(
              color: _OnboardingScreenState._ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _OnboardingScreenState._muted,
              fontSize: 10,
            ),
          ),
          if (selected) ...[
            const SizedBox(height: 10),
            const Icon(
              Icons.check_circle_rounded,
              color: _OnboardingScreenState._blue,
              size: 18,
            ),
          ],
        ],
      ),
    );
  }
}

class _PracticeVisual extends StatelessWidget {
  const _PracticeVisual();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: const [
              Expanded(
                child: _FeatureTile(
                  icon: Icons.videocam_rounded,
                  label: 'Video',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _FeatureTile(
                  icon: Icons.camera_alt_rounded,
                  label: 'Foto',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _FeatureTile(
                  icon: Icons.photo_library_rounded,
                  label: 'Upload',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x142864F0),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.center_focus_strong_rounded,
                  color: Color(0xFF2864F0),
                ),
                SizedBox(width: 9),
                Flexible(
                  child: Text(
                    'Bebas  •  Target huruf',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _OnboardingScreenState._ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x142864F0),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _OnboardingScreenState._blue, size: 25),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: _OnboardingScreenState._ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressVisual extends StatelessWidget {
  const _ProgressVisual();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1C2864F0),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_graph_rounded, color: Color(0xFF2864F0)),
                SizedBox(width: 8),
                Text(
                  'PROGRES LATIHAN',
                  style: TextStyle(
                    color: _OnboardingScreenState._muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: const [
                _LetterBadge(label: 'A', done: true),
                SizedBox(width: 8),
                _LetterBadge(label: 'B', done: true),
                SizedBox(width: 8),
                _LetterBadge(label: 'C'),
                SizedBox(width: 8),
                _LetterBadge(label: 'D'),
                Spacer(),
                Icon(Icons.menu_book_rounded, color: Color(0xFF2864F0)),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(
                value: 0.55,
                minHeight: 8,
                backgroundColor: Color(0xFFEAF0FF),
                color: Color(0xFF2864F0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterBadge extends StatelessWidget {
  const _LetterBadge({required this.label, this.done = false});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? _OnboardingScreenState._blue : const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: done ? Colors.white : _OnboardingScreenState._muted,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

enum _SlideVisual { welcome, models, practice, progress }

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.visual,
  });

  final String eyebrow;
  final String title;
  final String description;
  final _SlideVisual visual;
}
