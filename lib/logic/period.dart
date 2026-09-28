// Periode gajian: dari tanggal gajian sampai sehari sebelum gajian berikutnya.
// Contoh gajian tgl 25 → 25 Sep s/d 24 Okt.

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Selisih hari kalender dari [a] ke [b] (aman dari pergeseran jam/DST).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Tanggal gajian di bulan tertentu. Kalau gajian tgl 31 dan bulannya hanya
/// 30 hari, dipakai tanggal terakhir bulan itu.
DateTime paydayIn(int year, int month, int payday) {
  // Normalisasi bulan di luar 1..12
  final norm = DateTime(year, month, 1);
  final day = payday.clamp(1, daysInMonth(norm.year, norm.month));
  return DateTime(norm.year, norm.month, day);
}

class PayPeriod {
  /// Hari pertama periode (inklusif).
  final DateTime start;

  /// Hari pertama periode berikutnya (eksklusif).
  final DateTime end;
  final int payday;

  const PayPeriod._(this.start, this.end, this.payday);

  /// Periode yang memuat tanggal [ref].
  factory PayPeriod.containing(DateTime ref, int payday) {
    final d = dateOnly(ref);
    final thisMonth = paydayIn(d.year, d.month, payday);
    final start = d.isBefore(thisMonth) ? paydayIn(d.year, d.month - 1, payday) : thisMonth;
    final end = paydayIn(start.year, start.month + 1, payday);
    return PayPeriod._(start, end, payday);
  }

  PayPeriod get previous => PayPeriod.containing(DateTime(start.year, start.month, start.day - 1), payday);
  PayPeriod get next => PayPeriod.containing(end, payday);

  /// Hari terakhir periode (inklusif).
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  int get totalDays => daysBetween(start, end);

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  /// Sisa hari termasuk hari [today]. Minimal 1 selama today di dalam periode.
  int daysLeft(DateTime today) {
    final t = dateOnly(today);
    if (t.isBefore(start)) return totalDays;
    if (!t.isBefore(end)) return 0;
    return daysBetween(t, end);
  }

  /// Hari ke-berapa dalam periode (mulai 1).
  int dayIndex(DateTime d) => daysBetween(start, d) + 1;

  /// Daftar semua tanggal di periode ini.
  List<DateTime> get days => [
        for (var i = 0; i < totalDays; i++) DateTime(start.year, start.month, start.day + i),
      ];

  @override
  bool operator ==(Object other) =>
      other is PayPeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
