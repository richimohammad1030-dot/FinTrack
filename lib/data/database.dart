// Lapisan database SQLite. Semua akses tabel lewat kelas ini.

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'seed.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const fileName = 'fintrack.db';
  static const version = 1;

  /// Buka database di penyimpanan aplikasi. [path] bisa diisi
  /// `inMemoryDatabasePath` untuk pengujian.
  static Future<AppDatabase> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), fileName);
    final db = await openDatabase(
      dbPath,
      version: version,
      // Database di memori (pengujian) harus terpisah setiap kali dibuka.
      singleInstance: path != inMemoryDatabasePath,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
    );
    if (path == null) {
      // Database aplikasi versi lama (Pro-Tracker) tidak dipakai lagi.
      await deleteDatabase(p.join(await getDatabasesPath(), 'pro_tracker.db'));
    }
    return AppDatabase._(db);
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE wallets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        initial_balance INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('expense','income')),
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        monthly_limit INTEGER NOT NULL DEFAULT 0,
        is_saving INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        target INTEGER NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        deadline TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE recurrings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('expense','income')),
        amount INTEGER NOT NULL,
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
        day_of_month INTEGER NOT NULL,
        next_date TEXT NOT NULL,
        auto_record INTEGER NOT NULL DEFAULT 1,
        active INTEGER NOT NULL DEFAULT 1,
        note TEXT NOT NULL DEFAULT ''
      )''');
    batch.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK(type IN ('expense','income','transfer')),
        amount INTEGER NOT NULL CHECK(amount > 0),
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
        to_wallet_id INTEGER REFERENCES wallets(id) ON DELETE CASCADE,
        goal_id INTEGER REFERENCES goals(id) ON DELETE SET NULL,
        recurring_id INTEGER REFERENCES recurrings(id) ON DELETE SET NULL,
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_txn_date ON transactions(date)');
    batch.execute('CREATE INDEX idx_txn_category ON transactions(category_id)');
    for (final c in defaultCategories()) {
      batch.insert('categories', c.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();

  // ── Wallets ─────────────────────────────────────────────────────────────
  Future<List<Wallet>> wallets() async =>
      (await db.query('wallets', orderBy: 'sort_order, id')).map(Wallet.fromMap).toList();
  Future<int> insertWallet(Wallet w) => db.insert('wallets', w.toMap());
  Future<void> updateWallet(Wallet w) =>
      db.update('wallets', w.toMap(), where: 'id = ?', whereArgs: [w.id]);
  Future<void> deleteWallet(int id) => db.delete('wallets', where: 'id = ?', whereArgs: [id]);

  // ── Categories ──────────────────────────────────────────────────────────
  Future<List<Pos>> categories() async =>
      (await db.query('categories', orderBy: 'sort_order, id')).map(Pos.fromMap).toList();
  Future<int> insertCategory(Pos c) => db.insert('categories', c.toMap());
  Future<void> updateCategory(Pos c) =>
      db.update('categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  Future<void> deleteCategory(int id) =>
      db.delete('categories', where: 'id = ?', whereArgs: [id]);

  /// Simpan banyak batas pos sekaligus (dipakai layar "Bagi Gaji").
  Future<void> updateLimits(Map<int, int> limits) async {
    final batch = db.batch();
    limits.forEach((id, limit) {
      batch.update('categories', {'monthly_limit': limit}, where: 'id = ?', whereArgs: [id]);
    });
    await batch.commit(noResult: true);
  }

  Future<void> reorderCategories(List<int> ids) async {
    final batch = db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update('categories', {'sort_order': i}, where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit(noResult: true);
  }

  // ── Goals ───────────────────────────────────────────────────────────────
  Future<List<Goal>> goals() async =>
      (await db.query('goals', orderBy: 'archived, id')).map(Goal.fromMap).toList();
  Future<int> insertGoal(Goal g) => db.insert('goals', g.toMap());
  Future<void> updateGoal(Goal g) =>
      db.update('goals', g.toMap(), where: 'id = ?', whereArgs: [g.id]);
  Future<void> deleteGoal(int id) => db.delete('goals', where: 'id = ?', whereArgs: [id]);

  // ── Recurrings ──────────────────────────────────────────────────────────
  Future<List<Recurring>> recurrings() async =>
      (await db.query('recurrings', orderBy: 'next_date')).map(Recurring.fromMap).toList();
  Future<int> insertRecurring(Recurring r) => db.insert('recurrings', r.toMap());
  Future<void> updateRecurring(Recurring r) =>
      db.update('recurrings', r.toMap(), where: 'id = ?', whereArgs: [r.id]);
  Future<void> deleteRecurring(int id) =>
      db.delete('recurrings', where: 'id = ?', whereArgs: [id]);

  Future<void> postRecurring(Recurring updated, List<Txn> txns) async {
    await db.transaction((tx) async {
      for (final t in txns) {
        await tx.insert('transactions', t.toMap());
      }
      await tx.update('recurrings', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
    });
  }

  // ── Transactions ────────────────────────────────────────────────────────
  Future<List<Txn>> transactions() async =>
      (await db.query('transactions', orderBy: 'date DESC, id DESC')).map(Txn.fromMap).toList();
  Future<int> insertTxn(Txn t) => db.insert('transactions', t.toMap());
  Future<void> updateTxn(Txn t) =>
      db.update('transactions', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
  Future<void> deleteTxn(int id) => db.delete('transactions', where: 'id = ?', whereArgs: [id]);

  // ── Backup ──────────────────────────────────────────────────────────────
  static const tables = ['wallets', 'categories', 'goals', 'recurrings', 'transactions'];

  Future<Map<String, List<Map<String, Object?>>>> dumpAll() async => {
        for (final t in tables) t: await db.query(t),
      };

  /// Ganti seluruh isi database dengan data backup (dalam satu transaksi,
  /// jadi kalau gagal di tengah jalan data lama tetap aman).
  Future<void> replaceAll(Map<String, List<Map<String, Object?>>> data) async {
    await db.transaction((tx) async {
      for (final t in tables.reversed) {
        await tx.delete(t);
      }
      for (final t in tables) {
        for (final row in data[t] ?? const []) {
          await tx.insert(t, row);
        }
      }
    });
  }

  /// Hapus semua data dan kembalikan pos bawaan.
  Future<void> resetAll() async {
    await db.transaction((tx) async {
      for (final t in tables.reversed) {
        await tx.delete(t);
      }
      for (final c in defaultCategories()) {
        await tx.insert('categories', c.toMap());
      }
    });
  }
}
