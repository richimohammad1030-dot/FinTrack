import 'package:kait/data/models.dart';
import 'package:kait/logic/budget.dart';
import 'package:kait/logic/daily_report.dart';
import 'package:kait/logic/period.dart';
import 'package:flutter_test/flutter_test.dart';

Txn exp(int amount, DateTime date, int cat) =>
    Txn(type: TxnType.expense, amount: amount, categoryId: cat, walletId: 1, date: date);

void main() {
  final period = PayPeriod.containing(DateTime(2026, 9, 28), 28); // 28 Sep – 27 Okt (30 hari)
  final cats = [
    const Pos(id: 1, name: 'Makan', kind: PosKind.expense, monthlyLimit: 3000000),
    const Pos(id: 2, name: 'Kos', kind: PosKind.expense, monthlyLimit: 1400000, countsDaily: false),
    const Pos(id: 3, name: 'Tabungan', kind: PosKind.expense, monthlyLimit: 1000000, isSaving: true),
  ];
  final txns = [
    exp(1400000, DateTime(2026, 9, 28, 9), 2),
    exp(1000000, DateTime(2026, 9, 28, 9), 3),
    exp(80000, DateTime(2026, 9, 28, 12), 1),
    exp(120000, DateTime(2026, 9, 29, 12), 1),
    exp(95000, DateTime(2026, 9, 29, 19), 1),
  ];
  final now = DateTime(2026, 9, 30, 21);
  final summary = PeriodSummary.compute(txns, period, {3}, nonDailyIds: {2});

  test('rincian per hari: jatah hari itu, status, dan pemisahan pos', () {
    final r = PeriodDailyReport.build(
      period: period, summary: summary, txns: txns, categories: cats, savingIds: {3}, now: now);
    expect(r.days.length, 30);

    final d1 = r.dayOf(DateTime(2026, 9, 28))!;
    expect(d1.dailySpent, 80000); // kos & tabungan tidak ikut jatah
    expect(d1.allSpent, 1480000);
    expect(d1.saved, 1000000);
    expect(d1.allowance, 100000); // 3.000.000 ÷ 30
    expect(d1.status, DayStatus.near); // 80%
    expect(d1.txns.length, 3);

    final d2 = r.dayOf(DateTime(2026, 9, 29))!;
    // (3.000.000 − 80.000) ÷ 29 = 100.689 → 100.500
    expect(d2.allowance, 100500);
    expect(d2.dailySpent, 215000);
    expect(d2.status, DayStatus.over);

    expect(r.dayOf(DateTime(2026, 9, 30))!.status, DayStatus.zero);
    expect(r.dayOf(DateTime(2026, 10, 1))!.status, DayStatus.future);
    expect(r.elapsedDays, 3);
    expect(r.overDays, 1);
    expect(r.totalDaily, 295000);
    expect(r.averageDaily, 98333);
  });

  test('rincian anggaran: pos harian vs cadangan', () {
    final b = BudgetBreakdown.of(summary, cats);
    expect(b.usesFallback, isFalse);
    expect(b.total, 3000000);
    expect(b.dailyPos.single.$1.name, 'Makan');
  });
}
