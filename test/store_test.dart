import 'package:fintrack/data/models.dart';
import 'package:fintrack/logic/budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'test_utils.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  final now = DateTime(2026, 9, 28, 19);

  test('pos bawaan terisi saat database dibuat', () async {
    final (store, _, _) = await makeStore(now: now);
    expect(store.expenseCategories.map((c) => c.name), contains('Makan & Minum'));
    expect(store.savingCategory?.name, 'Tabungan');
    expect(store.incomeCategories.map((c) => c.name), contains('Gaji'));
  });

  test('saldo dompet, transfer, dan tabungan', () async {
    final (store, _, _) = await makeStore(now: now);
    final cash = await store.saveWallet(const Wallet(name: 'Tunai', initialBalance: 200000));
    final bank = await store.saveWallet(const Wallet(name: 'BCA', kind: WalletKind.bank));
    final gaji = store.incomeCategories.first.id!;
    final makan = store.expenseCategories.firstWhere((c) => c.name == 'Makan & Minum').id!;
    final tabungan = store.savingCategory!.id!;
    final goalId = await store.db.insertGoal(Goal(name: 'Dana darurat', target: 10000000));
    await store.load();

    await store.addTxn(Txn(type: TxnType.income, amount: 6000000, categoryId: gaji, walletId: bank, date: DateTime(2026, 9, 25)));
    await store.addTxn(Txn(type: TxnType.transfer, amount: 500000, walletId: bank, toWalletId: cash, date: DateTime(2026, 9, 25)));
    await store.addTxn(Txn(type: TxnType.expense, amount: 35000, categoryId: makan, walletId: cash, date: DateTime(2026, 9, 28, 12)));
    await store.addTxn(Txn(type: TxnType.expense, amount: 1000000, categoryId: tabungan, goalId: goalId, walletId: bank, date: DateTime(2026, 9, 25)));

    expect(store.walletBalance(cash), 200000 + 500000 - 35000);
    expect(store.walletBalance(bank), 6000000 - 500000 - 1000000);
    expect(store.totalBalance, 5165000);
    expect(store.goalSaved(goalId), 1000000);
    expect(store.currentSummary.expense, 35000);
    expect(store.currentSummary.saving, 1000000);
    // Urutan: terbaru di atas
    expect(store.transactions.first.amount, 35000);
  });

  test('hapus & urungkan transaksi', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'Tunai'));
    await store.addTxn(Txn(type: TxnType.expense, amount: 10000, categoryId: 2, walletId: w, date: now));
    final id = store.transactions.single.id!;
    final removed = await store.deleteTxn(id);
    expect(store.transactions, isEmpty);
    await store.restoreTxn(removed!);
    expect(store.transactions.single.id, id);
    expect((await store.db.transactions()).length, 1);
  });

  test('peringatan pos memicu notifikasi', () async {
    final (store, _, notifier) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'Tunai'));
    final makan = store.expenseCategories.firstWhere((c) => c.name == 'Makan & Minum');
    await store.saveLimits({makan.id!: 100000});
    final alerts = await store.addTxn(
        Txn(type: TxnType.expense, amount: 85000, categoryId: makan.id, walletId: w, date: now));
    expect(alerts.any((a) => a.scope == AlertScope.category && a.level == BudgetLevel.warning), isTrue);
    expect(notifier.shown, isNotEmpty);
  });

  test('transaksi rutin otomatis tercatat saat jatuh tempo', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'BCA'));
    await store.saveRecurring(Recurring(
      title: 'Internet',
      type: TxnType.expense,
      amount: 350000,
      categoryId: 3,
      walletId: w,
      dayOfMonth: 20,
      nextDate: DateTime(2026, 8, 20),
    ));
    expect(store.transactions.length, 2); // 20 Agu & 20 Sep
    expect(store.recurrings.single.nextDate, DateTime(2026, 10, 20));
    // Memuat ulang tidak membuat duplikat
    await store.load();
    expect(store.transactions.length, 2);
  });

  test('tagihan mode "ingatkan saja" menunggu konfirmasi', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'BCA'));
    await store.saveRecurring(Recurring(
      title: 'Listrik',
      type: TxnType.expense,
      amount: 300000,
      walletId: w,
      dayOfMonth: 27,
      nextDate: DateTime(2026, 9, 27),
      autoRecord: false,
    ));
    expect(store.transactions, isEmpty);
    expect(store.pendingRecurring.single.title, 'Listrik');
    await store.confirmRecurring(store.pendingRecurring.single, 275000);
    expect(store.transactions.single.amount, 275000);
    expect(store.pendingRecurring, isEmpty);
  });

  test('backup lalu restore mengembalikan data yang sama', () async {
    final (store, settings, _) = await makeStore(now: now);
    settings.payday = 27;
    final w = await store.saveWallet(const Wallet(name: 'Tunai', initialBalance: 50000));
    await store.addTxn(Txn(type: TxnType.expense, amount: 12000, categoryId: 2, walletId: w, date: now, note: 'kopi'));
    final json = await store.exportJson();

    final (other, otherSettings, _) = await makeStore(now: now);
    await other.importJson(json);
    expect(other.transactions.single.note, 'kopi');
    expect(other.walletBalance(other.wallets.single.id!), 38000);
    expect(otherSettings.payday, 27);
    expect(otherSettings.onboarded, isTrue);

    expect(() => other.importJson('{"hello":1}'), throwsFormatException);
  });

  test('backup tidak lengkap ditolak tanpa menghapus data', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'Tunai'));
    await store.addTxn(Txn(type: TxnType.expense, amount: 5000, categoryId: 2, walletId: w, date: now));
    expect(
      () => store.importJson('{"format":"fintrack-backup","version":1,"data":{}}'),
      throwsFormatException,
    );
    expect((await store.db.transactions()).length, 1);
  });

  test('proses transaksi rutin bersamaan tidak membuat duplikat', () async {
    final (store, _, _) = await makeStore(now: now);
    final w = await store.saveWallet(const Wallet(name: 'BCA'));
    await store.db.insertRecurring(Recurring(
      title: 'Kos',
      type: TxnType.expense,
      amount: 1000000,
      walletId: w,
      dayOfMonth: 1,
      nextDate: DateTime(2026, 9, 1),
    ));
    await Future.wait([store.processRecurring(), store.processRecurring(), store.load()]);
    expect((await store.db.transactions()).length, 1);
  });

  test('hapus semua data kembali ke onboarding', () async {
    final (store, settings, _) = await makeStore(now: now);
    settings.onboarded = true;
    settings.estimatedIncome = 5000000;
    await store.saveWallet(const Wallet(name: 'Tunai'));
    await store.resetAll();
    expect(settings.onboarded, isFalse);
    expect(settings.estimatedIncome, 0);
    expect(store.wallets, isEmpty);
    expect(store.expenseCategories, isNotEmpty);
  });
}
