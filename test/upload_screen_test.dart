import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sign_language/models/history_item.dart';
import 'package:sign_language/models/sign_prediction.dart';
import 'package:sign_language/screens/upload_screen.dart';

SignPrediction prediction(String label, double confidence) => SignPrediction(
  label: label,
  confidence: confidence,
  scores: List<double>.filled(24, 0),
);

Widget host(UploadScreen screen) => MaterialApp(home: Scaffold(body: screen));

void main() {
  testWidgets('pemilih model tidak overflow pada layar sempit', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(const UploadScreen()));

    final modelSelector = find.byKey(const ValueKey('upload-model-selector'));
    expect(modelSelector, findsOneWidget);
    final modelCard = tester.widget<Material>(
      find.ancestor(of: modelSelector, matching: find.byType(Material)).first,
    );
    expect(modelCard.color, isNot(const Color(0xFF2864F0)));
    final modelIcon = tester.widget<Icon>(
      find.descendant(
        of: modelSelector,
        matching: find.byIcon(Icons.memory_rounded),
      ),
    );
    expect(modelIcon.color, const Color(0xFF2864F0));
    expect(
      tester
          .widget<Text>(
            find.descendant(of: modelSelector, matching: find.text('MODEL AI')),
          )
          .style
          ?.color,
      isNot(const Color(0xFF2864F0)),
    );
    await tester.tap(modelSelector);
    await tester.pumpAndSettle();
    expect(find.text('Pilih Model AI'), findsOneWidget);
    final selectedModelOption = find.byKey(
      const ValueKey('upload-model-option-svm_hog'),
    );
    expect(selectedModelOption, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('upload-model-confirm')),
          )
          .style
          ?.backgroundColor
          ?.resolve({}),
      const Color(0xFF2864F0),
    );
    await tester.tap(find.byKey(const ValueKey('upload-model-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Contoh isyarat'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gambar tanpa tangan dilewati dan batch tetap berlanjut', (
    tester,
  ) async {
    final saved = <HistoryItem>[];
    await tester.pumpWidget(
      host(
        UploadScreen(
          pickFiles: (_) async => [XFile('no_hand.png'), XFile('hand.png')],
          classifyFile: (path) async {
            if (path == 'no_hand.png') {
              throw const FormatException('Tangan tidak terdeteksi.');
            }
            return prediction('C', 0.95);
          },
          saveImage: (file) async => 'saved/${file.path}',
          onResultSaved: (item) async => saved.add(item),
        ),
      ),
    );
    await tester.tap(find.text('Banyak gambar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih banyak gambar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Tangan tidak terdeteksi'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Tangan tidak terdeteksi'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('upload-letters'))).data,
      'C',
    );
    expect(saved.map((item) => item.gesture), ['C']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'upload menjaga urutan, menolak hasil ragu, dan menyimpan path permanen',
    (tester) async {
      final saved = <HistoryItem>[];
      final busy = <bool>[];
      final pickerModes = <bool>[];
      await tester.pumpWidget(
        host(
          UploadScreen(
            pickFiles: (multiple) async {
              pickerModes.add(multiple);
              expect(multiple, isTrue);
              return [XFile('a.png'), XFile('b.png'), XFile('c.png')];
            },
            classifyFile: (path) async => switch (path) {
              'a.png' => prediction('A', 0.95),
              'b.png' => prediction('B', 0.55),
              _ => prediction('C', 0.91),
            },
            saveImage: (file) async => 'saved/${file.path}',
            onResultSaved: (item) async => saved.add(item),
            onBusyChanged: busy.add,
          ),
        ),
      );
      await tester.tap(find.text('Banyak gambar'));
      await tester.pumpAndSettle();
      expect(pickerModes, isEmpty);
      await tester.tap(find.text('Pilih banyak gambar'));
      await tester.pumpAndSettle();
      expect(find.text('AC'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Belum yakin (B)'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Belum yakin (B)'), findsOneWidget);
      expect(saved.map((item) => item.gesture), ['A', 'C']);
      expect(saved.map((item) => item.imagePath), [
        'saved/a.png',
        'saved/c.png',
      ]);
      expect(saved.every((item) => item.source == 'upload'), isTrue);
      expect(busy, [true, false]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'gagal menyimpan riwayat tidak menghapus prediksi dan tidak mengunci UI',
    (tester) async {
      final busy = <bool>[];
      await tester.pumpWidget(
        host(
          UploadScreen(
            pickFiles: (multiple) async {
              expect(multiple, isFalse);
              return [XFile('a.png')];
            },
            classifyFile: (_) async => prediction('A', 0.95),
            saveImage: (file) async => file.path,
            onResultSaved: (_) async => throw StateError('database penuh'),
            onBusyChanged: busy.add,
          ),
        ),
      );
      await tester.tap(find.text('Satu gambar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pilih gambar tangan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Riwayat belum tersimpan:'), findsOneWidget);
      expect(find.text('Keyakinan 95.0%'), findsOneWidget);
      expect(busy, [true, false]);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Pilih gambar tangan'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hasil async setelah layar ditutup tidak disimpan', (
    tester,
  ) async {
    final pending = Completer<SignPrediction>();
    final saved = <HistoryItem>[];
    await tester.pumpWidget(
      host(
        UploadScreen(
          pickFiles: (multiple) async {
            expect(multiple, isFalse);
            return [XFile('a.png')];
          },
          classifyFile: (_) => pending.future,
          saveImage: (file) async => file.path,
          onResultSaved: (item) async => saved.add(item),
        ),
      ),
    );
    await tester.tap(find.text('Satu gambar'));
    await tester.pump();
    await tester.tap(find.text('Pilih gambar tangan'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(prediction('A', 0.95));
    await tester.pump();
    expect(saved, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
