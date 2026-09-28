// Data contoh untuk widget test & screenshot.

import 'package:kait/data/models.dart';
import 'package:kait/state/finance_store.dart';

Future<void> seedDemo(FinanceStore store) async {
  final s = store.settings;
  s.payday = 25;
  s.estimatedIncome = 7500000;
  s.onboarded = true;

  final cash = await store.saveWallet(const Wallet(name: 'Tunai', kind: WalletKind.cash, icon: 'cash', color: 0xFF1BAF7A, initialBalance: 350000));
  final bca = await store.saveWallet(const Wallet(name: 'BCA', kind: WalletKind.bank, icon: 'bank', color: 0xFF2A78D6, initialBalance: 1200000));
  final gopay = await store.saveWallet(const Wallet(name: 'GoPay', kind: WalletKind.ewallet, icon: 'phone', color: 0xFF4A3AA7, initialBalance: 80000));

  int cat(String name) => store.categories.firstWhere((c) => c.name == name).id!;
  final limits = {
    cat('Tabungan'): 1500000,
    cat('Makan & Minum'): 1800000,
    cat('Tagihan & Kos'): 1700000,
    cat('Transportasi'): 600000,
    cat('Kebutuhan Rumah'): 450000,
    cat('Hiburan & Jajan'): 500000,
    cat('Kesehatan'): 250000,
    cat('Keluarga & Sosial'): 500000,
    cat('Lainnya'): 200000,
  };
  await store.saveLimits(limits);

  final goalId = await store.db.insertGoal(Goal(
      name: 'Dana darurat', target: 22500000, icon: 'emergency', color: 0xFF4A3AA7, deadline: DateTime(2027, 6, 30)));
  await store.db.insertGoal(Goal(name: 'Liburan Bali', target: 6000000, icon: 'beach', color: 0xFFEB6834));
  await store.load();

  Future<void> e(int day, int month, int amount, String c, int w, String note, {int hour = 12, int? goal}) =>
      store.db.insertTxn(Txn(
        type: TxnType.expense,
        amount: amount,
        categoryId: cat(c),
        walletId: w,
        goalId: goal,
        date: DateTime(2026, month, day, hour),
        note: note,
      ));

  // Periode lalu (25 Agu – 24 Sep)
  await store.db.insertTxn(Txn(type: TxnType.income, amount: 7500000, categoryId: cat('Gaji'), walletId: bca, date: DateTime(2026, 8, 25, 9), note: 'Gaji Agustus'));
  await e(25, 8, 1500000, 'Tabungan', bca, 'Setor dana darurat', goal: goalId);
  await e(26, 8, 1700000, 'Tagihan & Kos', bca, 'Kos + listrik');
  for (var d = 26; d <= 31; d++) {
    await e(d, 8, 45000 + d * 1000, 'Makan & Minum', cash, 'Makan harian');
  }
  for (var d = 1; d <= 24; d++) {
    await e(d, 9, 52000 + (d % 5) * 9000, 'Makan & Minum', d.isEven ? cash : gopay, 'Makan harian');
    if (d % 3 == 0) await e(d, 9, 25000, 'Transportasi', gopay, 'Ojol');
  }
  await e(6, 9, 380000, 'Hiburan & Jajan', bca, 'Konser');
  await e(14, 9, 210000, 'Kebutuhan Rumah', bca, 'Belanja bulanan');

  // Periode ini (25 Sep – 24 Okt), hari ini 28 Sep
  await store.db.insertTxn(Txn(type: TxnType.income, amount: 7500000, categoryId: cat('Gaji'), walletId: bca, date: DateTime(2026, 9, 25, 9), note: 'Gaji September'));
  await store.db.insertTxn(Txn(type: TxnType.income, amount: 850000, categoryId: cat('Freelance'), walletId: bca, date: DateTime(2026, 9, 26, 15), note: 'Desain logo'));
  await e(25, 9, 1500000, 'Tabungan', bca, 'Setor dana darurat', hour: 10, goal: goalId);
  await e(25, 9, 1700000, 'Tagihan & Kos', bca, 'Kos + listrik', hour: 11);
  await store.db.insertTxn(Txn(type: TxnType.transfer, amount: 500000, walletId: bca, toWalletId: cash, date: DateTime(2026, 9, 25, 12), note: 'Tarik tunai'));
  await e(25, 9, 68000, 'Makan & Minum', cash, 'Makan malam', hour: 19);
  await e(26, 9, 385000, 'Kebutuhan Rumah', bca, 'Belanja bulanan', hour: 10);
  await e(26, 9, 95000, 'Makan & Minum', gopay, 'Makan siang tim', hour: 13);
  await e(27, 9, 420000, 'Hiburan & Jajan', bca, 'Nonton + jajan', hour: 16);
  await e(27, 9, 150000, 'Transportasi', cash, 'Bensin', hour: 8);
  await e(28, 9, 32000, 'Makan & Minum', cash, 'Sarapan', hour: 7);
  await e(28, 9, 28000, 'Makan & Minum', gopay, 'Makan siang', hour: 12);
  await e(28, 9, 18000, 'Transportasi', gopay, 'Ojol ke kantor', hour: 8);

  await store.saveRecurring(Recurring(
    title: 'Tagihan listrik',
    type: TxnType.expense,
    amount: 280000,
    categoryId: cat('Tagihan & Kos'),
    walletId: bca,
    dayOfMonth: 28,
    nextDate: DateTime(2026, 9, 28),
    autoRecord: false,
  ));
  // Hutang & piutang
  final kredivo = await store.createDebt(
    Debt(kind: DebtKind.payable, name: 'Kredivo', startDate: DateTime(2026, 6, 10), dueDate: DateTime(2026, 10, 2),
        note: 'Cicilan HP'),
    amount: 2400000,
  );
  await store.db.insertTxn(Txn(type: TxnType.debtOut, amount: 400000, walletId: bca, debtId: kredivo,
      date: DateTime(2026, 7, 10, 9)));
  await store.db.insertTxn(Txn(type: TxnType.debtOut, amount: 400000, walletId: bca, debtId: kredivo,
      date: DateTime(2026, 8, 10, 9)));
  await store.db.insertTxn(Txn(type: TxnType.debtOut, amount: 400000, walletId: bca, debtId: kredivo,
      date: DateTime(2026, 9, 10, 9)));
  await store.createDebt(Debt(kind: DebtKind.receivable, name: 'Andi', startDate: DateTime(2026, 9, 26),
      dueDate: DateTime(2026, 10, 25)), amount: 300000, walletId: cash);
  await store.load();
}
