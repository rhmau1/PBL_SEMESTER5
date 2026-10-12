import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history_item.dart';
import '../providers/history_provider.dart';

/// Riwayat foto, upload, latihan huruf, dan satu rangkaian per latihan bebas.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key, this.onNavigate});

  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);
    final hasItems = historyAsync.valueOrNull?.isNotEmpty ?? false;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Riwayat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Hapus semua riwayat',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: hasItems ? () => _confirmClearAll(context, ref) : null,
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Belum ada riwayat deteksi'),
                  SizedBox(height: 4),
                  Text(
                    'Hasil yang disimpan akan muncul di sini.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
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
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _HistoryItemTile(
                item: items[index],
                onOpen: () => _showDetails(context, items[index]),
                onDelete: () =>
                    _confirmDeleteSingle(context, ref, items[index]),
              ),
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Hasil deteksi', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              SelectableText(
                item.gesture,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text('Sumber: ${item.sourceLabel}'),
              Text('Waktu: ${item.date} ${item.time}'),
              Text(
                '${item.source == 'video' ? 'Rata-rata keyakinan huruf' : 'Keyakinan model'}: ${item.confidenceLabel}',
              ),
              const SizedBox(height: 8),
              const Text(
                'Keyakinan model adalah skor prediksi, bukan jaminan hasil benar.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (item.imagePath != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(item.imagePath!),
                    height: 260,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Text('Foto tidak tersedia di perangkat ini.'),
                  ),
                ),
              ],
              if (item.videoPath != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'File rekaman',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  item.videoPath!,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
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
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: onOpen,
          onLongPress: onDelete,
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE8F5E9),
            child: Icon(icon, color: const Color(0xFF2E7D32)),
          ),
          title: Text(
            item.gesture,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${item.sourceLabel} · ${item.date} ${item.time}\n'
            'Keyakinan model: ${item.confidenceLabel}',
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: 'Hapus riwayat',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ),
      ),
    );
  }
}
