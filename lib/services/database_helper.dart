import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/history_item.dart';

abstract interface class HistoryStore {
  Future<HistoryItem> insertHistory(HistoryItem item);
  Future<List<HistoryItem>> getAllHistory();
  Future<int> deleteHistory(int id);
  Future<int> deleteAllHistory();
}

/// Penyimpanan lokal. Migrasi v2 menambah metadata tanpa membuang riwayat lama.
class DatabaseHelper implements HistoryStore {
  static final DatabaseHelper instance = DatabaseHelper._init();
  Future<Database>? _openingDatabase;

  DatabaseHelper._init();

  Future<Database> get database => _openingDatabase ??= _openDatabase();

  Future<Database> _openDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      return await openDatabase(
        join(dbPath, 'sign_language_history.db'),
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              gesture TEXT NOT NULL,
              accuracy TEXT NOT NULL,
              date TEXT NOT NULL,
              time TEXT NOT NULL,
              confidence REAL,
              source TEXT NOT NULL DEFAULT 'unknown',
              image_path TEXT,
              video_path TEXT
            )
          ''');
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE history ADD COLUMN confidence REAL');
            await db.execute(
              "ALTER TABLE history ADD COLUMN source TEXT NOT NULL DEFAULT 'unknown'",
            );
            await db.execute('ALTER TABLE history ADD COLUMN image_path TEXT');
            await db.execute('ALTER TABLE history ADD COLUMN video_path TEXT');
          }
        },
      );
    } catch (_) {
      _openingDatabase = null;
      rethrow;
    }
  }

  @override
  Future<HistoryItem> insertHistory(HistoryItem item) async {
    final db = await database;
    final id = await db.insert('history', item.toMap());
    return item.copyWith(id: id);
  }

  @override
  Future<List<HistoryItem>> getAllHistory() async {
    final db = await database;
    final rows = await db.query('history', orderBy: 'id DESC');
    return rows.map(HistoryItem.fromMap).toList();
  }

  @override
  Future<int> deleteHistory(int id) async {
    final db = await database;
    return db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> deleteAllHistory() async {
    final db = await database;
    return db.delete('history');
  }

  Future<void> close() async {
    final opening = _openingDatabase;
    if (opening == null) return;
    final db = await opening;
    await db.close();
    _openingDatabase = null;
  }
}
