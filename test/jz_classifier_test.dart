import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/models/jz_prediction.dart';
import 'package:sign_language/services/jz_classifier.dart';

class _Runner implements JzScoreRunner {
  _Runner({this.gate});

  List<double> scores = const [0.8, 0.1, 0.1];
  final Completer<void>? gate;
  final entered = Completer<void>();
  var active = 0;
  var maximumActive = 0;
  var calls = 0;
  var closes = 0;
  List<List<double>>? lastFeatures;

  @override
  Future<List<double>> run(List<List<double>> features) async {
    active++;
    if (active > maximumActive) maximumActive = active;
    calls++;
    lastFeatures = features;
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    active--;
    return scores;
  }

  @override
  Future<void> close() async {
    expect(active, 0, reason: 'Native model must outlive running inference.');
    closes++;
  }
}

List<List<double>> _features() =>
    List<List<double>>.generate(48, (_) => List<double>.filled(64, 0));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('J/Z asset has the original identifier, labels and contract', () async {
    final data = await rootBundle.load(JzClassifier.modelAssetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    expect(bytes.length, 229672);
    expect(ascii.decode(bytes.sublist(4, 8)), 'TFL3');
    expect(
      jsonDecode(await rootBundle.loadString('assets/models/jz/labels.json')),
      JzPrediction.labels,
    );
    final contract = jsonDecode(
      await rootBundle.loadString(
        'assets/models/jz/preprocessing_contract.json',
      ),
    ) as Map<String, dynamic>;
    expect(contract['sequence_length'], 48);
    expect(contract['feature_count'], 64);
    expect(contract['image_mirror'], false);
  });

  test('J/Z acceptance uses .60 and OTHER always abstains', () {
    expect(JzPrediction.fromScores([0.60, 0.2, 0.2]).acceptedLabel, 'J');
    expect(JzPrediction.fromScores([0.2, 0.60, 0.2]).acceptedLabel, 'Z');
    expect(JzPrediction.fromScores([0.59, 0.21, 0.2]).acceptedLabel, isNull);
    final other = JzPrediction.fromScores([0.01, 0.01, 0.98]);
    expect(other.rawLabel, 'OTHER');
    expect(other.acceptedLabel, isNull);
    expect(() => other.scores[0] = 1, throwsUnsupportedError);
  });

  test('malformed probabilities never become an accepted letter', () {
    for (final scores in <List<double>>[
      [1, 0],
      [double.nan, 0, 0],
      [double.infinity, 0, 0],
      [-0.1, 0.1, 1],
      [1.1, 0, 0],
      [0.8, 0.8, 0.1],
    ]) {
      expect(() => JzPrediction.fromScores(scores), throwsStateError);
    }
  });

  test(
    'initialization is shared and retries after asynchronous failure',
    () async {
      var attempts = 0;
      final gate = Completer<JzScoreRunner>();
      final runner = _Runner();
      final classifier = JzClassifier(
        scoreRunnerFactory: () {
          attempts++;
          if (attempts == 1) return gate.future;
          return Future.value(runner);
        },
      );
      final first = classifier.initialize();
      final second = classifier.initialize();
      expect(identical(first, second), isTrue);
      final failures = Future.wait([
        expectLater(first, throwsStateError),
        expectLater(second, throwsStateError),
      ]);
      gate.completeError(StateError('native initialization failed'));
      await failures;
      await classifier.initialize();
      expect(attempts, 2);
      expect(classifier.isReady, isTrue);
      await classifier.close();
    },
  );

  test('synchronous load failure also permits retry', () async {
    var attempts = 0;
    final runner = _Runner();
    final classifier = JzClassifier(
      scoreRunnerFactory: () {
        if (++attempts == 1) {
          throw StateError('failed before returning a future');
        }
        return Future.value(runner);
      },
    );
    await expectLater(classifier.initialize(), throwsStateError);
    await classifier.initialize();
    expect(attempts, 2);
    await classifier.close();
  });

  test(
    'closing during initialization releases the loaded model exactly once',
    () async {
      final gate = Completer<JzScoreRunner>();
      final runner = _Runner();
      final classifier = JzClassifier(scoreRunnerFactory: () => gate.future);
      final initializing = expectLater(
        classifier.initialize(),
        throwsStateError,
      );
      final closing = classifier.close();
      gate.complete(runner);
      await initializing;
      await closing;
      await classifier.close();
      expect(runner.closes, 1);
      expect(classifier.isReady, isFalse);
      await expectLater(classifier.initialize(), throwsStateError);
      await expectLater(
        classifier.classifyFeatures(_features()),
        throwsStateError,
      );
    },
  );

  test(
    'inferences serialize and snapshot features before the first await',
    () async {
      final gate = Completer<void>();
      final runner = _Runner(gate: gate);
      final classifier = JzClassifier(scoreRunnerFactory: () async => runner);
      final features = _features();
      final first = classifier.classifyFeatures(features);
      features[0][0] = 99;
      await runner.entered.future;
      final second = classifier.classifyFeatures(_features());
      await Future<void>.delayed(Duration.zero);
      expect(runner.calls, 1);
      expect(runner.lastFeatures![0][0], 0);
      gate.complete();
      final predictions = await Future.wait([first, second]);
      expect(predictions.map((p) => p.acceptedLabel), ['J', 'J']);
      expect(runner.maximumActive, 1);
      await classifier.close();
    },
  );

  test('close waits for active inference before freeing the runner', () async {
    final gate = Completer<void>();
    final runner = _Runner(gate: gate);
    final classifier = JzClassifier(scoreRunnerFactory: () async => runner);
    final prediction = classifier.classifyFeatures(_features());
    await runner.entered.future;
    final closing = classifier.close();
    expect(runner.closes, 0);
    gate.complete();
    expect((await prediction).acceptedLabel, 'J');
    await closing;
    expect(runner.closes, 1);
  });

  test(
    'invalid feature tensors are rejected before loading a native model',
    () async {
      var loads = 0;
      final classifier = JzClassifier(
        scoreRunnerFactory: () async {
          loads++;
          return _Runner();
        },
      );
      final invalid = <List<List<double>>>[
        [],
        List.generate(48, (_) => List<double>.filled(63, 0)),
        _features()..[3][2] = double.nan,
        _features()..[3][2] = double.infinity,
        _features()..[3][2] = 1e100,
      ];
      for (final features in invalid) {
        await expectLater(
          classifier.classifyFeatures(features),
          throwsArgumentError,
        );
      }
      expect(loads, 0);
      await classifier.close();
    },
  );

  // Opt in on a host with the tflite_flutter C runtime installed. This runs
  // the actual model, not an injected runner, on preserved held-out features.
  const nativeTest = bool.fromEnvironment('JZ_NATIVE_TEST');
  test(
    'native float16 J/Z inference matches held-out J, Z and synthetic OTHER',
    () async {
      final fixture = jsonDecode(
        await File('test/fixtures/jz_held_out_features.json').readAsString(),
      ) as Map<String, dynamic>;
      final classifier = JzClassifier();
      try {
        await classifier.initialize();
        for (final value in fixture['samples'] as List<dynamic>) {
          final sample = value as Map<String, dynamic>;
          final features = (sample['features'] as List<dynamic>)
              .map(
                (row) => (row as List<dynamic>)
                    .map((number) => (number as num).toDouble())
                    .toList(),
              )
              .toList();
          final prediction = await classifier.classifyFeatures(features);
          expect(
            prediction.rawLabel,
            sample['expected_label'],
            reason: 'Preserved held-out sample ${sample['source_index']}',
          );
          expect(
            prediction.acceptedLabel,
            sample['expected_label'] == 'OTHER'
                ? isNull
                : sample['expected_label'],
          );
        }
      } finally {
        await classifier.close();
      }
    },
    skip: !nativeTest
        ? 'Run with --dart-define=JZ_NATIVE_TEST=true and native runtime.'
        : false,
  );
}
