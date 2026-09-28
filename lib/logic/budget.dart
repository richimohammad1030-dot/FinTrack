// Perhitungan anggaran: ringkasan periode, batas harian, status pos, peringatan.
// Semua fungsi di sini murni (tanpa database/UI) supaya mudah diuji.

import '../data/models.dart';
import 'period.dart';

/// Kunci untuk transaksi yang posnya sudah dihapus.
const uncategorizedId = 0;

class PeriodSummary {
  final PayPeriod period;
  final int income;

  /// Pengeluaran riil (tidak termasuk setoran tabungan).
  final int expense;

  /// Uang yang disisihkan ke pos tabungan.
  final int saving;

  /// Total per pos pengeluaran (termasuk pos tabungan).
  final Map<int, int> byCategory;

  /// Total per sumber pemasukan.
  final Map<int, int> incomeByCategory;

  /// Pengeluaran HARIAN per hari (hanya pos yang masuk jatah harian;
  /// kos, tagihan, dll. tidak termasuk). Kunci = tanggal tanpa jam.
  final Map<DateTime, int> daily;

  /// Uang masuk / keluar karena hutang-piutang (bukan pemasukan/pengeluaran).
  final int debtIn;
  final int debtOut;

  const PeriodSummary({
    required this.period,
    required this.income,
    required this.expense,
    required this.saving,
    required this.byCategory,
    required this.incomeByCategory,
    required this.daily,
    this.debtIn = 0,
    this.debtOut = 0,
  });

  /// Sisa uang periode ini: pemasukan − pengeluaran − tabungan, ditambah
  /// arus hutang (pinjam = masuk, bayar hutang = keluar).
  int get net => income - expense - saving + debtIn - debtOut;

  int spentOn(DateTime day) => daily[dateOnly(day)] ?? 0;
  int spentIn(int categoryId) => byCategory[categoryId] ?? 0;

  static PeriodSummary compute(
    Iterable<Txn> txns,
    PayPeriod period,
    Set<int> savingCategoryIds, {
    Set<int> nonDailyIds = const {},
  }) {
    var income = 0, expense = 0, saving = 0, debtIn = 0, debtOut = 0;
    final byCat = <int, int>{};
    final incomeByCat = <int, int>{};
    final daily = <DateTime, int>{};
    for (final t in txns) {
      if (!period.contains(t.date)) continue;
      final cat = t.categoryId ?? uncategorizedId;
      switch (t.type) {
        case TxnType.income:
          income += t.amount;
          incomeByCat[cat] = (incomeByCat[cat] ?? 0) + t.amount;
        case TxnType.expense:
          byCat[cat] = (byCat[cat] ?? 0) + t.amount;
          if (savingCategoryIds.contains(cat)) {
            saving += t.amount;
          } else {
            expense += t.amount;
            if (!nonDailyIds.contains(cat)) {
              final d = dateOnly(t.date);
              daily[d] = (daily[d] ?? 0) + t.amount;
            }
          }
        case TxnType.transfer:
          break;
        case TxnType.debtIn:
          debtIn += t.amount;
        case TxnType.debtOut:
          debtOut += t.amount;
      }
    }
    return PeriodSummary(
      period: period,
      income: income,
      expense: expense,
      saving: saving,
      byCategory: byCat,
      incomeByCategory: incomeByCat,
      daily: daily,
      debtIn: debtIn,
      debtOut: debtOut,
    );
  }
}

enum BudgetLevel { none, ok, warning, over }

/// Level peringatan: ≥80% = warning, ≥100% = over.
BudgetLevel levelFor(int spent, int limit) {
  if (limit <= 0) return BudgetLevel.none;
  final r = spent / limit;
  if (r >= 1) return BudgetLevel.over;
  if (r >= 0.8) return BudgetLevel.warning;
  return BudgetLevel.ok;
}

class DailyBudget {
  /// Batas aman hari ini.
  final int allowance;
  final int spentToday;

  /// Anggaran pengeluaran total periode (dasar perhitungan).
  final int periodBudget;
  final int daysLeft;
  final bool isManual;

  const DailyBudget({
    required this.allowance,
    required this.spentToday,
    required this.periodBudget,
    required this.daysLeft,
    required this.isManual,
  });

  int get remainingToday => allowance - spentToday;
  double get ratio => allowance <= 0 ? (spentToday > 0 ? 1 : 0) : spentToday / allowance;
  BudgetLevel get level => allowance <= 0
      ? (spentToday > 0 ? BudgetLevel.over : BudgetLevel.none)
      : levelFor(spentToday, allowance);

  /// Batas harian otomatis = (anggaran periode − yang sudah terpakai sebelum
  /// hari ini) ÷ sisa hari. Jadi kalau kemarin boros, jatah hari ini mengecil;
  /// kalau hemat, jatah hari ini membesar.
  static DailyBudget compute({
    required PeriodSummary summary,
    required List<Pos> categories,
    required DateTime today,
    int manualLimit = 0,
  }) {
    final period = summary.period;
    final t = dateOnly(today);
    final spentToday = summary.spentOn(t);
    final daysLeft = period.daysLeft(t);

    final budget = periodBudgetFor(summary, categories);
    if (manualLimit > 0) {
      return DailyBudget(
        allowance: manualLimit,
        spentToday: spentToday,
        periodBudget: budget,
        daysLeft: daysLeft,
        isManual: true,
      );
    }
    var spentBefore = 0;
    summary.daily.forEach((day, v) {
      if (day.isBefore(t)) spentBefore += v;
    });
    final left = budget - spentBefore;
    var allowance = daysLeft > 0 && left > 0 ? left ~/ daysLeft : 0;
    // Bulatkan ke bawah ke kelipatan 500 biar enak dibaca.
    allowance = allowance - allowance % 500;
    return DailyBudget(
      allowance: allowance,
      spentToday: spentToday,
      periodBudget: budget,
      daysLeft: daysLeft,
      isManual: false,
    );
  }
}

