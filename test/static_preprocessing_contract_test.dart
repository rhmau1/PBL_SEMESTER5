import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sign_language/services/image_preprocessor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('photo preprocessing matches the shared Colab contract', () {
    final cases = <Map<String, Object?>>[];
    for (final spec in [
      ['center', 65, 49, .25, .2, .75, .8],
      ['edge', 97, 61, .65, .55, .98, .99],
      ['portrait', 43, 101, .02, .01, .4, .48],
    ]) {
      final width = spec[1] as int, height = spec[2] as int;
      final image = img.Image(width: width, height: height, numChannels: 3);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          image.setPixelRgb(
            x,
            y,
            (x * 13 + y * 7) % 256,
            (x * 5 + y * 11) % 256,
            (x * 3 + y * 17) % 256,
          );
        }
      }
      final points = List.generate(
        21,
        (i) => Offset(
          (spec[3] as double) +
              ((spec[5] as double) - (spec[3] as double)) * (i % 7) / 6,
          (spec[4] as double) +
              ((spec[6] as double) - (spec[4] as double)) * (i ~/ 7) / 2,
        ),
      );
      final crops = ImagePreprocessor.imageToGrayHandCrops(
        image,
        normalizedLandmarks: points,
      );
      String hex(img.Image source) =>
          ImagePreprocessor.modelImageToInput(source).single
              .expand((r) => r)
              .map((p) => p.single.toInt().toRadixString(16).padLeft(2, '0'))
              .join();
      cases.add({
        'name': spec[0],
        'width': width,
        'height': height,
        'points': points.map((p) => [p.dx, p.dy]).toList(),
        'context_hex': hex(crops.context),
        'tight_hex': hex(crops.tight),
        'full_hex': hex(ImagePreprocessor.toModelImage(image)),
      });
    }
    final contract = {
      'pattern': 'r=(13x+7y)%256,g=(5x+11y)%256,b=(3x+17y)%256',
      'version': 'grid4_round_luminance_floor_mean_v1',
      'cases': cases,
    };
    final file = File('test/fixtures/static_preprocessing_contract.json');
    if (const bool.fromEnvironment('UPDATE_STATIC_CONTRACT')) {
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(contract),
      );
    }
    expect(jsonDecode(file.readAsStringSync()), contract);
  });
}
