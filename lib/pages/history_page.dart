import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history_item.dart';
import '../providers/history_provider.dart';

/// Riwayat foto, upload, latihan huruf, dan satu rangkaian per latihan bebas.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.onNavigate});

  final ValueChanged<int>? onNavigate;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

enum _HistoryFilter { all, camera, upload }

class _HistoryPageState extends ConsumerState<HistoryPage> {
  _HistoryFilter _selectedFilter = _HistoryFilter.all;

  List<HistoryItem> _filterItems(List<HistoryItem> items) {
    return switch (_selectedFilter) {
      _HistoryFilter.all => items,
      _HistoryFilter.camera =>
        items.where((item) => item.source != 'upload').toList(),
      _HistoryFilter.upload =>
        items.where((item) => item.source == 'upload').toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(historyProvider);
    final items = historyAsync.valueOrNull ?? const <HistoryItem>[];
    final hasItems = items.isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 88,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Riwayat',
              style: TextStyle(
                color: Color(0xFF172642),
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Sesi latihan aktif · ${items.length} item',
              style: const TextStyle(
                color: Color(0xFF7585A2),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Hapus semua riwayat',
            icon: const Icon(Icons.delete_sweep_outlined),
            color: const Color(0xFFE05A61),
            onPressed: hasItems ? () => _confirmClearAll(context, ref) : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF2864F0)),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                const Text(
                  'Riwayat belum dapat dibaca. Coba muat ulang.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    try {
                      await ref.read(historyProvider.notifier).loadHistory();
                    } catch (_) {
                      // Provider menampilkan status gagal; tombol tetap bisa dicoba.
                    }
                  },
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 54,
                        color: Color(0xFF8A9AB5),
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Belum ada riwayat deteksi',
                        style: TextStyle(
                          color: Color(0xFF172642),
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Hasil yang disimpan akan muncul di sini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF7585A2)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final filteredItems = _filterItems(items);
          return RefreshIndicator(
            onRefresh: () async {
              try {
                await ref.read(historyProvider.notifier).loadHistory();
              } catch (_) {
                // Status gagal muncul di halaman.
              }
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              itemCount: filteredItems.isEmpty ? 2 : filteredItems.length + 1,
              separatorBuilder: (_, index) =>
                  SizedBox(height: index == 0 ? 20 : 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _HistoryFilterBar(
                    selected: _selectedFilter,
                    onSelected: (filter) =>
                        setState(() => _selectedFilter = filter),
                  );
                }
                if (filteredItems.isEmpty && index == 1) {
                  return _FilteredHistoryEmpty(filter: _selectedFilter);
                }
                final item = filteredItems[index - 1];
                return _HistoryItemTile(
                  item: item,
                  onOpen: () => _showDetails(context, item),
                  onDelete: () => _confirmDeleteSingle(context, ref, item),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus semua riwayat?'),
        content: const Text(
          'Semua catatan deteksi akan dihapus. File foto dan video tidak dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(historyProvider.notifier).clearAllHistory();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua riwayat telah dihapus')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Riwayat gagal dihapus. Coba lagi.')),
      );
    }
  }

  Future<void> _confirmDeleteSingle(
    BuildContext context,
    WidgetRef ref,
    HistoryItem item,
  ) async {
    if (item.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus riwayat?'),
        content: Text(
          'Hapus hasil "${item.gesture}" pada ${item.date} ${item.time}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(historyProvider.notifier).removeHistory(item.id!);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Riwayat telah dihapus')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Riwayat gagal dihapus. Coba lagi.')),
      );
    }
  }

