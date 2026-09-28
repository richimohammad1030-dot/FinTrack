import 'package:kait/logic/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<OcrLine> lines(String s) => [for (final l in s.split('\n')) OcrLine(l)];

void main() {
  final now = DateTime(2026, 9, 28, 19);

  group('parseAmounts', () {
    test('format Indonesia, Inggris, polos, dengan sen', () {
      expect(parseAmounts('TOTAL 125.000'), [125000]);
      expect(parseAmounts('Total Rp 1.250.000,00'), [1250000]);
      expect(parseAmounts('TOTAL 125,000.00'), [125000]);
      expect(parseAmounts('Grand Total 58500'), [58500]);
      expect(parseAmounts('Rp12.500'), [12500]);
    });

    test('jam dan tanggal tidak dianggap nominal', () {
      expect(parseAmounts('28/09/2026 12:45'), isEmpty);
      expect(parseAmounts('Tgl 28.09.26 Jam 19.30'), isEmpty);
    });
  });

  test('struk minimarket: ambil TOTAL, bukan TUNAI/KEMBALI/SUBTOTAL', () {
    final r = parseReceipt(lines('''
INDOMARET
JL. SUDIRMAN NO 12
NPWP 01.234.567.8-901.000
28.09.26-19:12 2.0.21 1234567/KASIR/01
AQUA 600ML        2    3.500     7.000
INDOMIE GORENG    5    3.100    15.500
TEH PUCUK         1    4.000     4.000
SUB TOTAL                       26.500
TOTAL ITEM 8
HEMAT                            1.000
TOTAL                           25.500
TUNAI                           50.000
KEMBALI                         24.500
TERIMA KASIH'''), now: now);
    expect(r.total, 25500);
    expect(r.confident, isTrue);
    expect(r.date, DateTime(2026, 9, 28));
    expect(r.merchant, 'Indomaret');
    expect(r.categoryName, 'Kebutuhan Rumah');
  });

  test('restoran: GRAND TOTAL menang atas TOTAL', () {
    final r = parseReceipt(lines('''
Warung Kopi Senja
Jl. Braga 5 Bandung
Tanggal: 27 Sep 2026
Kopi Susu        2   25,000
Roti Bakar       1   18,000
Total                68,000
Service 5%            3,400
PPN 10%               7,140
Grand Total          78,540
Cash                100,000
Change               21,460'''), now: now);
    expect(r.total, 78540);
    expect(r.date, DateTime(2026, 9, 27));
    expect(r.merchant, 'Warung Kopi Senja');
    expect(r.categoryName, 'Makan & Minum');
  });

  test('label dan nominal terpisah kolom (pakai posisi kotak ML Kit)', () {
    final r = parseReceipt([
      const OcrLine('SPBU 34.123.45', left: 10, top: 0, right: 200, bottom: 20),
      const OcrLine('PERTALITE', left: 10, top: 40, right: 120, bottom: 60),
      const OcrLine('Total Harga', left: 10, top: 100, right: 120, bottom: 120),
      const OcrLine('Rp. 50.000', left: 300, top: 102, right: 400, bottom: 122),
      const OcrLine('Tunai', left: 10, top: 140, right: 80, bottom: 160),
      const OcrLine('Rp. 100.000', left: 300, top: 141, right: 400, bottom: 161),
    ], now: now);
    expect(r.total, 50000);
    expect(r.categoryName, 'Transportasi');
  });

  test('label lalu nominal di baris berikutnya (tanpa kotak)', () {
    final r = parseReceipt(lines('APOTEK SEHAT\nTOTAL BAYAR\nRp 87.300\nDEBIT BCA\n87.300'), now: now);
    expect(r.total, 87300);
    expect(r.categoryName, 'Kesehatan');
  });

  test('tanpa label total: pakai nominal terbesar selain uang dibayar', () {
    final r = parseReceipt(lines('Toko Makmur\nBeras 5kg 72.000\nMinyak 2L 38.000\n110.000\nTunai 150.000'), now: now);
    expect(r.total, 110000);
    expect(r.confident, isFalse);
  });

  test('tanggal yang tidak masuk akal diabaikan', () {
    expect(parseReceiptDate('12/31/2026', now), isNull); // masa depan
    expect(parseReceiptDate('09/15/2026', now), DateTime(2026, 9, 15)); // format AS sebagai cadangan
    expect(parseReceiptDate('2026-09-01', now), DateTime(2026, 9, 1));
    expect(parseReceiptDate('01 Jan 2020', now), isNull); // terlalu lama
  });

  test('teks kosong', () {
    expect(parseReceipt(const [], now: now).isEmpty, isTrue);
  });

  test('kata kunci pos harus kata utuh', () {
    expect(guessCategory('SOLARIA Mall Kota Kasablanka'), 'Makan & Minum');
    expect(guessCategory('SPBU 34.12 SOLAR'), 'Transportasi');
    expect(guessCategory('Smartphone Center'), isNull);
  });
}
