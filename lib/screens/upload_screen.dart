import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/history_item.dart';
import '../models/sign_prediction.dart';
import '../services/sign_classifier.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({
    super.key,
    this.onResultSaved,
    this.onBusyChanged,
    this.pickFiles,
    this.classifyFile,
    this.saveImage,
  });

  final Future<void> Function(HistoryItem)? onResultSaved;
  final ValueChanged<bool>? onBusyChanged;
  final Future<List<XFile>> Function(bool multiple)? pickFiles;
  final Future<SignPrediction> Function(String path)? classifyFile;
  final Future<String> Function(XFile file)? saveImage;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  static const _minimumConfidence = 0.60;
  final _picker = ImagePicker();
  final _results = <_UploadResult>[];
  bool _isProcessing = false;

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() => _isProcessing = value);
    widget.onBusyChanged?.call(value);
  }

  Future<List<XFile>> _pickFiles(bool multiple) async {
    if (multiple) {
      return _picker.pickMultiImage(requestFullMetadata: false);
    }
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    return file == null ? [] : [file];
  }

  Future<String> _saveImage(XFile file) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = await Directory('${documents.path}/uploads')
        .create(recursive: true);
    // Preserve the original bytes and extension; the decoder handles EXIF.
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    final safeExtension = RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : 'jpg';
    final path =
        '${directory.path}/upload_${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
    await file.saveTo(path);
    return path;
  }

  Future<void> _pickAndClassify(bool multiple) async {
    if (_isProcessing) return;
    _setBusy(true);
    try {
      final files = await (widget.pickFiles ?? _pickFiles)(multiple);
      if (!mounted || files.isEmpty) return;
      setState(_results.clear);
      for (final file in files) {
        if (!mounted) return;
        String path = file.path;
        SignPrediction? prediction;
        String? error;
        String? historyError;
        try {
          prediction =
              await (widget.classifyFile ??
                  SignClassifier.instance.classifyUploadFile)(path);
        } catch (failure) {
          error = '$failure';
        }
        if (!mounted) return;
        if (prediction != null &&
            prediction.confidence >= _minimumConfidence &&
            widget.onResultSaved != null) {
          try {
            path = await (widget.saveImage ?? _saveImage)(file);
            if (!mounted) return;
            await widget.onResultSaved!(
              HistoryItem.fromDetection(
                gesture: prediction.label,
                confidence: prediction.confidence,
                source: 'upload',
                imagePath: path,
              ),
            );
          } catch (failure) {
            historyError = 'Riwayat belum tersimpan: $failure';
          }
        }
        if (!mounted) return;
        setState(
          () => _results.add(
            _UploadResult(
              path: path,
              prediction: prediction,
              error: error,
              historyError: historyError,
            ),
          ),
        );
      }
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tidak dapat membuka gambar: $failure')),
        );
      }
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('upload'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uji Gambar',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pilih satu gambar untuk diuji sebagai satu huruf, atau beberapa gambar sekaligus untuk diuji berurutan.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'MediaPipe mencari dan memotong area tangan secara otomatis. Gunakan satu tangan dengan seluruh jari terlihat.',
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => _pickAndClassify(false),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Satu gambar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _pickAndClassify(true),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Banyak gambar'),
                      ),
                    ),
                  ],
                ),
                if (_isProcessing) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text('Memproses gambar ${_results.length + 1}...'),
                ],
              ],
            ),
          ),
        ),
        if (_results.isEmpty && !_isProcessing)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Belum ada gambar')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList.list(
              children: [
                _UploadSummary(results: _results),
                const SizedBox(height: 14),
                for (var index = 0; index < _results.length; index++) ...[
                  _ResultCard(result: _results[index], index: index),
                  if (index < _results.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _UploadResult {
  const _UploadResult({
    required this.path,
    this.prediction,
    this.error,
    this.historyError,
  });
  final String path;
  final SignPrediction? prediction;
  final String? error;
  final String? historyError;
  bool get accepted =>
      prediction != null &&
      prediction!.confidence >= _UploadScreenState._minimumConfidence;
}

class _UploadSummary extends StatelessWidget {
  const _UploadSummary({required this.results});
  final List<_UploadResult> results;

  @override
  Widget build(BuildContext context) {
    final letters = results
        .where((result) => result.accepted)
        .map((result) => result.prediction!.label)
        .join();
    return Card(
      color: const Color(0xFFE0EFE9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Urutan hasil tanpa spasi',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              letters.isEmpty ? 'Belum ada hasil yang cukup yakin' : letters,
              key: const ValueKey('upload-letters'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.index});
  final _UploadResult result;
  final int index;

  @override
  Widget build(BuildContext context) {
    final prediction = result.prediction;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: Image.file(
                File(result.path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gambar ${index + 1}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (prediction == null)
                    Text('Gagal memproses: ${result.error}')
                  else ...[
                    Text(
                      result.accepted
                          ? prediction.label
                          : 'Belum yakin (${prediction.label})',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text('Keyakinan ${prediction.confidenceText}'),
                    if (result.historyError != null) Text(result.historyError!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
