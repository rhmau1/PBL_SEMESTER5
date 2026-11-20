import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sign_language/services/svm_hog_classifier.dart';

void main() => runApp(const MaterialApp(home: PhotoQa()));

class PhotoQa extends StatefulWidget {
  const PhotoQa({super.key});

  @override
  State<PhotoQa> createState() => _PhotoQaState();
}

typedef Photo = ({String path, String name, String? expected});
typedef Result = ({
  Photo photo,
  String? prediction,
  String status,
  String? reason,
  int milliseconds,
});

class _PhotoQaState extends State<PhotoQa> {
  final List<Result> _results = [];
  bool _busy = false;
  String? _message;

  Future<void> _test(
    Future<List<Photo>> Function() load, {
    bool save = false,
  }) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final photos = await load();
      if (photos.isEmpty || !mounted) return;
      setState(_results.clear);
      final classifier = SvmHogClassifier.instance;
      final startup = Stopwatch()..start();
      await classifier.initialize();
      startup.stop();
      for (final photo in photos) {
        if (!mounted) return;
        final elapsed = Stopwatch()..start();
        String? label;
        String? reason;
        String status;
        try {
          final result = await classifier.classifyFile(photo.path);
          label = result.label;
          status = result.accepted ? 'accepted' : 'crop_disagreement';
        } on FormatException catch (error) {
          status = 'input_rejected';
          reason = error.message;
        } catch (error) {
          status = 'error';
          reason = error.toString();
        }
        if (!mounted) return;
        setState(
          () => _results.add((
            photo: photo,
            prediction: label,
            status: status,
            reason: reason,
            milliseconds: elapsed.elapsedMilliseconds,
          )),
        );
      }
      if (save) {
        final directory = await getApplicationDocumentsDirectory();
        final report = {
          'model': SvmHogClassifier.modelId,
          'initialize_ms': startup.elapsedMilliseconds,
          'results': _results
              .map(
                (result) => {
                  'photo': result.photo.name,
                  'expected': result.photo.expected,
                  'prediction': result.prediction,
                  'status': result.status,
                  'reason': result.reason,
                  'ms': result.milliseconds,
                },
              )
              .toList(),
        };
        await File('${directory.path}/svm_qa_report.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<Photo>> _fixtures() async {
    final directory = await getApplicationDocumentsDirectory();
    final root = '${directory.path}/svm_qa_photos';
    final manifest = jsonDecode(
      await File('$root/manifest.json').readAsString(),
    ) as Map<String, dynamic>;
    return (manifest['photos'] as List)
        .cast<Map<String, dynamic>>()
        .where((photo) => photo['static_24_eligible'] == true)
        .map(
          (photo) => (
            path: '$root/${photo['filename']}',
            name: photo['filename'] as String,
            expected: photo['target_from_filename'] as String?,
          ),
        )
        .toList();
  }

  Future<List<Photo>> _pick(bool multiple) async {
    final picker = ImagePicker();
    final XFile? single = multiple
        ? null
        : await picker.pickImage(source: ImageSource.gallery);
    final files = multiple
        ? await picker.pickMultiImage()
        : [?single];
    return files
        .map((file) => (path: file.path, name: file.name, expected: null))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final labeled = _results.where((result) => result.photo.expected != null);
    final correct = labeled
        .where(
          (result) =>
              result.status == 'accepted' &&
              result.prediction == result.photo.expected,
        )
        .length;
    final wrong = labeled
        .where(
          (result) =>
              result.status == 'accepted' &&
              result.prediction != result.photo.expected,
        )
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('LatihIsyarat QA')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _test(() => _pick(false)),
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('Pilih satu foto'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _test(() => _pick(true)),
                    icon: const Icon(Icons.collections_outlined),
                    label: const Text('Pilih banyak foto'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _test(_fixtures, save: true),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Uji foto Drive'),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_message!),
              ),
            if (labeled.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '$correct benar · $wrong salah · ${labeled.length - correct - wrong} tanpa hasil',
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final result = _results[index];
                  final label = switch (result.status) {
                    'accepted' => result.prediction!,
                    'crop_disagreement' => 'Belum yakin',
                    _ => result.reason ?? 'Gagal diproses',
                  };
                  return ListTile(
                    leading: Image.file(
                      File(result.photo.path),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                    title: Text(result.photo.name),
                    subtitle: Text(
                      result.photo.expected == null
                          ? label
                          : 'Target ${result.photo.expected} · $label',
                    ),
                    trailing: Text('${result.milliseconds} ms'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
