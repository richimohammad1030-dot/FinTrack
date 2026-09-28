// Membaca hasil OCR struk belanja: total, tanggal, nama toko, tebakan pos.
// Murni (tanpa plugin) supaya mudah diuji. Input berupa baris teks beserta
// posisi kotaknya (kalau ada) dari ML Kit.

class OcrLine {
  final String text;
  final double? left, top, right, bottom;

  const OcrLine(this.text, {this.left, this.top, this.right, this.bottom});

  bool get hasBox => top != null && bottom != null && left != null;
  double get centerY => (top! + bottom!) / 2;
  double get height => bottom! - top!;
}

class ReceiptResult {
  final int? total;
  final DateTime? date;
  final String? merchant;

  /// Nama pos bawaan yang paling cocok (mis. "Makan & Minum").
  final String? categoryName;

  /// true kalau total ditemukan dari baris berlabel TOTAL (lebih yakin),
  /// false kalau hanya menebak angka terbesar.
  final bool confident;

  const ReceiptResult({this.total, this.date, this.merchant, this.categoryName, this.confident = false});

  bool get isEmpty => total == null && date == null && merchant == null;
}

// ── Nominal ──────────────────────────────────────────────────────────────

final _amountRe = RegExp(
  r'(?<![\d.,])(?:rp\.?\s*)?(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d{3,9}(?:[.,]\d{2})?)(?![\d.,]*\d)(?!\s?[a-zA-Z]{1,3}\b(?<!rp))',
  caseSensitive: false,
);

