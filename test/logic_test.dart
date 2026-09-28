import 'package:kait/data/models.dart';
import 'package:kait/logic/budget.dart';
import 'package:kait/logic/period.dart';
import 'package:kait/logic/recurring.dart';
import 'package:flutter_test/flutter_test.dart';

Txn exp(int amount, DateTime date, {int cat = 1}) =>
    Txn(type: TxnType.expense, amount: amount, categoryId: cat, walletId: 1, date: date);
Txn inc(int amount, DateTime date) =>
    Txn(type: TxnType.income, amount: amount, categoryId: 99, walletId: 1, date: date);

void main() {
  group('PayPeriod', () {
    test('gajian tgl 25: 28 Sep masuk periode 25 Sep – 24 Okt', () {
      final p = PayPeriod.containing(DateTime(2026, 9, 28, 14), 25);
      expect(p.start, DateTime(2026, 9, 25));
      expect(p.end, DateTime(2026, 10, 25));
      expect(p.lastDay, DateTime(2026, 10, 24));
      expect(p.totalDays, 30);
      expect(p.daysLeft(DateTime(2026, 9, 28)), 27);
    });

    test('sebelum tanggal gajian masih periode bulan lalu', () {
      final p = PayPeriod.containing(DateTime(2026, 9, 10), 25);
      expect(p.start, DateTime(2026, 8, 25));
      expect(p.end, DateTime(2026, 9, 25));
    });

    test('gajian tgl 31 di bulan pendek memakai tanggal terakhir', () {
      final p = PayPeriod.containing(DateTime(2026, 2, 28), 31);
      expect(p.start, DateTime(2026, 2, 28));
      expect(p.end, DateTime(2026, 3, 31));
      final prev = p.previous;
      expect(prev.start, DateTime(2026, 1, 31));
      expect(prev.end, DateTime(2026, 2, 28));
    });

    test('pergantian tahun', () {
      final p = PayPeriod.containing(DateTime(2027, 1, 3), 25);
      expect(p.start, DateTime(2026, 12, 25));
      expect(p.next.start, DateTime(2027, 1, 25));
    });

    test('gajian tgl 1 = bulan kalender', () {
      final p = PayPeriod.containing(DateTime(2026, 9, 28), 1);
      expect(p.start, DateTime(2026, 9, 1));
      expect(p.end, DateTime(2026, 10, 1));
      expect(p.days.length, 30);
    });
  });

  group('Ringkasan & batas harian', () {
    final period = PayPeriod.containing(DateTime(2026, 9, 25), 25); // 30 hari
    final cats = [
      const Pos(id: 1, name: 'Makan', kind: PosKind.expense, monthlyLimit: 1500000),
      const Pos(id: 2, name: 'Transport', kind: PosKind.expense, monthlyLimit: 600000),
      const Pos(id: 3, name: 'Tabungan', kind: PosKind.expense, monthlyLimit: 1000000, isSaving: true),
    ];

    test('tabungan tidak dihitung sebagai pengeluaran', () {
      final s = PeriodSummary.compute([
        inc(5000000, DateTime(2026, 9, 25)),
        exp(1000000, DateTime(2026, 9, 25), cat: 3),
        exp(50000, DateTime(2026, 9, 26)),
        exp(20000, DateTime(2026, 10, 25)), // periode berikutnya
      ], period, {3});
      expect(s.income, 5000000);
      expect(s.saving, 1000000);
      expect(s.expense, 50000);
      expect(s.net, 3950000);
      expect(s.spentIn(3), 1000000);
    });

    test('batas harian = (anggaran − terpakai sebelum hari ini) ÷ sisa hari', () {
      final s = PeriodSummary.compute([
        exp(300000, DateTime(2026, 9, 25)),
        exp(40000, DateTime(2026, 9, 28, 12)),
      ], period, {3});
      final d = DailyBudget.compute(summary: s, categories: cats, today: DateTime(2026, 9, 28, 18));
      // anggaran 2.100.000 − 300.000 = 1.800.000 ÷ 27 hari = 66.666 → 66.500
      expect(d.periodBudget, 2100000);
      expect(d.daysLeft, 27);
      expect(d.allowance, 66500);
      expect(d.spentToday, 40000);
      expect(d.remainingToday, 26500);
      expect(d.level, BudgetLevel.ok);
    });

    test('tanpa batas pos, anggaran = pemasukan − target tabungan', () {
      final noLimits = [
        const Pos(id: 1, name: 'Makan', kind: PosKind.expense),
        const Pos(id: 3, name: 'Tabungan', kind: PosKind.expense, monthlyLimit: 1000000, isSaving: true),
      ];
      final s = PeriodSummary.compute([inc(4000000, DateTime(2026, 9, 25))], period, {3});
      final d = DailyBudget.compute(summary: s, categories: noLimits, today: DateTime(2026, 9, 25));
      expect(d.periodBudget, 3000000);
      expect(d.allowance, 100000);
    });

    test('batas manual dipakai apa adanya', () {
      final s = PeriodSummary.compute([exp(120000, DateTime(2026, 9, 28))], period, {3});
      final d = DailyBudget.compute(
          summary: s, categories: cats, today: DateTime(2026, 9, 28), manualLimit: 100000);
      expect(d.allowance, 100000);
      expect(d.level, BudgetLevel.over);
    });

    test('peringatan muncul saat melewati 80% dan 100%', () {
      final today = DateTime(2026, 9, 28, 9);
      final before = PeriodSummary.compute([exp(400000, DateTime(2026, 9, 25), cat: 2)], period, {3});
      final after = PeriodSummary.compute([
        exp(400000, DateTime(2026, 9, 25), cat: 2),
        exp(90000, today, cat: 2),
      ], period, {3});
      final alerts = alertsAfterChange(
        before: before,
        after: after,
        categories: cats,
        today: today,
        manualDailyLimit: 0,
        fmt: (v) => '$v',
      );
      final catAlert = alerts.singleWhere((a) => a.scope == AlertScope.category);
      expect(catAlert.categoryId, 2);
      expect(catAlert.level, BudgetLevel.warning); // 490rb / 600rb = 82%

      final after2 = PeriodSummary.compute([
        exp(400000, DateTime(2026, 9, 25), cat: 2),
        exp(230000, today, cat: 2),
      ], period, {3});
      final alerts2 = alertsAfterChange(
        before: before,
        after: after2,
        categories: cats,
        today: today,
        manualDailyLimit: 0,
        fmt: (v) => '$v',
      );
      expect(alerts2.where((a) => a.scope == AlertScope.category).single.level, BudgetLevel.over);
      // 230rb hari ini > jatah harian ~62rb
      expect(alerts2.where((a) => a.scope == AlertScope.daily).single.level, BudgetLevel.over);
    });

    test('tidak ada peringatan ulang kalau level tidak naik', () {
      final s = PeriodSummary.compute([exp(10000, DateTime(2026, 9, 26))], period, {3});
      final alerts = alertsAfterChange(
          before: s, after: s, categories: cats, today: DateTime(2026, 9, 26), manualDailyLimit: 0, fmt: (v) => '$v');
      expect(alerts, isEmpty);
    });
  });

  group('Transaksi rutin', () {
    test('jatuh tempo yang terlewat dicatat semua', () {
      final r = Recurring(
        title: 'Kos',
        type: TxnType.expense,
        amount: 1500000,
        walletId: 1,
        dayOfMonth: 5,
        nextDate: DateTime(2026, 7, 5),
      );
      expect(dueDates(r, DateTime(2026, 9, 28)),
          [DateTime(2026, 7, 5), DateTime(2026, 8, 5), DateTime(2026, 9, 5)]);
    });

    test('tanggal 31 menyesuaikan bulan pendek', () {
      expect(nextDue(DateTime(2026, 1, 31), 31), DateTime(2026, 2, 28));
      expect(nextDue(DateTime(2026, 2, 28), 31), DateTime(2026, 3, 31));
      expect(firstDueOnOrAfter(DateTime(2026, 9, 28), 5), DateTime(2026, 10, 5));
      expect(firstDueOnOrAfter(DateTime(2026, 9, 28), 28), DateTime(2026, 9, 28));
    });
  });

  test('pos bulanan (kos) tidak mengurangi jatah harian', () {
    final period = PayPeriod.containing(DateTime(2026, 9, 28), 28); // 28 Sep – 27 Okt, 30 hari
    final cats = [
      const Pos(id: 1, name: 'Makan', kind: PosKind.expense, monthlyLimit: 1500000),
      const Pos(id: 2, name: 'Transport', kind: PosKind.expense, monthlyLimit: 600000),
      const Pos(id: 4, name: 'Tagihan & Kos', kind: PosKind.expense, monthlyLimit: 1400000, countsDaily: false),
    ];
    final today = DateTime(2026, 9, 28, 18);
    final s = PeriodSummary.compute([
      exp(1400000, today, cat: 4), // bayar kos
      exp(300000, today, cat: 4), // token listrik
      exp(40000, today, cat: 1), // makan
    ], period, const {}, nonDailyIds: {4});
    final d = DailyBudget.compute(summary: s, categories: cats, today: today);
    expect(s.expense, 1740000); // tetap tercatat sebagai pengeluaran
    expect(d.periodBudget, 2100000); // hanya pos harian
    expect(d.allowance, 70000); // 2.100.000 ÷ 30
    expect(d.spentToday, 40000); // kos & listrik tidak ikut
    expect(d.level, BudgetLevel.ok);
  });
}
