import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sign_language/screens/upload_screen.dart';
import 'package:sign_language/services/sign_classifier.dart';

void main() {
  testWidgets('unconfigured backend produces no saved recognition', (
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
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining(SignClassifier.unavailableMessage),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining(SignClassifier.unavailableMessage),
      findsOneWidget,
    );
    expect(saved, 0);
    expect(busy, [true, false]);
    expect(tester.takeException(), isNull);
  });
}
