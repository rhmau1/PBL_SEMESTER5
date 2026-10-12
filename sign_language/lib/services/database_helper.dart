import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/history_item.dart';

/// Singleton helper yang mengelola database SQLite untuk history deteksi.
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// Buka (atau buat) database. Dipanggil sekali saja, hasilnya di-cache.
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sign_language_history.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  /// Buat tabel history saat pertama kali database dibuat.
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE history (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        gesture  TEXT NOT NULL,
        accuracy TEXT NOT NULL,
        date     TEXT NOT NULL,
        time     TEXT NOT NULL
      )
    ''');
  }

  // ─── CRUD Operations ─────────────────────────────────────────────────────

  /// Insert satu record baru, return [HistoryItem] dengan id terisi.
  Future<HistoryItem> insertHistory(HistoryItem item) async {
    final db = await database;
    final id = await db.insert('history', item.toMap());
    return item.copyWith(id: id);
  }

  /// Ambil semua history, diurutkan dari yang terbaru (id terbesar).
  Future<List<HistoryItem>> getAllHistory() async {
    final db = await database;
    final result = await db.query('history', orderBy: 'id DESC');
    return result.map((map) => HistoryItem.fromMap(map)).toList();
  }

  /// Hapus satu record berdasarkan [id].
  Future<int> deleteHistory(int id) async {
    final db = await database;
    return db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  /// Hapus semua history.
  Future<int> deleteAllHistory() async {
    final db = await database;
    return db.delete('history');
  }

  /// Tutup database connection (opsional, dipanggil saat app exit).
  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }
}
