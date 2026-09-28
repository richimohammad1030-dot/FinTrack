// Lapisan database SQLite. Semua akses tabel lewat kelas ini.

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'seed.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const fileName = 'fintrack.db';
  static const version = 3;

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
      onUpgrade: _onUpgrade,
    );
    if (path == null) {
      // Database aplikasi versi lama (Pro-Tracker) tidak dipakai lagi.
      await deleteDatabase(p.join(await getDatabasesPath(), 'pro_tracker.db'));
    }
    return AppDatabase._(db);
  }

  // ── Skema ──────────────────────────────────────────────────────────────
  // v1: FinTrack 2.0 · v2: hutang/piutang · v3: kolom categories.daily

  static const _debtsSql = '''
      CREATE TABLE debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL CHECK(kind IN ('payable','receivable')),
        name TEXT NOT NULL,
        principal INTEGER NOT NULL DEFAULT 0,
        start_date TEXT NOT NULL,
        due_date TEXT,
        note TEXT NOT NULL DEFAULT '',
        closed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )''';

  static const _recurringsSql = '''
      CREATE TABLE recurrings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('expense','income','debtIn','debtOut')),
        amount INTEGER NOT NULL,
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
        debt_id INTEGER REFERENCES debts(id) ON DELETE CASCADE,
        day_of_month INTEGER NOT NULL,
        next_date TEXT NOT NULL,
        auto_record INTEGER NOT NULL DEFAULT 1,
        active INTEGER NOT NULL DEFAULT 1,
        note TEXT NOT NULL DEFAULT ''
      )''';

  static const _transactionsSql = '''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL CHECK(type IN ('expense','income','transfer','debtIn','debtOut')),
        amount INTEGER NOT NULL CHECK(amount > 0),
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
        to_wallet_id INTEGER REFERENCES wallets(id) ON DELETE CASCADE,
        goal_id INTEGER REFERENCES goals(id) ON DELETE SET NULL,
        recurring_id INTEGER REFERENCES recurrings(id) ON DELETE SET NULL,
        debt_id INTEGER REFERENCES debts(id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )''';

  static void _indexes(Batch b) {
    b.execute('CREATE INDEX IF NOT EXISTS idx_txn_date ON transactions(date)');
    b.execute('CREATE INDEX IF NOT EXISTS idx_txn_category ON transactions(category_id)');
    b.execute('CREATE INDEX IF NOT EXISTS idx_txn_debt ON transactions(debt_id)');
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
        daily INTEGER NOT NULL DEFAULT 1,
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
    batch.execute(_debtsSql);
    batch.execute(_recurringsSql);
    batch.execute(_transactionsSql);
    _indexes(batch);
    for (final c in defaultCategories()) {
      batch.insert('categories', c.toMap());
    }
    await batch.commit(noResult: true);
  }

  /// Migrasi tanpa kehilangan data. SQLite tidak bisa mengubah CHECK, jadi
  /// tabel dibuat ulang lalu datanya disalin.
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(_debtsSql);
      await db.execute('ALTER TABLE recurrings RENAME TO recurrings_v1');
      await db.execute(_recurringsSql);
      await db.execute('''
        INSERT INTO recurrings (id, title, type, amount, category_id, wallet_id, day_of_month,
          next_date, auto_record, active, note)
        SELECT id, title, type, amount, category_id, wallet_id, day_of_month,
          next_date, auto_record, active, note FROM recurrings_v1''');
      await db.execute('ALTER TABLE transactions RENAME TO transactions_v1');
      await db.execute(_transactionsSql);
      await db.execute('''
        INSERT INTO transactions (id, type, amount, category_id, wallet_id, to_wallet_id, goal_id,
          recurring_id, date, note, created_at)
        SELECT id, type, amount, category_id, wallet_id, to_wallet_id, goal_id,
          recurring_id, date, note, created_at FROM transactions_v1''');
      await db.execute('DROP TABLE transactions_v1');
      await db.execute('DROP TABLE recurrings_v1');
      final b = db.batch();
      _indexes(b);
      await b.commit(noResult: true);
    }
    if (oldVersion < 3) {
      // v3: pos bulanan (kos, tagihan, dll.) tidak masuk jatah harian.
      await db.execute('ALTER TABLE categories ADD COLUMN daily INTEGER NOT NULL DEFAULT 1');
      await db.update('categories', {'daily': 0},
          where: "kind = 'expense' AND name IN (${List.filled(nonDailyDefaults.length, '?').join(',')})",
          whereArgs: nonDailyDefaults.toList());
    }
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

  // ── Debts ───────────────────────────────────────────────────────────────
  Future<List<Debt>> debts() async => (await db.query('debts', orderBy: 'id')).map(Debt.fromMap).toList();
  Future<int> insertDebt(Debt d) => db.insert('debts', d.toMap());
  Future<void> updateDebt(Debt d) => db.update('debts', d.toMap(), where: 'id = ?', whereArgs: [d.id]);
  Future<void> deleteDebt(int id) => db.delete('debts', where: 'id = ?', whereArgs: [id]);

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
  static const tables = ['wallets', 'categories', 'goals', 'debts', 'recurrings', 'transactions'];

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
