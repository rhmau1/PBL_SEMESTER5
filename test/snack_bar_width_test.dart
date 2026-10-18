import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/main.dart';

const _short = 'Gagal';
const _long = 'Hasil tampil, tetapi gagal disimpan ke riwayat: disk penuh';

/// Shows [message] through the app's ScaffoldMessenger and returns the
/// rendered width of the SnackBar with the app's stock theme.
Future<double> _snackBarWidth(
  WidgetTester tester, {
  required Size size,
  required String message,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const ProviderScope(child: MyApp(cameraEnabled: false)),
  );
  await tester.pumpAndSettle();

  final context = tester.element(find.byType(Scaffold).first);
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text(message)));
  await tester.pumpAndSettle();

  final width = tester.getSize(find.byType(SnackBar)).width;

  messenger.hideCurrentSnackBar();
  await tester.pumpAndSettle();
  return width;
}

void main() {
  for (final size in const [Size(360, 800), Size(411, 915)]) {
    testWidgets(
      'snackbar spans the full ${size.width.toInt()}px screen width',
      (tester) async {
        final shortWidth = await _snackBarWidth(
          tester,
          size: size,
          message: _short,
        );
        final longWidth = await _snackBarWidth(
          tester,
          size: size,
          message: _long,
        );

        expect(shortWidth, size.width);
        expect(longWidth, size.width);
        expect(longWidth, shortWidth);
      },
    );
  }
}
