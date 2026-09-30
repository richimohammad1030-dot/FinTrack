// Laporan per hari: berapa yang keluar setiap hari, ke pos mana, dan
// dibandingkan dengan jatah hari itu. Murni (tanpa UI) supaya mudah diuji.

import '../data/models.dart';
import 'budget.dart';
import 'period.dart';

enum DayStatus {
  /// Hari yang belum terjadi.
  future,

  /// Tidak ada pengeluaran harian.
  zero,

  /// Di bawah 80% jatah.
  ok,

  /// 80–100% jatah.
  near,

  /// Lewat jatah.
  over,
}

class DayReport {
  final DateTime day;

  /// Pengeluaran pos harian (yang dihitung di jatah harian).
  final int dailySpent;

  /// Semua pengeluaran (termasuk pos bulanan, tanpa tabungan).
  final int allSpent;
  final int saved;
  final int income;

  /// Jatah harian yang berlaku pada hari itu.
  final int allowance;

  /// Total per pos (pengeluaran & tabungan).
  final Map<int, int> byCategory;
  final List<Txn> txns;
  final DayStatus status;

  const DayReport({
    required this.day,
    required this.dailySpent,
    required this.allSpent,
    required this.saved,
    required this.income,
    required this.allowance,
    required this.byCategory,
    required this.txns,
    required this.status,
  });

  int get remaining => allowance - dailySpent;
  bool get hasActivity => txns.isNotEmpty;
}

class PeriodDailyReport {
  final PayPeriod period;
  final List<DayReport> days;

  const PeriodDailyReport(this.period, this.days);

  DayReport? dayOf(DateTime d) {
    final t = dateOnly(d);
    for (final r in days) {
      if (r.day == t) return r;
    }
    return null;
  }

  Iterable<DayReport> get past => days.where((d) => d.status != DayStatus.future);
  int get totalDaily => past.fold(0, (a, d) => a + d.dailySpent);
  int get totalAll => past.fold(0, (a, d) => a + d.allSpent);
  int get elapsedDays => past.length;
  int get averageDaily => elapsedDays == 0 ? 0 : totalDaily ~/ elapsedDays;
  int get overDays => past.where((d) => d.status == DayStatus.over).length;
  int get okDays => past.where((d) => d.status == DayStatus.ok || d.status == DayStatus.zero).length;

  static PeriodDailyReport build({
    required PayPeriod period,
    required PeriodSummary summary,
    required Iterable<Txn> txns,
    required List<Pos> categories,
    required Set<int> savingIds,
    required DateTime now,
    int manualLimit = 0,
  }) {
    final today = dateOnly(now);
    final byDay = <DateTime, List<Txn>>{};
    for (final t in txns) {
      if (period.contains(t.date)) byDay.putIfAbsent(dateOnly(t.date), () => []).add(t);
    }
    final reports = <DayReport>[];
    for (final day in period.days) {
      final list = byDay[day] ?? const <Txn>[];
      var all = 0, saved = 0, income = 0;
      final byCat = <int, int>{};
      for (final t in list) {
        if (t.isIncome) income += t.amount;
        if (!t.isExpense) continue;
        final c = t.categoryId ?? uncategorizedId;
        byCat[c] = (byCat[c] ?? 0) + t.amount;
        if (savingIds.contains(c)) {
          saved += t.amount;
        } else {
          all += t.amount;
        }
      }
      final daily = summary.spentOn(day);
      final future = day.isAfter(today);
      final allowance = DailyBudget.compute(
        summary: summary,
        categories: categories,
        today: day,
        manualLimit: manualLimit,
      ).allowance;
      final DayStatus status;
      if (future) {
        status = DayStatus.future;
      } else if (daily == 0) {
        status = DayStatus.zero;
      } else {
        status = switch (levelFor(daily, allowance)) {
          BudgetLevel.over => DayStatus.over,
          BudgetLevel.warning => DayStatus.near,
          BudgetLevel.none => daily > 0 ? DayStatus.over : DayStatus.zero,
          BudgetLevel.ok => DayStatus.ok,
        };
      }
      final sorted = [...list]..sort((a, b) => b.date.compareTo(a.date));
      reports.add(DayReport(
        day: day,
        dailySpent: daily,
        allSpent: all,
        saved: saved,
        income: income,
        allowance: allowance,
        byCategory: byCat,
        txns: sorted,
        status: status,
      ));
    }
    return PeriodDailyReport(period, reports);
  }
}
