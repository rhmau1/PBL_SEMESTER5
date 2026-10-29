import 'package:flutter/material.dart';

class GuidePage extends StatelessWidget {
  const GuidePage({super.key, this.onNavigate});

  final ValueChanged<int>? onNavigate;

  static const _ink = Color(0xFF172642);
  static const _muted = Color(0xFF7585A2);
  static const _blue = Color(0xFF2864F0);
  static const _paleBlue = Color(0xFFEAF0FF);
  static const _border = Color(0xFFE8EDF5);
  static const _amber = Color(0xFFFFC42E);
  static const _amberBg = Color(0xFFFFF8E9);
  static const _amberBorder = Color(0xFFFFDF83);
  static const _amberText = Color(0xFF9A4D12);

  void _handleNavigate(BuildContext context, int tabIndex) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    onNavigate?.call(tabIndex);
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Panduan Penggunaan',
              style: TextStyle(
                color: _ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Pelajari cara belajar & memaksimalkan deteksi',
              style: TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: _border),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const _GuideHeroBanner(),
            const SizedBox(height: 22),

            const _SectionHeader(
              title: 'Fitur-Fitur Utama',
              subtitle: 'Berbagai mode latihan dan pembelajaran yang tersedia',
            ),
            const SizedBox(height: 12),

            // Fitur 1: Deteksi Video
            _FeatureCard(
              icon: Icons.videocam_rounded,
              iconColor: _blue,
              iconBgColor: _paleBlue,
              title: 'Deteksi dengan Video (Kamera Real-Time)',
              description:
                  'Gunakan kamera secara langsung untuk melatih pose tangan dengan evaluasi instan berbasis kecerdasan buatan (AI).',
              subItems: const [
                _SubItemData(
                  title: 'Mode Latihan Bebas',
                  description:
                      'Peragakan gerakan huruf secara bebas tanpa batas waktu. Sistem akan mengenali dan merangkai huruf demi huruf yang berhasil diperagakan secara berkelanjutan.',
                ),
                _SubItemData(
                  title: 'Mode Uji per Huruf',
                  description:
                      'Pilih satu huruf target yang ingin diuji melalui menu dropdown (misal: Huruf A). Sistem memvalidasi apakah bentuk tangan Anda sudah sesuai dengan target tersebut.',
                ),
                _SubItemData(
                  title: '24 Abjad Didukung (Tanpa J & Z)',
                  description:
                      'Deteksi saat ini mencakup 24 huruf alfabet statis (A–Y, kecuali J dan Z). Huruf J dan Z belum didukung karena membutuhkan deteksi gerakan tangan dinamis (motion gestures), sementara model saat ini difokuskan pada pose statis.',
                  isHighlight: true,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Fitur 2: Deteksi Foto
            const _FeatureCard(
              icon: Icons.camera_alt_rounded,
              iconColor: Color(0xFF00A879),
              iconBgColor: Color(0xFFE8F8F3),
              title: 'Deteksi dari Foto (Mode Foto)',
              description:
                  'Ambil foto pose tangan Anda secara instan menggunakan tombol rana kamera. Foto akan dianalisis secara presisi dan menampilkan huruf yang terdeteksi beserta persentase keyakinan model.',
            ),
            const SizedBox(height: 14),

            // Fitur 3: Upload Gambar
            const _FeatureCard(
              icon: Icons.photo_library_rounded,
              iconColor: Color(0xFF8E44AD),
              iconBgColor: Color(0xFFF4ECF7),
              title: 'Deteksi dari Upload Gambar',
              description:
                  'Unggah foto tangan dari galeri perangkat Anda. Mendukung upload satu gambar maupun banyak gambar sekaligus (batch) untuk evaluasi cepat.',
            ),
            const SizedBox(height: 14),

            // Fitur 4: Riwayat Deteksi
            const _FeatureCard(
              icon: Icons.history_rounded,
              iconColor: Color(0xFFE67E22),
              iconBgColor: Color(0xFFFDF2E9),
              title: 'Riwayat Deteksi Otomatis',
              description:
                  'Setiap kali Anda selesai melakukan deteksi (baik melalui video, foto, maupun upload), hasilnya akan otomatis tersimpan ke halaman Riwayat Deteksi. Anda dapat membuka kembali rekaman latihan, melihat tanggal, sumber deteksi, dan skor keyakinan kapan saja.',
            ),
            const SizedBox(height: 14),

            // Fitur 5: Kamus Isyarat
            const _FeatureCard(
              icon: Icons.menu_book_rounded,
              iconColor: _blue,
              iconBgColor: _paleBlue,
              title: 'Kamus Isyarat Lengkap (A–Z)',
              description:
                  'Menampilkan contoh visual bentuk dan posisi jari tangan untuk seluruh huruf dari A sampai Z. Dilengkapi petunjuk deskriptif cara membentuk setiap huruf sebagai referensi belajar Anda.',
            ),
            const SizedBox(height: 14),

            // Fitur 6: Gamifikasi & Badges
            _FeatureCard(
              icon: Icons.military_tech_rounded,
              iconColor: const Color(0xFFE67E22),
              iconBgColor: const Color(0xFFFFF7E6),
              title: 'Sistem Gamifikasi & Koleksi Badges',
              description:
                  'Aplikasi mencatat secara lokal berapa kali Anda mencoba dan huruf apa saja yang telah dipelajari. Dapatkan badges prestasi sesuai tingkat penguasaan Anda:',
              subItems: const [
                _SubItemData(
                  title: 'Keep learning',
                  description:
                      'Didapat setelah menyelesaikan sesi latihan/deteksi pertama kali.',
                ),
                _SubItemData(
                  title: 'Good',
                  description:
                      'Didapat saat sudah mencoba dan mempelajari minimal 5 huruf berbeda.',
                ),
                _SubItemData(
                  title: 'Excellent',
                  description:
                      'Didapat saat sudah mencoba dan mempelajari minimal 15 huruf alfabet.',
                ),
                _SubItemData(
                  title: 'Perfect',
                  description:
                      'Didapat saat sudah melatih seluruh 24 huruf alfabet yang didukung.',
                ),
                _SubItemData(
                  title: 'Impossible (Tingkat Tertinggi)',
                  description:
                      'Didapat jika berhasil menguasai seluruh huruf sekaligus mencapai 7-day streak latihan berturut-turut.',
                  isHighlight: true,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Disclaimer & Akurasi
            const _DisclaimerCard(),
            const SizedBox(height: 24),

            // Rekomendasi Penggunaan
            const _SectionHeader(
              title: 'Tips & Rekomendasi Penggunaan',
              subtitle: 'Agar model AI dapat mendeteksi tangan dengan akurat',
            ),
            const SizedBox(height: 12),

            const _TipCard(
              icon: Icons.wb_sunny_rounded,
              title: 'Pencahayaan yang Terang & Cukup',
              description:
                  'Gunakan aplikasi di ruangan dengan penerangan yang baik dan merata. Hindari kondisi remang-remang atau backlight (sumber cahaya kuat berada tepat di belakang Anda).',
            ),
            const SizedBox(height: 10),

            const _TipCard(
              icon: Icons.front_hand_rounded,
              title: 'Area Tangan Terlihat Jelas & Tidak Terpotong',
              description:
                  'Posisikan seluruh telapak tangan dan kelima jari berada utuh di dalam bingkai layar kamera. Jangan sampai bagian jari terpotong tepi layar atau tertutup lengan baju dan aksesoris.',
            ),
            const SizedBox(height: 10),

            const _TipCard(
              icon: Icons.wallpaper_rounded,
              title: 'Latar Belakang Sederhana & Tidak Ramai',
              description:
                  'Pilih latar belakang yang polos atau minim distraksi. Hindari background ramai seperti orang berlalu-lalang atau pola dinding yang rumit agar titik-titik tangan (hand landmarks) terdeteksi optimal.',
            ),

            if (onNavigate != null) ...[
              const SizedBox(height: 26),
              const _SectionHeader(
                title: 'Mulai Berlatih Sekarang',
                subtitle: 'Pilih halaman yang ingin Anda tuju',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.center_focus_strong_rounded,
                      label: 'Deteksi Kamera',
                      onTap: () => _handleNavigate(context, 1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.menu_book_rounded,
                      label: 'Buka Kamus',
                      onTap: () => _handleNavigate(context, 2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.history_rounded,
                      label: 'Lihat Riwayat',
                      onTap: () => _handleNavigate(context, 3),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuideHeroBanner extends StatelessWidget {
  const _GuideHeroBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 140),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3475FF), Color(0xFF2059E8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x382864F0),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 14,
                ),
                SizedBox(width: 6),
                Text(
                  'TENTANG APLIKASI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Belajar Bahasa Isyarat\nMandiri & Interaktif',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'LatihIsyarat dirancang untuk membantu Anda mempelajari abjad bahasa isyarat (American Sign Language / ASL fingerspelling) melalui teknologi Computer Vision secara praktis langsung dari perangkat Anda.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: GuidePage._ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: GuidePage._muted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _SubItemData {
  const _SubItemData({
    required this.title,
    required this.description,
    this.isHighlight = false,
  });

  final String title;
  final String description;
  final bool isHighlight;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.description,
    this.subItems = const [],
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String description;
  final List<_SubItemData> subItems;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: GuidePage._border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0E2343),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: GuidePage._ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        color: GuidePage._muted,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (subItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: GuidePage._border),
            const SizedBox(height: 12),
            for (final sub in subItems) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: sub.isHighlight
                      ? GuidePage._amberBg
                      : const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: sub.isHighlight
                        ? GuidePage._amberBorder
                        : const Color(0xFFE8EEF7),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      sub.isHighlight
                          ? Icons.info_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                      color: sub.isHighlight
                          ? GuidePage._amberText
                          : GuidePage._blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sub.title,
                            style: TextStyle(
                              color: sub.isHighlight
                                  ? GuidePage._amberText
                                  : GuidePage._ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            sub.description,
                            style: TextStyle(
                              color: sub.isHighlight
                                  ? const Color(0xFF7A3E0E)
                                  : GuidePage._muted,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GuidePage._amberBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: GuidePage._amberBorder, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C9A4D12),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: GuidePage._amber,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: GuidePage._ink,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PENTING: DISCLAIMER AKURASI',
                      style: TextStyle(
                        color: GuidePage._amberText,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Model Bisa Saja Salah Mendeteksi',
                      style: TextStyle(
                        color: GuidePage._ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Model AI dibangun menggunakan algoritma visi komputer yang memberikan estimasi berdasarkan kecocokan pola tangan. Oleh karena itu:',
            style: TextStyle(
              color: Color(0xFF6B3E14),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          _buildBullet(
            'Akurasi yang diberikan belum tentu 100% benar pada setiap kondisi pencahayaan atau sudut pengambilan.',
          ),
          const SizedBox(height: 6),
          _buildBullet(
            'Pastikan untuk selalu melakukan cek manual di halaman Kamus Isyarat jika hasil deteksi terasa meragukan atau tidak sesuai.',
          ),
          const SizedBox(height: 6),
          _buildBullet(
            'Jadikan hasil deteksi sebagai sarana latihan dan evaluasi, bukan tolok ukur mutlak.',
          ),
        ],
      ),
    );
  }

  static Widget _buildBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(
            Icons.circle,
            size: 6,
            color: GuidePage._amberText,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF6B3E14),
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: GuidePage._border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080E2343),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: GuidePage._paleBlue,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: GuidePage._blue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: GuidePage._ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: GuidePage._muted,
                    fontSize: 12,
                    height: 1.45,
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

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GuidePage._border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: GuidePage._paleBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: GuidePage._blue, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: GuidePage._ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
