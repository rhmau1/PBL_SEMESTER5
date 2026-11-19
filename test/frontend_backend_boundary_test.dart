import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sign_language/screens/upload_screen.dart';

void main() {
  testWidgets('missing upload file produces no saved recognition', (
    tester,
  ) async {
    var saved = 0;
    final busy = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UploadScreen(
            pickFiles: (_) async => [XFile('photo-a.jpg')],
            onResultSaved: (_) async {
              saved++;
            },
            onBusyChanged: busy.add,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pilih gambar tangan'));
    for (var poll = 0; !busy.contains(false) && poll < 100; poll++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('File gambar tidak ditemukan.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('File gambar tidak ditemukan.'), findsOneWidget);
    expect(saved, 0);
    expect(busy, [true, false]);
    expect(tester.takeException(), isNull);
  });
}