/// Ambil semua nominal rupiah dari satu baris. "125.000" → 125000,
/// "125,000.00" → 125000, "Rp 12.500,00" → 12500, "15000" → 15000.
List<int> parseAmounts(String line) {
  final out = <int>[];
  // Abaikan jam (12:30) dan tanggal (28/09/2026) supaya tidak terbaca nominal.
  final cleaned = line
      .replaceAll(RegExp(r'(?<![\d.,])\d{1,2}[:.]\d{2}(?::\d{2})?(?![\d.,]*\d)\s*(wib|wita|wit)?', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\d{1,4}[/\-]\d{1,2}[/\-]\d{1,4}'), ' ');
  for (final m in _amountRe.allMatches(cleaned)) {
    var raw = m.group(1)!;
    // Buang pecahan sen: separator terakhir diikuti 1–2 digit.
    raw = raw.replaceFirst(RegExp(r'[.,]\d{1,2}$'), '');
    final digits = raw.replaceAll(RegExp(r'[.,]'), '');
    final v = int.tryParse(digits);
    if (v != null && v >= 100 && v < 1000000000) out.add(v);
  }
  return out;
}

// ── Kata kunci ───────────────────────────────────────────────────────────

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Skor baris sebagai label total. 0 = bukan label total.
int _totalScore(String line) {
  final l = _norm(line).replaceAll(RegExp(r'[^a-z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  const exclude = [
    'sub total', 'subtotal', 'total item', 'total qty', 'total disc', 'total diskon', 'total hemat',
    'total potongan', 'total ppn', 'total pajak', 'total tax', 'total quantity', 'jumlah item', 'jml item',
    'total point', 'total poin', 'total barang',
  ];
  if (exclude.any(l.contains)) return 0;
  if (RegExp(r'\bgrand total\b').hasMatch(l)) return 10;
  if (RegExp(r'\btotal (bayar|belanja|pembayaran|harga|tagihan|akhir)\b').hasMatch(l)) return 9;
  if (RegExp(r'\b(amount due|total due|total amount|net total|total nett?)\b').hasMatch(l)) return 9;
  if (RegExp(r'\b(total|ttl)\b').hasMatch(l)) return 8;
  if (RegExp(r'\b(jumlah bayar|jumlah tagihan|tagihan|netto|nett)\b').hasMatch(l)) return 6;
  if (RegExp(r'\bjumlah\b').hasMatch(l)) return 4;
  return 0;
}

/// Baris yang nominalnya BUKAN total belanja (uang dibayar, kembalian, dll).
bool _isNoiseLine(String line) {
  final l = _norm(line);
  return RegExp(
    r'(?<![a-z])(tunai|cash|kembali|kembalian|change|debit|kredit|credit|kartu|card|bca|mandiri|bri|bni|qris|'
    r'ovo|gopay|dana|shopeepay|voucher|poin|point|hemat|diskon|disc|potongan|ppn|pajak|tax|'
    r'telp|tlp|phone|hp|npwp|no\.|nomor|kode|member|ref|trx|transaksi|kasir|struk|nota|inv|invoice)(?![a-z])',
  ).hasMatch(l);
}

// ── Tanggal ──────────────────────────────────────────────────────────────

const _months = {
  'jan': 1, 'feb': 2, 'peb': 2, 'mar': 3, 'apr': 4, 'mei': 5, 'may': 5, 'jun': 6, 'jul': 7,
  'agu': 8, 'ags': 8, 'aug': 8, 'sep': 9, 'okt': 10, 'oct': 10, 'nov': 11, 'nop': 11, 'des': 12, 'dec': 12,
};

DateTime? parseReceiptDate(String text, DateTime now) {
  bool plausible(DateTime d) =>
      !d.isAfter(now.add(const Duration(days: 1))) && d.isAfter(DateTime(now.year - 1, now.month, now.day));
  int year(String y) {
    final v = int.parse(y);
    return v < 100 ? 2000 + v : v;
  }

  DateTime? build(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    if (dt.month != m) return null; // mis. 31 Feb
    return plausible(dt) ? dt : null;
  }

  // 2026-09-28
  for (final m in RegExp(r'\b(20\d{2})[/\-.](\d{1,2})[/\-.](\d{1,2})\b').allMatches(text)) {
    final d = build(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (d != null) return d;
  }
  // 28/09/2026, 28-09-26, 28.09.2026 (format Indonesia: tanggal dulu)
  for (final m in RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b').allMatches(text)) {
    final d = build(year(m[3]!), int.parse(m[2]!), int.parse(m[1]!)) ??
        build(year(m[3]!), int.parse(m[1]!), int.parse(m[2]!)); // cadangan: format AS
    if (d != null) return d;
  }
  // 28 Sep 2026, 28-Sep-26
  for (final m in RegExp(r'\b(\d{1,2})[\s\-/]*([a-z]{3})[a-z]*[\s\-/,]*(\d{2,4})\b', caseSensitive: false)
      .allMatches(text)) {
    final mon = _months[m[2]!.toLowerCase()];
    if (mon == null) continue;
    final d = build(year(m[3]!), mon, int.parse(m[1]!));
    if (d != null) return d;
  }
  return null;
}

// ── Nama toko & tebakan pos ──────────────────────────────────────────────

String? _merchant(List<String> lines) {
  for (final raw in lines.take(5)) {
    final l = raw.trim();
    final letters = RegExp(r'[A-Za-z]').allMatches(l).length;
    if (letters < 3) continue;
    final n = _norm(l);
    if (RegExp(r'^(struk|receipt|nota|invoice|faktur|selamat|welcome|terima kasih|jl\b|jalan|telp|npwp)').hasMatch(n)) {
      continue;
    }
    if (RegExp(r'\d{5,}').hasMatch(n)) continue;
    // Rapikan: huruf kapital di awal kata.
    final cleaned = l.replaceAll(RegExp(r'[^A-Za-z0-9&\-\. ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) continue;
    final titled = cleaned
        .split(' ')
        .map((w) => w.length <= 3 && w.toUpperCase() == w ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
    return titled.length > 40 ? titled.substring(0, 40) : titled;
  }
  return null;
}

const _categoryKeywords = <String, List<String>>{
  'Transportasi': [
    'spbu', 'pertamina', 'pertalite', 'pertamax', 'solar', 'shell', 'bp-akr', 'bp akr', 'vivo energy',
    'parkir', 'parking', 'e-toll', 'tol ', 'bensin', 'grab', 'gojek', 'krl', 'mrt', 'transjakarta',
  ],
  'Kesehatan': [
    'apotek', 'apotik', 'kimia farma', 'k-24', 'k24', 'century', 'guardian', 'watsons', 'klinik',
    'rumah sakit', 'hospital', 'farma', 'optik', 'lab ',
  ],
  'Makan & Minum': [
    'resto', 'restoran', 'restaurant', 'rumah makan', 'warung', 'cafe', 'kafe', 'coffee', 'kopi',
    'bakery', 'mcdonald', "mcd", 'kfc', 'burger', 'pizza', 'hokben', 'solaria', 'starbucks', 'janji jiwa',
    'kenangan', 'chatime', 'mixue', 'bakso', 'sate', 'ayam', 'mie ', 'noodle', 'dimsum', 'food', 'makan',
  ],
  'Hiburan & Jajan': ['cinema', 'xxi', 'cgv', 'cinepolis', 'bioskop', 'karaoke', 'timezone', 'game', 'steam'],
  'Tagihan & Kos': ['pln', 'token listrik', 'pdam', 'indihome', 'telkom', 'bpjs', 'iuran'],
  'Kebutuhan Rumah': [
    'indomaret', 'alfamart', 'alfamidi', 'superindo', 'hypermart', 'transmart', 'carrefour', 'lotte mart',
    'giant', 'hero', 'supermarket', 'minimarket', 'swalayan', 'toko', 'mart', 'grosir', 'ace hardware',
    'informa', 'ikea', 'daiso', 'miniso',
  ],
};

final _categoryRes = {
  for (final e in _categoryKeywords.entries)
    e.key: RegExp('(?<![a-z0-9])(${e.value.map((k) => RegExp.escape(k.trim())).join('|')})(?![a-z0-9])'),
};

String? guessCategory(String text) {
  final t = _norm(text);
  // Kata utuh saja: "solar" tidak cocok dengan "Solaria", "mart" tidak dengan "Smart".
  for (final e in _categoryRes.entries) {
    if (e.value.hasMatch(t)) return e.key;
  }
  return null;
}

// ── Utama ────────────────────────────────────────────────────────────────

ReceiptResult parseReceipt(List<OcrLine> lines, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final texts = [for (final l in lines) l.text.trim()]..removeWhere((t) => t.isEmpty);
  if (texts.isEmpty) return const ReceiptResult();
  final all = texts.join('\n');

  // 1) Cari baris berlabel TOTAL, lalu ambil nominal di baris yang sama,
  //    di sebelah kanannya (posisi kotak), atau di baris berikutnya.
  int? best;
  var bestScore = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final score = _totalScore(line.text);
    if (score == 0) continue;
    int? amount;
    final own = parseAmounts(line.text);
    if (own.isNotEmpty) amount = own.last;
    if (amount == null && line.hasBox) {
      // Cari baris lain yang sejajar secara horizontal (kolom harga).
      OcrLine? match;
      for (final o in lines) {
        if (identical(o, line) || !o.hasBox) continue;
        final sameRow = (o.centerY - line.centerY).abs() < line.height * 0.7;
        if (sameRow && o.left! > line.left! && parseAmounts(o.text).isNotEmpty) {
          if (match == null || o.left! > match.left!) match = o;
        }
      }
      if (match != null) amount = parseAmounts(match.text).last;
    }
    if (amount == null) {
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final next = lines[j].text;
        if (_totalScore(next) > 0 || _isNoiseLine(next)) break;
        final a = parseAmounts(next);
        if (a.isNotEmpty) {
          amount = a.last;
          break;
        }
      }
    }
    if (amount == null) continue;
    // Skor lebih tinggi menang; kalau sama, yang lebih bawah (grand total
    // biasanya di bawah).
    if (score >= bestScore) {
      bestScore = score;
      best = amount;
    }
  }

  var confident = best != null;
  // 2) Cadangan: nominal terbesar dari baris yang bukan pembayaran/kembalian.
  if (best == null) {
    var maxV = 0;
    for (final t in texts) {
      if (_isNoiseLine(t)) continue;
      for (final a in parseAmounts(t)) {
        if (a > maxV) maxV = a;
      }
    }
    if (maxV > 0) best = maxV;
    confident = false;
  }

  return ReceiptResult(
    total: best,
    date: parseReceiptDate(all, n),
    merchant: _merchant(texts),
    // Nama toko di bagian atas lebih bisa dipercaya daripada isi barang.
    categoryName: guessCategory(texts.take(3).join(' ')) ?? guessCategory(all),
    confident: confident,
  );
}
