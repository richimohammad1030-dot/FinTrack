// lib/models/transaction_model.dart
// Pro-Tracker - Transaction Model (v3)
// Kategori expense eksklusif, field notes, clean enum.

enum TransactionType { income, expense }

enum TransactionCategory {
  // ── Pemasukan ────────────────────────────
  gajiUtama,
  freelance,
  profitTrading,

  // ── Pengeluaran ──────────────────────────
  makanMinum,
  jajanHiburan,
  kebutuhanBulanan,
  transportasi,
  kesehatan,
  belanjaShopping,
  lainnya,
}

// ── Extensions ────────────────────────────────────────────────────────────────

extension TransactionTypeX on TransactionType {
  String get value => this == TransactionType.income ? 'income' : 'expense';

  static TransactionType fromString(String v) {
    switch (v) {
      case 'income':
        return TransactionType.income;
      case 'expense':
        return TransactionType.expense;
      default:
        throw ArgumentError('Unknown TransactionType: $v');
    }
  }
}

extension TransactionCategoryX on TransactionCategory {
  String get value {
    switch (this) {
      case TransactionCategory.gajiUtama:         return 'Gaji Utama';
      case TransactionCategory.freelance:          return 'Freelance';
      case TransactionCategory.profitTrading:      return 'Profit Trading';
      case TransactionCategory.makanMinum:         return 'Makan & Minum';
      case TransactionCategory.jajanHiburan:       return 'Jajan & Hiburan';
      case TransactionCategory.kebutuhanBulanan:   return 'Kebutuhan Bulanan';
      case TransactionCategory.transportasi:       return 'Transportasi';
      case TransactionCategory.kesehatan:          return 'Kesehatan';
      case TransactionCategory.belanjaShopping:    return 'Belanja/Shopping';
      case TransactionCategory.lainnya:            return 'Lainnya';
    }
  }

  String get emoji {
    switch (this) {
      case TransactionCategory.gajiUtama:         return '💼';
      case TransactionCategory.freelance:          return '💻';
      case TransactionCategory.profitTrading:      return '📈';
      case TransactionCategory.makanMinum:         return '🍽️';
      case TransactionCategory.jajanHiburan:       return '🎮';
      case TransactionCategory.kebutuhanBulanan:   return '🏠';
      case TransactionCategory.transportasi:       return '🚗';
      case TransactionCategory.kesehatan:          return '❤️';
      case TransactionCategory.belanjaShopping:    return '🛍️';
      case TransactionCategory.lainnya:            return '📦';
    }
  }

  static TransactionCategory fromString(String v) {
    switch (v) {
      case 'Gaji Utama':          return TransactionCategory.gajiUtama;
      case 'Freelance':            return TransactionCategory.freelance;
      case 'Profit Trading':       return TransactionCategory.profitTrading;
      case 'Makan & Minum':        return TransactionCategory.makanMinum;
      case 'Jajan & Hiburan':      return TransactionCategory.jajanHiburan;
      case 'Kebutuhan Bulanan':    return TransactionCategory.kebutuhanBulanan;
      case 'Transportasi':         return TransactionCategory.transportasi;
      case 'Kesehatan':            return TransactionCategory.kesehatan;
      case 'Belanja/Shopping':     return TransactionCategory.belanjaShopping;
      default:                     return TransactionCategory.lainnya;
    }
  }

  bool get isIncomeCategory =>
      this == TransactionCategory.gajiUtama ||
      this == TransactionCategory.freelance ||
      this == TransactionCategory.profitTrading;
}

// ── Lists helper (dipakai di form) ────────────────────────────────────────────

const kIncomeCategories = [
  TransactionCategory.gajiUtama,
  TransactionCategory.freelance,
  TransactionCategory.profitTrading,
];

const kExpenseCategories = [
  TransactionCategory.makanMinum,
  TransactionCategory.jajanHiburan,
  TransactionCategory.kebutuhanBulanan,
  TransactionCategory.transportasi,
  TransactionCategory.kesehatan,
  TransactionCategory.belanjaShopping,
  TransactionCategory.lainnya,
];

// ── Model ─────────────────────────────────────────────────────────────────────

class TransactionModel {
  final int? id;
  final String title;
  final double amount;
  final TransactionType type;
  final TransactionCategory category;
  final DateTime date;
  final String? notes;

  const TransactionModel({
    this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
    this.notes,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id:       map['id'] as int?,
      title:    map['title'] as String,
      amount:   (map['amount'] as num).toDouble(),
      type:     TransactionTypeX.fromString(map['type'] as String),
      category: TransactionCategoryX.fromString(map['category'] as String),
      date:     DateTime.parse(map['date'] as String),
      notes:    map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'title':    title,
    'amount':   amount,
    'type':     type.value,
    'category': category.value,
    'date':     date.toIso8601String(),
    'notes':    notes,
  };

  TransactionModel copyWith({
    int? id, String? title, double? amount,
    TransactionType? type, TransactionCategory? category,
    DateTime? date, String? notes,
  }) => TransactionModel(
    id:       id ?? this.id,
    title:    title ?? this.title,
    amount:   amount ?? this.amount,
    type:     type ?? this.type,
    category: category ?? this.category,
    date:     date ?? this.date,
    notes:    notes ?? this.notes,
  );

  @override
  bool operator ==(Object other) =>
      other is TransactionModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}