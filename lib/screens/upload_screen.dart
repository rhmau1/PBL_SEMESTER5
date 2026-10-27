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
  bool _multipleImages = false;

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
                  SignClassifier.instance.classifyFile)(path);
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
    const ink = Color(0xFF172642);
    const muted = Color(0xFF7585A2);
    const blue = Color(0xFF2864F0);
    return CustomScrollView(
      key: const PageStorageKey('upload'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Uji Gambar',
                        style: TextStyle(
                          color: ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEAF0FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: blue,
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pilih foto tangan untuk menguji deteksi abjad isyarat. Pastikan posisi jari jelas dan pencahayaan cukup.',
                  style: TextStyle(color: Color(0xFF52627D), height: 1.5),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _multipleImages
                              ? Colors.white
                              : blue,
                          foregroundColor: _multipleImages ? ink : Colors.white,
                          minimumSize: const Size(0, 52),
                          side: BorderSide(
                            color: _multipleImages
                                ? const Color(0xFFDCE4F1)
                                : Colors.transparent,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => setState(() => _multipleImages = false),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Satu gambar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _multipleImages
                              ? blue
                              : Colors.white,
                          foregroundColor: _multipleImages ? Colors.white : ink,
                          minimumSize: const Size(0, 52),
                          side: BorderSide(
                            color: _multipleImages
                                ? Colors.transparent
                                : const Color(0xFFDCE4F1),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: _isProcessing
                            ? null
                            : () => setState(() => _multipleImages = true),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Banyak gambar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E9),
                    border: Border.all(color: const Color(0xFFFFDF83)),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_rounded,
                        color: Color(0xFFE7A514),
                        size: 22,
                      ),
                      SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tips hasil akurat',
                              style: TextStyle(
                                color: ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Gunakan satu tangan dengan seluruh jari terlihat dan latar belakang sederhana.',
                              style: TextStyle(
                                color: muted,
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
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyUploadState(
              isProcessing: _isProcessing,
              multipleImages: _multipleImages,
              onTap: _isProcessing
                  ? null
                  : () => _pickAndClassify(_multipleImages),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList.list(
              children: [
                _UploadSummary(results: _results),
                const SizedBox(height: 14),
                _UploadActionButton(
                  isProcessing: _isProcessing,
                  multipleImages: _multipleImages,
                  onTap: _isProcessing
                      ? null
                      : () => _pickAndClassify(_multipleImages),
                ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0FF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'URUTAN HASIL TANPA SPASI',
            style: TextStyle(
              color: Color(0xFF7585A2),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            letters.isEmpty ? 'Belum ada hasil yang cukup yakin' : letters,
            key: const ValueKey('upload-letters'),
            style: const TextStyle(
              color: Color(0xFF2864F0),
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ],
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
    final accepted = result.accepted;
    final confidence = prediction?.confidence ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E2343),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: SizedBox(
                  width: 82,
                  height: 104,
                  child: Image.file(
                    File(result.path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFFEAF0FF),
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Color(0xFF7585A2),
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Gambar ${index + 1}',
                            style: const TextStyle(
                              color: Color(0xFF172642),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          accepted
                              ? Icons.check_circle_outline_rounded
                              : Icons.info_outline_rounded,
                          color: accepted
                              ? const Color(0xFF00B982)
                              : const Color(0xFFE3A21A),
                          size: 22,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'HASIL DETEKSI',
                      style: TextStyle(
                        color: Color(0xFF7585A2),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (prediction == null)
                      Text(
                        'Gagal memproses: ${result.error}',
                        style: const TextStyle(color: Color(0xFFC43D3D)),
                      )
                    else ...[
                      Text(
                        accepted
                            ? prediction.label
                            : 'Belum yakin (${prediction.label})',
                        style: const TextStyle(
                          color: Color(0xFF172642),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Keyakinan ${prediction.confidenceText}',
                        style: TextStyle(
                          color: accepted
                              ? const Color(0xFF00A879)
                              : const Color(0xFFAE7010),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          value: confidence.clamp(0.0, 1.0).toDouble(),
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE9EEF6),
                          color: accepted
                              ? const Color(0xFF13B986)
                              : const Color(0xFFE5AA33),
                        ),
                      ),
                      if (result.historyError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.historyError!,
                          style: const TextStyle(
                            color: Color(0xFFC43D3D),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (prediction == null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3DD),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'Perlu foto lebih jelas',
                  style: TextStyle(
                    color: Color(0xFFAE7010),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyUploadState extends StatelessWidget {
  const _EmptyUploadState({
    required this.isProcessing,
    required this.multipleImages,
    required this.onTap,
  });

  final bool isProcessing;
  final bool multipleImages;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFB8CCFF), width: 1.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: Color(0xFF2864F0),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 13),
                const Text(
                  'Upload Foto Isyarat',
                  style: TextStyle(
                    color: Color(0xFF172642),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Pilih foto tangan dari galeri untuk mulai mendeteksi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF7585A2),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _UploadActionButton(
                  isProcessing: isProcessing,
                  multipleImages: multipleImages,
                  onTap: onTap,
                ),
                const SizedBox(height: 10),
                const Text(
                  'JPG, PNG, dan format gambar yang didukung',
                  style: TextStyle(color: Color(0xFF8A9AB5), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.bolt_rounded, color: Color(0xFFE8A11A), size: 20),
              SizedBox(width: 6),
              Text(
                'Contoh isyarat',
                style: TextStyle(
                  color: Color(0xFF172642),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final letter in ['a', 'b', 'c']) ...[
                if (letter != 'a') const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.asset(
                            'assets/signs/$letter.png',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          letter.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF2864F0),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _UploadActionButton extends StatelessWidget {
  const _UploadActionButton({
    required this.isProcessing,
    required this.multipleImages,
    required this.onTap,
  });

  final bool isProcessing;
  final bool multipleImages;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2864F0),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(
          isProcessing
              ? Icons.hourglass_top_rounded
              : Icons.folder_open_rounded,
        ),
        label: Text(
          isProcessing
              ? 'Memproses gambar...'
              : multipleImages
              ? 'Pilih banyak gambar'
              : 'Pilih gambar tangan',
        ),
      ),
    );
  }
}
