import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/widgets/session_result_sheet.dart';

const _sheetKey = ValueKey('session-result-sheet');

Future<void> _pumpSheet(
  WidgetTester tester, {
  required List<String> letters,
  String target = '',
  String? savedVideoPath,
  Size size = const Size(360, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SessionResultSheet(
            letters: letters,
            target: target,
            savedVideoPath: savedVideoPath,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('fills the width of a 360x800 screen', (tester) async {
    await _pumpSheet(tester, letters: const ['A', 'B']);

    final size = tester.getSize(find.byKey(_sheetKey));
    expect(size.width, 360);
  });

  testWidgets('fills the width of a 411x915 screen', (tester) async {
    await _pumpSheet(
      tester,
      letters: const ['A', 'B'],
      size: const Size(411, 915),
    );

    final size = tester.getSize(find.byKey(_sheetKey));
    expect(size.width, 411);
  });

  testWidgets('opens at the same 50% height for 2 and 12 letters',
      (tester) async {
    await _pumpSheet(tester, letters: const ['A', 'B']);
    final shortHeight = tester.getSize(find.byKey(_sheetKey)).height;

    await _pumpSheet(
      tester,
      letters: const ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L'],
    );
    final longHeight = tester.getSize(find.byKey(_sheetKey)).height;

    expect(shortHeight, closeTo(400, 1));
    expect(longHeight, closeTo(400, 1));
    expect(longHeight, shortHeight);
  });

  testWidgets('20 letters do not overflow and stay under the max height',
      (tester) async {
    const letters = [
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
      'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    ];
    await _pumpSheet(tester, letters: letters);

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byKey(_sheetKey));
    expect(size.height, lessThanOrEqualTo(0.85 * 800));
  });

  testWidgets('target mode shows the target title and validation summary',
      (tester) async {
    await _pumpSheet(
      tester,
      letters: const ['A', 'C', 'C'],
      target: 'C',
    );

    expect(find.text('Hasil uji target C'), findsOneWidget);
    expect(find.text('Validasi target C: 2/3 benar (66.7%).'), findsOneWidget);
  });

  testWidgets('empty letters show the empty state message', (tester) async {
    await _pumpSheet(tester, letters: const []);

    expect(find.text('Belum ada huruf yang stabil.'), findsOneWidget);
  });

  testWidgets('renders the saved video path when provided', (tester) async {
    const path = '/data/user/0/app/files/recordings/asl_session.mp4';
    await _pumpSheet(
      tester,
      letters: const ['A'],
      savedVideoPath: path,
    );

    expect(find.textContaining('Video tersimpan di:'), findsOneWidget);
    expect(find.textContaining(path), findsOneWidget);
  });
}