/// Anggaran HARIAN periode: jumlah batas pos yang masuk jatah harian
/// (makan, transport, jajan…). Pos bulanan seperti kos & tagihan tidak ikut.
/// Kalau pos harian belum diberi batas, pakai: pemasukan − tabungan − pos
/// bulanan (batasnya, atau yang sudah terpakai kalau lebih besar).
int periodBudgetFor(PeriodSummary summary, List<Pos> categories) {
  var dailyLimits = 0, reserved = 0;
  for (final c in categories) {
    if (!c.isExpense || c.archived) continue;
    if (c.isDaily) {
      dailyLimits += c.monthlyLimit;
    } else {
      final spent = c.id == null ? 0 : summary.spentIn(c.id!);
      reserved += c.monthlyLimit > spent ? c.monthlyLimit : spent;
    }
  }
  if (dailyLimits > 0) return dailyLimits;
  final fallback = summary.income - reserved;
  return fallback > 0 ? fallback : 0;
}

class PosStatus {
  final Pos category;
  final int spent;
  final int daysLeft;

  const PosStatus(this.category, this.spent, this.daysLeft);

  int get limit => category.monthlyLimit;
  int get remaining => limit - spent;
  double get ratio => limit <= 0 ? 0 : spent / limit;
  BudgetLevel get level => category.isSaving ? BudgetLevel.none : levelFor(spent, limit);

  /// Jatah per hari yang tersisa untuk pos ini.
  int get perDayLeft => daysLeft <= 0 || remaining <= 0 ? 0 : remaining ~/ daysLeft;
}

List<PosStatus> posStatuses(
  PeriodSummary summary,
  List<Pos> categories,
  DateTime today,
) {
  final daysLeft = summary.period.daysLeft(today);
  return [
    for (final c in categories)
      if (c.isExpense && !c.archived) PosStatus(c, summary.spentIn(c.id!), daysLeft),
  ];
}

// ── Peringatan ─────────────────────────────────────────────────────────────

enum AlertScope { daily, category }

class BudgetAlert {
  final AlertScope scope;
  final BudgetLevel level;
  final String title;
  final String message;
  final int? categoryId;

  const BudgetAlert({
    required this.scope,
    required this.level,
    required this.title,
    required this.message,
    this.categoryId,
  });
}

/// Bandingkan kondisi sebelum & sesudah transaksi baru, kembalikan peringatan
/// untuk setiap batas yang baru saja terlewati (80% atau 100%).
List<BudgetAlert> alertsAfterChange({
  required PeriodSummary before,
  required PeriodSummary after,
  required List<Pos> categories,
  required DateTime today,
  required int manualDailyLimit,
  required String Function(int) fmt,
}) {
  final alerts = <BudgetAlert>[];
  final db0 = DailyBudget.compute(
      summary: before, categories: categories, today: today, manualLimit: manualDailyLimit);
  final db1 = DailyBudget.compute(
      summary: after, categories: categories, today: today, manualLimit: manualDailyLimit);
  if ((db1.allowance > 0 || db1.periodBudget > 0) && db1.level.index > db0.level.index) {
    if (db1.level == BudgetLevel.over) {
      alerts.add(BudgetAlert(
        scope: AlertScope.daily,
        level: BudgetLevel.over,
        title: 'Batas harian terlewati',
        message: 'Hari ini sudah keluar ${fmt(db1.spentToday)} dari batas ${fmt(db1.allowance)}. '
            'Kelebihannya akan mengurangi jatah hari-hari berikutnya.',
      ));
    } else if (db1.level == BudgetLevel.warning) {
      alerts.add(BudgetAlert(
        scope: AlertScope.daily,
        level: BudgetLevel.warning,
        title: 'Hampir mencapai batas harian',
        message: 'Sisa jatah hari ini tinggal ${fmt(db1.remainingToday)}.',
      ));
    }
  }
  for (final c in categories) {
    if (!c.isExpense || c.isSaving || !c.hasLimit || c.archived) continue;
    final l0 = levelFor(before.spentIn(c.id!), c.monthlyLimit);
    final spent = after.spentIn(c.id!);
    final l1 = levelFor(spent, c.monthlyLimit);
    if (l1.index <= l0.index) continue;
    if (l1 == BudgetLevel.over) {
      alerts.add(BudgetAlert(
        scope: AlertScope.category,
        level: BudgetLevel.over,
        categoryId: c.id,
        title: 'Pos ${c.name} habis',
        message: 'Terpakai ${fmt(spent)} dari ${fmt(c.monthlyLimit)} '
            '(${(spent * 100 / c.monthlyLimit).round()}%).',
      ));
    } else if (l1 == BudgetLevel.warning) {
      alerts.add(BudgetAlert(
        scope: AlertScope.category,
        level: BudgetLevel.warning,
        categoryId: c.id,
        title: 'Pos ${c.name} tinggal sedikit',
        message: 'Sudah terpakai ${(spent * 100 / c.monthlyLimit).round()}%, '
            'sisa ${fmt(c.monthlyLimit - spent)}.',
      ));
    }
  }
  return alerts;
}
