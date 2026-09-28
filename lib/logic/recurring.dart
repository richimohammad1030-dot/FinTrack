// Penjadwalan transaksi rutin bulanan.

import '../data/models.dart';
import 'period.dart';

/// Tanggal jatuh tempo pertama yang ≥ [from] untuk tanggal [dayOfMonth].
DateTime firstDueOnOrAfter(DateTime from, int dayOfMonth) {
  final f = dateOnly(from);
  final thisMonth = paydayIn(f.year, f.month, dayOfMonth);
  return thisMonth.isBefore(f) ? paydayIn(f.year, f.month + 1, dayOfMonth) : thisMonth;
}

/// Jatuh tempo berikutnya setelah [date].
DateTime nextDue(DateTime date, int dayOfMonth) => paydayIn(date.year, date.month + 1, dayOfMonth);

/// Semua tanggal jatuh tempo yang sudah lewat / hari ini dan belum diproses.
List<DateTime> dueDates(Recurring r, DateTime today) {
  if (!r.active) return const [];
  final t = dateOnly(today);
  final out = <DateTime>[];
  var d = dateOnly(r.nextDate);
  // Batasi 24 bulan supaya tidak berputar tanpa akhir kalau data aneh.
  while (!d.isAfter(t) && out.length < 24) {
    out.add(d);
    d = nextDue(d, r.dayOfMonth);
  }
  return out;
}