  void _showDetails(BuildContext context, HistoryItem item) {
    final confidence =
        item.confidence ??
        (double.tryParse(item.accuracy.replaceAll('%', '')) ?? 0) / 100;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F7FC),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF0FF),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'DETAIL DETEKSI',
                      style: TextStyle(
                        color: Color(0xFF2864F0),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(ctx),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF7585A2),
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              SelectableText(
                item.gesture,
                style: const TextStyle(
                  color: Color(0xFF172642),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 14),
              if (item.imagePath != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140E2343),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Image.file(
                      File(item.imagePath!),
                      height: 250,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 180,
                        child: Center(
                          child: Text(
                            'Foto tidak tersedia di perangkat ini.',
                            style: TextStyle(color: Color(0xFF7585A2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5EBF4)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DetailInfo(
                            label: 'Sumber Media',
                            value: item.sourceLabel,
                            icon: switch (item.source) {
                              'video' => Icons.videocam_rounded,
                              'photo' => Icons.camera_alt_rounded,
                              'upload' => Icons.photo_library_rounded,
                              _ => Icons.sign_language_rounded,
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DetailInfo(
                            label: 'Waktu Deteksi',
                            value: '${item.date} ${item.time}',
                            icon: Icons.schedule_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFE9EEF6)),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.source == 'video' ? 'Rata-rata keyakinan huruf' : 'Keyakinan model'}: ${item.confidenceLabel}',
                            style: const TextStyle(
                              color: Color(0xFF2864F0),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (confidence >= 0.6)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF0FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Terdeteksi',
                              style: TextStyle(
                                color: Color(0xFF2864F0),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: confidence.clamp(0.0, 1.0).toDouble(),
                        minHeight: 8,
                        backgroundColor: const Color(0xFFE2E9F3),
                        color: const Color(0xFF2864F0),
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Keyakinan model adalah skor prediksi, bukan jaminan hasil pasti benar.',
                        style: TextStyle(
                          color: Color(0xFF8A9AB5),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (item.videoPath != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'File rekaman',
                        style: TextStyle(
                          color: Color(0xFF172642),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        item.videoPath!,
                        style: const TextStyle(
                          color: Color(0xFF7585A2),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({required this.selected, required this.onSelected});

  final _HistoryFilter selected;
  final ValueChanged<_HistoryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _HistoryFilterChip(
            label: 'Semua deteksi',
            selected: selected == _HistoryFilter.all,
            onTap: () => onSelected(_HistoryFilter.all),
          ),
          const SizedBox(width: 8),
          _HistoryFilterChip(
            label: 'Kamera',
            selected: selected == _HistoryFilter.camera,
            onTap: () => onSelected(_HistoryFilter.camera),
          ),
          const SizedBox(width: 8),
          _HistoryFilterChip(
            label: 'Upload',
            selected: selected == _HistoryFilter.upload,
            onTap: () => onSelected(_HistoryFilter.upload),
          ),
        ],
      ),
    );
  }
}

class _HistoryFilterChip extends StatelessWidget {
  const _HistoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF2864F0) : Colors.white,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF7585A2),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilteredHistoryEmpty extends StatelessWidget {
  const _FilteredHistoryEmpty({required this.filter});

  final _HistoryFilter filter;

  @override
  Widget build(BuildContext context) {
    final (title, description, icon) = switch (filter) {
      _HistoryFilter.all => (
        'Belum ada riwayat deteksi',
        'Hasil deteksi yang disimpan akan muncul di sini.',
        Icons.history_rounded,
      ),
      _HistoryFilter.camera => (
        'Belum ada deteksi kamera',
        'Hasil dari mode Foto atau Video akan muncul di sini setelah deteksi tersimpan.',
        Icons.camera_alt_outlined,
      ),
      _HistoryFilter.upload => (
        'Belum ada deteksi upload',
        'Hasil deteksi dari gambar yang diunggah akan muncul di sini setelah tersimpan.',
        Icons.photo_library_outlined,
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: const Color(0xFF8A9AB5)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF172642),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF7585A2),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryItemTile extends StatelessWidget {
  const _HistoryItemTile({
    required this.item,
    required this.onOpen,
    required this.onDelete,
  });

  final HistoryItem item;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2864F0);
    const ink = Color(0xFF172642);
    const muted = Color(0xFF7585A2);
    final icon = switch (item.source) {
      'video' => Icons.videocam_outlined,
      'photo' => Icons.camera_alt_outlined,
      'upload' => Icons.photo_library_outlined,
      'target' => Icons.sign_language_outlined,
      _ => Icons.history,
    };
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        color: Colors.red.shade50,
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onOpen,
          onLongPress: onDelete,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: item.imagePath == null
                        ? Container(
                            color: const Color(0xFFEAF0FF),
                            child: Icon(icon, color: blue, size: 27),
                          )
                        : Image.file(
                            File(item.imagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFFEAF0FF),
                              child: Icon(icon, color: blue, size: 27),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.gesture,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.sourceLabel} · ${item.date} ${item.time}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Keyakinan model: ${item.confidenceLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color:
                            item.confidence != null && item.confidence! >= 0.75
                            ? const Color(0xFFE3F8EF)
                            : const Color(0xFFEAF0FF),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        item.confidenceLabel,
                        style: TextStyle(
                          color:
                              item.confidence != null &&
                                  item.confidence! >= 0.75
                              ? const Color(0xFF00A879)
                              : blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 34,
                      height: 30,
                      child: IconButton(
                        tooltip: 'Hapus riwayat',
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        color: const Color(0xFF9AA8BD),
                        onPressed: onDelete,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailInfo extends StatelessWidget {
  const _DetailInfo({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF8A9AB5), fontSize: 11),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Icon(icon, color: const Color(0xFF2864F0), size: 17),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF172642),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
