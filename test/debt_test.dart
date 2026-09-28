import 'package:kait/data/database.dart';
import 'package:kait/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_utils.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  final now = DateTime(2026, 9, 28, 19);

  test('hutang dengan uang masuk dompet: saldo, sisa, pelunasan', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'BCA', initialBalance: 100000));
    final id = await store.createDebt(
      Debt(kind: DebtKind.payable, name: 'Budi', startDate: DateTime(2026, 9, 26)),
      amount: 1000000,
      walletId: w,
    );
    final d = store.debt(id)!;
    expect(store.walletBalance(w), 1100000);
    expect(store.debtStatus(d).remaining, 1000000);
    expect(store.totalPayable, 1000000);
    // Pinjaman tidak dihitung sebagai pemasukan
    expect(store.currentSummary.income, 0);
    expect(store.currentSummary.debtIn, 1000000);

    await store.recordDebtTxn(d, amount: 400000, walletId: w, date: now);
    expect(store.debtStatus(d).remaining, 600000);
    expect(store.walletBalance(w), 700000);
    // Bayar hutang tidak memakan jatah harian
    expect(store.currentSummary.expense, 0);

    await store.recordDebtTxn(d, amount: 600000, walletId: w, date: now);
    expect(store.debtStatus(d).settled, isTrue);
    expect(store.activeDebts, isEmpty);
  });

  test('hutang lama tanpa mutasi dompet & tambahan pinjaman', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'Tunai'));
    final id = await store.createDebt(
      Debt(kind: DebtKind.payable, name: 'Paylater', startDate: DateTime(2026, 8, 1)),
      amount: 2000000,
    );
    final d = store.debt(id)!;
    expect(store.walletBalance(w), 0);
    await store.recordDebtTxn(d, amount: 500000, walletId: w, date: now, increase: true);
    expect(store.debtStatus(d).total, 2500000);
    expect(store.walletBalance(w), 500000);
  });

  test('piutang: meminjamkan lalu dibayar kembali', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'Tunai', initialBalance: 500000));
    final id = await store.createDebt(
      Debt(kind: DebtKind.receivable, name: 'Andi', startDate: now),
      amount: 300000,
      walletId: w,
    );
    final d = store.debt(id)!;
    expect(store.walletBalance(w), 200000);
    expect(store.totalReceivable, 300000);
    await store.recordDebtTxn(d, amount: 100000, walletId: w, date: now);
    expect(store.walletBalance(w), 300000);
    expect(store.debtStatus(d).remaining, 200000);
  });

  test('cicilan otomatis berhenti saat lunas & tidak melebihi sisa', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'BCA'));
    final id = await store.createDebt(
      Debt(kind: DebtKind.payable, name: 'Kredivo', startDate: DateTime(2026, 5, 1)),
      amount: 1000000,
    );
    await store.saveDebtInstallment(
      store.debt(id)!,
      Recurring(
        title: 'Cicilan Kredivo',
        type: TxnType.debtOut,
        amount: 400000,
        walletId: w,
        dayOfMonth: 10,
        nextDate: DateTime(2026, 6, 10),
        debtId: id,
      ),
    );
    // Jatuh tempo 10 Jun, 10 Jul, 10 Agu, 10 Sep → 400 + 400 + 200 lalu berhenti
    final paid = store.debtTxns(id).map((t) => t.amount).toList()..sort();
    expect(paid, [200000, 400000, 400000]);
    expect(store.debtStatus(store.debt(id)!).settled, isTrue);
    expect(store.debtRecurrings(id).single.active, isFalse);
  });

  test('pengingat jatuh tempo dijadwalkan & dibatalkan saat lunas', () async {
    final (store, _, notifier) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'BCA'));
    final id = await store.createDebt(
      Debt(kind: DebtKind.payable, name: 'Budi', startDate: now, dueDate: DateTime(2026, 10, 10)),
      amount: 100000,
      walletId: w,
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifier.scheduled.length, 2);
    await store.recordDebtTxn(store.debt(id)!, amount: 100000, walletId: w, date: now);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.scheduled, isEmpty);
  });

  test('hapus hutang ikut menghapus pembayarannya', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'BCA'));
    final id = await store.createDebt(
      Debt(kind: DebtKind.payable, name: 'X', startDate: now),
      amount: 50000,
      walletId: w,
    );
    await store.deleteDebt(id);
    expect(store.transactions, isEmpty);
    expect(store.debts, isEmpty);
  });

  test('backup v2 memuat hutang; backup v1 tetap bisa dipulihkan', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'BCA'));
    await store.createDebt(Debt(kind: DebtKind.payable, name: 'Budi', startDate: now), amount: 70000, walletId: w);
    final json = await store.exportJson();
    expect(json, contains('"kait-backup"'));
    final (other, _, _) = await makeStore(now: now);
    await other.importJson(json);
    expect(other.totalPayable, 70000);

    final v1 = '{"format":"fintrack-backup","version":1,"data":{"wallets":[],"categories":[],'
        '"goals":[],"recurrings":[],"transactions":[]}}';
    await other.importJson(v1);
    expect(other.debts, isEmpty);
  });

  test('migrasi database v1 → v2 tidak menghilangkan data', () async {
    setUpFfi();
    final path = '${(await databaseFactory.getDatabasesPath())}/migrate_test_${DateTime.now().microsecondsSinceEpoch}.db';
    final v1 = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE wallets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
                'kind TEXT NOT NULL, icon TEXT NOT NULL, color INTEGER NOT NULL, initial_balance INTEGER NOT NULL '
                'DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0)');
            await db.execute("CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, "
                "kind TEXT NOT NULL CHECK(kind IN ('expense','income')), icon TEXT NOT NULL, color INTEGER NOT NULL, "
                "monthly_limit INTEGER NOT NULL DEFAULT 0, is_saving INTEGER NOT NULL DEFAULT 0, archived INTEGER "
                "NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0)");
            await db.execute('CREATE TABLE goals (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
                'target INTEGER NOT NULL, icon TEXT NOT NULL, color INTEGER NOT NULL, deadline TEXT, archived '
                'INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)');
            await db.execute("CREATE TABLE recurrings (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, "
                "type TEXT NOT NULL CHECK(type IN ('expense','income')), amount INTEGER NOT NULL, category_id INTEGER "
                "REFERENCES categories(id) ON DELETE SET NULL, wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON "
                "DELETE CASCADE, day_of_month INTEGER NOT NULL, next_date TEXT NOT NULL, auto_record INTEGER NOT NULL "
                "DEFAULT 1, active INTEGER NOT NULL DEFAULT 1, note TEXT NOT NULL DEFAULT '')");
            await db.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL "
                "CHECK(type IN ('expense','income','transfer')), amount INTEGER NOT NULL CHECK(amount > 0), "
                "category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL, wallet_id INTEGER NOT NULL "
                "REFERENCES wallets(id) ON DELETE CASCADE, to_wallet_id INTEGER REFERENCES wallets(id) ON DELETE "
                "CASCADE, goal_id INTEGER REFERENCES goals(id) ON DELETE SET NULL, recurring_id INTEGER REFERENCES "
                "recurrings(id) ON DELETE SET NULL, date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', created_at "
                "TEXT NOT NULL)");
            await db.execute('CREATE INDEX idx_txn_date ON transactions(date)');
            await db.insert('wallets', {'name': 'Tunai', 'kind': 'cash', 'icon': 'cash', 'color': 1});
            await db.insert('recurrings', {
              'title': 'Kos', 'type': 'expense', 'amount': 1, 'wallet_id': 1, 'day_of_month': 5,
              'next_date': '2026-10-05T00:00:00.000',
            });
            await db.insert('transactions', {
              'type': 'expense', 'amount': 25000, 'wallet_id': 1, 'recurring_id': 1,
              'date': '2026-09-28T12:00:00.000', 'note': 'kopi', 'created_at': '2026-09-28T12:00:00.000',
            });
          },
        ));
    await v1.close();

    // Tambah satu pos bernama "Tagihan & Kos" (v1) → setelah migrasi v3 jadi pos bulanan.
    final raw = await databaseFactory.openDatabase(path, options: OpenDatabaseOptions(version: 1));
    await raw.insert('categories', {'name': 'Tagihan & Kos', 'kind': 'expense', 'icon': 'home', 'color': 1});
    await raw.insert('categories', {'name': 'Makan & Minum', 'kind': 'expense', 'icon': 'food', 'color': 1});
    await raw.close();

    final db = await AppDatabase.open(path: path);
    final cats = await db.categories();
    expect(cats.firstWhere((c) => c.name == 'Tagihan & Kos').countsDaily, isFalse);
    expect(cats.firstWhere((c) => c.name == 'Makan & Minum').countsDaily, isTrue);
    expect((await db.transactions()).single.note, 'kopi');
    expect((await db.recurrings()).single.title, 'Kos');
    final debtId = await db.insertDebt(Debt(kind: DebtKind.payable, name: 'Budi', startDate: now));
    await db.insertTxn(Txn(type: TxnType.debtIn, amount: 1000, walletId: 1, debtId: debtId, date: now));
    expect((await db.transactions()).length, 2);
    await db.close();
  });

  test('cicilan berhenti kalau sisa jadi negatif karena pinjaman dihapus', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'BCA'));
    final id = await store.createDebt(Debt(kind: DebtKind.payable, name: 'X', startDate: DateTime(2026, 9, 1)),
        amount: 1000000, walletId: w);
    await store.recordDebtTxn(store.debt(id)!, amount: 400000, walletId: w, date: DateTime(2026, 9, 2));
    await store.saveDebtInstallment(
      store.debt(id)!,
      Recurring(title: 'c', type: TxnType.debtOut, amount: 100000, walletId: w, dayOfMonth: 1,
          nextDate: DateTime(2026, 10, 1), debtId: id),
    );
    final loan = store.debtTxns(id).firstWhere((t) => t.type == TxnType.debtIn);
    await store.deleteTxn(loan.id!);
    expect(store.debtRecurrings(id).single.active, isFalse);
  });
}
