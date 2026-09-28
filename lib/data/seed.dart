// Pos & sumber pemasukan bawaan saat aplikasi pertama kali dipasang.

import 'models.dart';

/// Persentase saran pembagian gaji per pos (dipakai tombol "Saran otomatis").
/// Kunci = nama pos bawaan. Total 100.
const suggestedSplit = <String, int>{
  'Tabungan': 20,
  'Makan & Minum': 25,
  'Tagihan & Kos': 20,
  'Transportasi': 8,
  'Kebutuhan Rumah': 7,
  'Hiburan & Jajan': 8,
  'Kesehatan': 4,
  'Keluarga & Sosial': 5,
  'Lainnya': 3,
};

List<Pos> defaultCategories() {
  var order = 0;
  Pos e(String name, String icon, int color, {bool saving = false}) => Pos(
        name: name,
        kind: PosKind.expense,
        icon: icon,
        color: color,
        isSaving: saving,
        sortOrder: order++,
      );
  Pos i(String name, String icon, int color) => Pos(
        name: name,
        kind: PosKind.income,
        icon: icon,
        color: color,
        sortOrder: order++,
      );
  return [
    e('Tabungan', 'savings', 0xFF4A3AA7, saving: true),
    e('Makan & Minum', 'food', 0xFFEB6834),
    e('Tagihan & Kos', 'home', 0xFF2A78D6),
    e('Transportasi', 'car', 0xFF1BAF7A),
    e('Kebutuhan Rumah', 'cart', 0xFFEDA100),
    e('Hiburan & Jajan', 'game', 0xFFE87BA4),
    e('Kesehatan', 'health', 0xFFE34948),
    e('Keluarga & Sosial', 'people', 0xFF008300),
    e('Lainnya', 'category', 0xFF64748B),
    i('Gaji', 'work', 0xFF10B981),
    i('Bonus / THR', 'gift', 0xFF22C55E),
    i('Freelance', 'laptop', 0xFF0EA5E9),
    i('Profit Trading', 'trend', 0xFF8B5CF6),
    i('Lainnya', 'category', 0xFF64748B),
  ];
}
