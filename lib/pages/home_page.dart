import 'package:flutter/material.dart';

import 'guide_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.onNavigate,
    required this.onUploadTap,
    this.onOpenGuide,
  });

  final ValueChanged<int> onNavigate;
  final VoidCallback onUploadTap;
  final VoidCallback? onOpenGuide;

  static const _ink = Color(0xFF172642);
  static const _muted = Color(0xFF7585A2);
  static const _blue = Color(0xFF2864F0);
  static const _paleBlue = Color(0xFFEAF0FF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _HomeHeader(
              onOpenGuide: () => _openGuide(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  _WelcomeBanner(blue: _blue),
                  const SizedBox(height: 18),
                  const Text(
                    'Mau mulai dari mana?',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PrimaryAction(
                    onTap: () => onNavigate(1),
                    ink: _ink,
                    blue: _blue,
                    muted: _muted,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ShortcutCard(
                          icon: Icons.menu_book_rounded,
                          title: 'Kamus Isyarat',
                          subtitle: 'Temukan gerakan baru',
                          onTap: () => onNavigate(2),
                          ink: _ink,
                          blue: _blue,
                          muted: _muted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ShortcutCard(
                          icon: Icons.history_rounded,
                          title: 'Riwayat Deteksi',
                          subtitle: 'Lihat deteksi sebelumnya',
                          onTap: () => onNavigate(3),
                          ink: _ink,
                          blue: _blue,
                          muted: _muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ImageAction(onTap: onUploadTap, ink: _ink, blue: _blue),
                  const SizedBox(height: 12),
                  _GuideAction(
                    onTap: () => _openGuide(context),
                    ink: _ink,
                    blue: _blue,
                    muted: _muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openGuide(BuildContext context) {
    if (onOpenGuide != null) {
      onOpenGuide!();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuidePage(onNavigate: onNavigate),
        ),
      );
    }
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onOpenGuide});

  final VoidCallback onOpenGuide;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8EDF5))),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LatihIsyarat',
                  style: TextStyle(
                    color: HomePage._ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Belajar isyarat, bangun koneksi.',
                  style: TextStyle(color: HomePage._muted, fontSize: 14),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Panduan Penggunaan',
            onPressed: onOpenGuide,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: HomePage._paleBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.help_outline_rounded,
                color: HomePage._blue,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.blue});

  final Color blue;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 160),
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3475FF), Color(0xFF2059E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: blue.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'SETIAP GERAKAN PUNYA ARTI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFDCE7FF),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 11),
                const Text(
                  'Mulai bicara\ndengan tangan.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Satu isyarat, satu langkah lebih dekat.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 104,
              height: 116,
              child: Image.asset(
                'assets/signs/a.png',
                fit: BoxFit.cover,
                semanticLabel: 'Contoh isyarat huruf A',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.onTap,
    required this.ink,
    required this.blue,
    required this.muted,
  });

  final VoidCallback onTap;
  final Color ink;
  final Color blue;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: HomePage._paleBlue,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.center_focus_strong_rounded,
                  color: blue,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deteksi Kamera',
                      style: TextStyle(
                        color: ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gunakan kamera untuk mengenali gerakan',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: blue, size: 23),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.ink,
    required this.blue,
    required this.muted,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color ink;
  final Color blue;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 130,
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: blue, size: 27),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 11, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageAction extends StatelessWidget {
  const _ImageAction({
    required this.onTap,
    required this.ink,
    required this.blue,
  });

  final VoidCallback onTap;
  final Color ink;
  final Color blue;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HomePage._paleBlue,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: blue,
                  size: 25,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Deteksi dari upload',
                  style: TextStyle(
                    color: ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: blue, size: 23),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideAction extends StatelessWidget {
  const _GuideAction({
    required this.onTap,
    required this.ink,
    required this.blue,
    required this.muted,
  });

  final VoidCallback onTap;
  final Color ink;
  final Color blue;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: HomePage._paleBlue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panduan Penggunaan',
                      style: TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fitur deteksi, 24 huruf, dan tips akurasi',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: blue, size: 23),
            ],
          ),
        ),
      ),
    );
  }
}
