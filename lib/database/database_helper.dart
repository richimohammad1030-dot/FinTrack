// lib/database/database_helper.dart
// Pro-Tracker - Database Helper (v2)
// Penambahan: kolom 'notes', migrasi aman dari v1 → v2.

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';

class DatabaseHelper {
  // ── Singleton ────────────────────────────────────────────────────────────
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  // ── Konstanta ────────────────────────────────────────────────────────────
  static const String _dbName = 'pro_tracker.db';

  // ⚠️ PENTING: Naikkan versi dari 1 → 2 agar migrasi _onUpgrade dipanggil
  static const int _dbVersion = 2;

  static const String tableTransactions = 'transactions';
  static const String colId = 'id';
  static const String colTitle = 'title';
  static const String colAmount = 'amount';
  static const String colType = 'type';
  static const String colCategory = 'category';
  static const String colDate = 'date';
  static const String colNotes = 'notes'; // ← BARU

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Skema lengkap untuk instalasi baru (sudah include kolom notes)
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableTransactions (
        $colId       INTEGER PRIMARY KEY AUTOINCREMENT,
        $colTitle    TEXT    NOT NULL,
        $colAmount   REAL    NOT NULL,
        $colType     TEXT    NOT NULL CHECK($colType IN ('income', 'expense')),
        $colCategory TEXT    NOT NULL,
        $colDate     TEXT    NOT NULL,
        $colNotes    TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_date ON $tableTransactions ($colDate)');
    await db.execute('CREATE INDEX idx_type ON $tableTransactions ($colType)');
  }

  /// Migrasi aman: menambah kolom 'notes' tanpa menghapus data lama.
  /// ALTER TABLE ADD COLUMN aman digunakan di SQLite — data lama tetap ada,
  /// kolom baru akan berisi NULL untuk semua baris yang sudah ada.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Tambah kolom notes — tidak ada data yang hilang
      await db.execute(
        'ALTER TABLE $tableTransactions ADD COLUMN $colNotes TEXT',
      );
    }
    // Tambahkan blok if (oldVersion < 3) di sini untuk migrasi berikutnya
  }

  // ── CREATE ───────────────────────────────────────────────────────────────

  Future<int> insertTransaction(TransactionModel transaction) async {
    final db = await database;
    return await db.insert(
      tableTransactions,
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── READ ─────────────────────────────────────────────────────────────────

  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await database;
    final maps = await db.query(tableTransactions, orderBy: '$colDate DESC');
    return maps.map(TransactionModel.fromMap).toList();
  }

  Future<List<TransactionModel>> getTransactionsByType(
    TransactionType type,
  ) async {
    final db = await database;
    final maps = await db.query(
      tableTransactions,
      where: '$colType = ?',
      whereArgs: [type.value],
      orderBy: '$colDate DESC',
    );
    return maps.map(TransactionModel.fromMap).toList();
  }

  Future<List<TransactionModel>> getTransactionsByCategory(
    TransactionCategory category,
  ) async {
    final db = await database;
    final maps = await db.query(
      tableTransactions,
      where: '$colCategory = ?',
      whereArgs: [category.value],
      orderBy: '$colDate DESC',
    );
    return maps.map(TransactionModel.fromMap).toList();
  }

  Future<List<TransactionModel>> getRecentTransactions({int limit = 10}) async {
    final db = await database;
    final maps = await db.query(
      tableTransactions,
      orderBy: '$colDate DESC',
      limit: limit,
    );
    return maps.map(TransactionModel.fromMap).toList();
  }

  Future<List<TransactionModel>> getTransactionsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await database;
    final maps = await db.query(
      tableTransactions,
      where: '$colDate BETWEEN ? AND ?',
      whereArgs: [startDate.toIso8601String(), endDate.toIso8601String()],
      orderBy: '$colDate DESC',
    );
    return maps.map(TransactionModel.fromMap).toList();
  }

  // ── UPDATE ───────────────────────────────────────────────────────────────

  Future<int> updateTransaction(TransactionModel transaction) async {
    if (transaction.id == null) {
      throw ArgumentError('Cannot update a transaction without an id.');
    }
    final db = await database;
    return await db.update(
      tableTransactions,
      transaction.toMap(),
      where: '$colId = ?',
      whereArgs: [transaction.id],
    );
  }

  // ── DELETE ───────────────────────────────────────────────────────────────

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return await db.delete(
      tableTransactions,
      where: '$colId = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAllTransactions() async {
    final db = await database;
    return await db.delete(tableTransactions);
  }

  // ── AGGREGASI ────────────────────────────────────────────────────────────

  Future<double> getTotalIncome() async => _sumByType(TransactionType.income);
  Future<double> getTotalExpense() async => _sumByType(TransactionType.expense);

  Future<double> getNetBalance() async {
    final income = await getTotalIncome();
    final expense = await getTotalExpense();
    return income - expense;
  }

  Future<double> _sumByType(TransactionType type) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM($colAmount) as total FROM $tableTransactions '
      'WHERE $colType = ?',
      [type.value],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<Map<String, double>> getExpenseByCategory() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT $colCategory, SUM($colAmount) as total
      FROM $tableTransactions
      WHERE $colType = 'expense'
      GROUP BY $colCategory
      ORDER BY total DESC
    ''');

    return {
      for (final row in result)
        row[colCategory] as String: (row['total'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> getIncomeByCategory() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT $colCategory, SUM($colAmount) as total
      FROM $tableTransactions
      WHERE $colType = 'income'
      GROUP BY $colCategory
      ORDER BY total DESC
    ''');

    return {
      for (final row in result)
        row[colCategory] as String: (row['total'] as num).toDouble(),
    };
  }

  // ── UTILITY ──────────────────────────────────────────────────────────────

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
