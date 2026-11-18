import 'dart:convert';
import 'dart:io';

import 'package:sign_language/services/svm_hog_input.dart';
import 'package:sign_language/services/svm_hog_model.dart';

void main(List<String> args) {
  if (args.isEmpty ||
      args.length > 2 ||
      (args.length == 2 && args[1] != '--wide')) {
    stderr.writeln(
      'Usage: dart run tooling/probe_svm_hog_photos.dart PHOTO_DIR [--wide]',
    );
    exitCode = 64;
    return;
  }
  final model = SvmHogModel(
    File('assets/models/svm_hog.bin.gz').readAsBytesSync(),
  );
  final directory = Directory(args.first);
  final manifest = jsonDecode(
    File('${directory.path}/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  var correct = 0, incorrect = 0, rejected = 0;
  final elapsed = Stopwatch()..start();
  for (final item
      in (manifest['photos'] as List).cast<Map<String, dynamic>>()) {
    if (item['static_24_eligible'] != true) continue;
    final path = '${directory.path}/${item['filename']}';
    final image = SvmHogInput.decode(File(path).readAsBytesSync())!;
    final preparation = SvmHogInput.prepareHandCrops(
      image,
      tightFraming: args.length == 1,
    );
    final predictions = preparation.crops
        .map((crop) => model.predict(SvmHogModel.hog(crop)).label)
        .toList();
    final accepted =
        predictions.length == 2 && predictions[0] == predictions[1];
    if (!accepted) {
      rejected++;
    } else if (predictions[0] == item['target_from_filename']) {
      correct++;
    } else {
      incorrect++;
    }
    stdout.writeln(
      '${item['filename']}: ${predictions.join('/')} '
      '${preparation.rejection ?? (accepted ? '' : '(crop berbeda)')}',
    );
  }
  stdout.writeln(
    'Benar: $correct, salah: $incorrect, ditolak: $rejected, ms: ${elapsed.elapsedMilliseconds}',
  );
}
