import 'package:flutter/material.dart';

import '../models/sign_guide_item.dart';

class SignGuideScreen extends StatelessWidget {
  const SignGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF172642);
    const muted = Color(0xFF7585A2);
    return CustomScrollView(
      key: const PageStorageKey('sign-guide'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0FF),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'KAMUS ISYARAT ASL',
                    style: TextStyle(
                      color: Color(0xFF2864F0),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Rumus Sign Language',
                  style: const TextStyle(
                    color: ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pilih huruf untuk melihat cara membentuk ejaan jari ASL secara presisi.',
                  style: TextStyle(color: muted, height: 1.5),
                ),
                const SizedBox(height: 18),
                const _MotionNotice(),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          sliver: SliverGrid.builder(
            itemCount: signGuideItems.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 112,
              mainAxisExtent: 142,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final item = signGuideItems[index];
              return _LetterCard(item: item);
            },
          ),
        ),
      ],
    );
  }
}

class _MotionNotice extends StatelessWidget {
  const _MotionNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E2343),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFC42E),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.lightbulb_rounded,
                color: Color(0xFF172642),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Catatan gestur dinamis',
                    style: TextStyle(
                      color: Color(0xFF172642),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Huruf J dan Z memakai gerakan, sehingga belum dinilai oleh model gambar statis.',
                    style: TextStyle(
                      color: Color(0xFF9A4D12),
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
    );
  }
}

class _LetterCard extends StatelessWidget {
  const _LetterCard({required this.item});

  final SignGuideItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: item.imageAsset == null
                          ? Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                item.letter,
                                style: const TextStyle(
                                  color: Color(0xFF9A4D12),
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                item.imageAsset!,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: item.requiresMotion
                              ? const Color(0xFFFFC42E)
                              : const Color(0xB8172642),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.requiresMotion ? 'GERAKAN' : 'ASL',
                          style: TextStyle(
                            color: item.requiresMotion
                                ? const Color(0xFF172642)
                                : Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  item.letter,
                  style: const TextStyle(
                    color: Color(0xFF172642),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF4F7FC),
      builder: (context) => SingleChildScrollView(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _DetailBadge(
                      text: 'PANDUAN ASL',
                      background: const Color(0xFFEAF0FF),
                      foreground: const Color(0xFF2864F0),
                    ),
                    const SizedBox(width: 8),
                    _DetailBadge(
                      text: item.requiresMotion ? 'Gerakan' : 'Huruf statis',
                      background: item.requiresMotion
                          ? const Color(0xFFFFF1D6)
                          : const Color(0xFFE3F8EF),
                      foreground: item.requiresMotion
                          ? const Color(0xFF92610A)
                          : const Color(0xFF00A879),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF7585A2),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (item.imageAsset != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140E2343),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        item.imageAsset!,
                        width: double.infinity,
                        height: 240,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    height: 200,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      '${item.letter} · membutuhkan gerakan',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9A4D12),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE5EBF4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF0FF),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Text(
                              item.letter,
                              style: const TextStyle(
                                color: Color(0xFF2864F0),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Bentuk tangan huruf ${item.letter}',
                                  style: const TextStyle(
                                    color: Color(0xFF172642),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'American Sign Language (ASL)',
                                  style: TextStyle(
                                    color: Color(0xFF2864F0),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        item.instruction,
                        style: const TextStyle(
                          color: Color(0xFF52627D),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      if (item.requiresMotion) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Model saat ini tidak mengenali huruf ini.',
                          style: TextStyle(
                            color: Color(0xFF9A4D12),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEAF0FF),
                      foregroundColor: const Color(0xFF2864F0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Paham'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
