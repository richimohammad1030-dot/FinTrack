// Format angka rupiah & tanggal (bahasa Indonesia).

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../logic/period.dart';

final _num = NumberFormat.decimalPattern('id_ID');

/// Rp 1.250.000
String rupiah(int v) => '${v < 0 ? '-' : ''}Rp ${_num.format(v.abs())}';

/// +Rp 50.000 / -Rp 50.000
String signedRupiah(int v) => '${v >= 0 ? '+' : '-'}Rp ${_num.format(v.abs())}';

/// Angka pendek untuk grafik & ruang sempit: 850rb, 1,2jt, 3,5M.
String compactRupiah(int v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  String trim(double x) {
    final s = x.toStringAsFixed(x >= 100 ? 0 : 1).replaceAll('.', ',');
    return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
  }

  if (a >= 1000000000) return '$sign${trim(a / 1000000000)}M';
  if (a >= 1000000) return '$sign${trim(a / 1000000)}jt';
  if (a >= 1000) return '$sign${trim(a / 1000)}rb';
  return '$sign$a';
}

String groupDigits(int v) => _num.format(v);

int parseDigits(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

String percent(double r) => '${(r * 100).round()}%';

final _dayMonth = DateFormat('d MMM', 'id_ID');
final _dayMonthYear = DateFormat('d MMM yyyy', 'id_ID');
final _weekdayFull = DateFormat('EEEE, d MMM', 'id_ID');
final _monthYear = DateFormat('MMMM yyyy', 'id_ID');
final _time = DateFormat('HH:mm', 'id_ID');

String fmtDayMonth(DateTime d) => _dayMonth.format(d);
String fmtDate(DateTime d) => _dayMonthYear.format(d);
String fmtMonthYear(DateTime d) => _monthYear.format(d);
String fmtTime(DateTime d) => _time.format(d);

/// "Hari ini", "Kemarin", atau "Senin, 28 Sep".
String fmtRelativeDay(DateTime d, {DateTime? now}) {
  final diff = daysBetween(d, now ?? DateTime.now());
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  if (diff == -1) return 'Besok';
  return _weekdayFull.format(d);
}

/// "25 Sep – 24 Okt"
String fmtPeriod(PayPeriod p) {
  final sameYear = p.start.year == p.lastDay.year && p.start.year == DateTime.now().year;
  return sameYear
      ? '${_dayMonth.format(p.start)} – ${_dayMonth.format(p.lastDay)}'
      : '${_dayMonthYear.format(p.start)} – ${_dayMonthYear.format(p.lastDay)}';
}

/// Input nominal dengan titik ribuan otomatis (20000 → 20.000),
/// posisi kursor tetap wajar saat mengedit di tengah angka.
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter({this.maxDigits = 13});
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    if (digits.length > maxDigits) return oldValue;
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final formatted = _num.format(int.parse(digits));

    // Hitung berapa digit di sebelah kanan kursor, lalu pertahankan.
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsRight =
        newValue.text.substring(cursor).replaceAll(RegExp(r'[^0-9]'), '').length;
    var pos = formatted.length, seen = 0;
    while (pos > 0 && seen < digitsRight) {
      pos--;
      if (RegExp(r'[0-9]').hasMatch(formatted[pos])) seen++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: pos),
    );
  }
}
