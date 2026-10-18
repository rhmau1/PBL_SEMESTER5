/// Satu hasil deteksi. [accuracy] tetap tersedia untuk riwayat versi lama.
/// Angka baru adalah keyakinan prediksi, bukan akurasi pengujian model.
class HistoryItem {
  final int? id;
  final String gesture;
  final String accuracy;
  final String date;
  final String time;
  final double? confidence;
  final String source;
  final String? imagePath;
  final String? videoPath;

  const HistoryItem({
    this.id,
    required this.gesture,
    required this.accuracy,
    required this.date,
    required this.time,
    this.confidence,
    this.source = 'unknown',
    this.imagePath,
    this.videoPath,
  });

  factory HistoryItem.fromDetection({
    required String gesture,
    required double confidence,
    required String source,
    String? imagePath,
    String? videoPath,
  }) {
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'Harus antara 0–1.');
    }
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return HistoryItem(
      gesture: gesture,
      accuracy: '${(confidence * 100).toStringAsFixed(1)}%',
      date: '${now.year}-${two(now.month)}-${two(now.day)}',
      time: '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
      confidence: confidence,
      source: source,
      imagePath: imagePath,
      videoPath: videoPath,
    );
  }

  String get sourceLabel => switch (source) {
    'video' => 'Latihan bebas',
    'photo' => 'Foto kamera',
    'upload' => 'Upload gambar',
    _ => 'Deteksi sebelumnya',
  };

  String get confidenceLabel => confidence == null
      ? accuracy
      : '${(confidence! * 100).toStringAsFixed(1)}%';

  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      id: (map['id'] as num?)?.toInt(),
      gesture: map['gesture'] as String,
      accuracy: map['accuracy'] as String,
      date: map['date'] as String,
      time: map['time'] as String,
      confidence: (map['confidence'] as num?)?.toDouble(),
      source: map['source'] as String? ?? 'unknown',
      imagePath: map['image_path'] as String?,
      videoPath: map['video_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'gesture': gesture,
    'accuracy': accuracy,
    'date': date,
    'time': time,
    'confidence': confidence,
    'source': source,
    'image_path': imagePath,
    'video_path': videoPath,
  };

  HistoryItem copyWith({
    int? id,
    String? gesture,
    String? accuracy,
    String? date,
    String? time,
    double? confidence,
    String? source,
    String? imagePath,
    String? videoPath,
  }) => HistoryItem(
    id: id ?? this.id,
    gesture: gesture ?? this.gesture,
    accuracy: accuracy ?? this.accuracy,
    date: date ?? this.date,
    time: time ?? this.time,
    confidence: confidence ?? this.confidence,
    source: source ?? this.source,
    imagePath: imagePath ?? this.imagePath,
    videoPath: videoPath ?? this.videoPath,
  );
}
