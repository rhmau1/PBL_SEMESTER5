import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language/models/history_item.dart';

void main() {
  test('full video sequence and metadata survive database serialization', () {
    final item = HistoryItem.fromDetection(
      gesture: 'SAYA BELAJAR',
      confidence: 0.9235,
      source: 'video',
      videoPath: '/recordings/session.mp4',
    ).copyWith(id: 17);
    final restored = HistoryItem.fromMap(item.toMap());
    expect(restored.id, 17);
    expect(restored.gesture, 'SAYA BELAJAR');
    expect(restored.confidence, 0.9235);
    expect(restored.confidenceLabel, '92.3%');
    expect(restored.sourceLabel, 'Latihan bebas');
    expect(restored.videoPath, '/recordings/session.mp4');
    expect(restored.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(restored.time, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
  });

  test('version 1 history remains readable with missing metadata columns', () {
    final item = HistoryItem.fromMap({
      'id': 4,
      'gesture': 'C',
      'accuracy': '87%',
      'date': '2026-10-10',
      'time': '12:13',
    });
    expect(item.gesture, 'C');
    expect(item.confidence, isNull);
    expect(item.confidenceLabel, '87%');
    expect(item.source, 'unknown');
    expect(item.imagePath, isNull);
    expect(item.videoPath, isNull);
  });

  test('photo metadata survives the id assigned by SQLite', () {
    final item = HistoryItem.fromDetection(
      gesture: 'A',
      confidence: 1,
      source: 'photo',
      imagePath: '/photos/a.jpg',
    ).copyWith(id: 1);
    final saved = HistoryItem.fromMap(item.toMap());
    expect(saved.imagePath, '/photos/a.jpg');
    expect(saved.confidenceLabel, '100.0%');
    expect(saved.sourceLabel, 'Foto kamera');
  });

  test('invalid scores cannot become misleading percentages', () {
    for (final score in [double.nan, double.infinity, -0.1, 1.1]) {
      expect(
        () => HistoryItem.fromDetection(
          gesture: 'B',
          confidence: score,
          source: 'target',
        ),
        throwsArgumentError,
      );
    }
  });
}
