/// Model untuk satu record deteksi yang disimpan di SQLite.
class HistoryItem {
  final int? id;
  final String gesture;
  final String accuracy;
  final String date;
  final String time;

  const HistoryItem({
    this.id,
    required this.gesture,
    required this.accuracy,
    required this.date,
    required this.time,
  });

  /// Konversi dari Map (database row) ke [HistoryItem].
  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      id: map['id'] as int?,
      gesture: map['gesture'] as String,
      accuracy: map['accuracy'] as String,
      date: map['date'] as String,
      time: map['time'] as String,
    );
  }

  /// Konversi ke Map untuk disimpan ke SQLite.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'gesture': gesture,
      'accuracy': accuracy,
      'date': date,
      'time': time,
    };
  }

  /// Copy with helper.
  HistoryItem copyWith({
    int? id,
    String? gesture,
    String? accuracy,
    String? date,
    String? time,
  }) {
    return HistoryItem(
      id: id ?? this.id,
      gesture: gesture ?? this.gesture,
      accuracy: accuracy ?? this.accuracy,
      date: date ?? this.date,
      time: time ?? this.time,
    );
  }

  @override
  String toString() =>
      'HistoryItem(id: $id, gesture: $gesture, accuracy: $accuracy, date: $date, time: $time)';
}
