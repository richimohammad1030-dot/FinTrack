// Model data FinTrack.
// Semua nominal disimpan sebagai int (rupiah penuh) supaya tidak ada error
// pembulatan seperti pada double.

enum TxnType { expense, income, transfer }

extension TxnTypeX on TxnType {
  String get key => name;
  static TxnType parse(String v) =>
      TxnType.values.firstWhere((e) => e.name == v, orElse: () => TxnType.expense);
  String get label => switch (this) {
        TxnType.expense => 'Pengeluaran',
        TxnType.income => 'Pemasukan',
        TxnType.transfer => 'Transfer',
      };
}

enum PosKind { expense, income }

enum WalletKind { cash, bank, ewallet, other }

extension WalletKindX on WalletKind {
  static WalletKind parse(String v) =>
      WalletKind.values.firstWhere((e) => e.name == v, orElse: () => WalletKind.other);
  String get label => switch (this) {
        WalletKind.cash => 'Tunai',
        WalletKind.bank => 'Rekening Bank',
        WalletKind.ewallet => 'E-Wallet',
        WalletKind.other => 'Lainnya',
      };
  String get defaultIcon => switch (this) {
        WalletKind.cash => 'cash',
        WalletKind.bank => 'bank',
        WalletKind.ewallet => 'phone',
        WalletKind.other => 'wallet',
      };
}

DateTime? _parseDate(Object? v) => v == null ? null : DateTime.parse(v as String);
bool _b(Object? v) => v == 1 || v == true;

/// Dompet / rekening tempat uang berada (Tunai, BCA, GoPay, ...).
class Wallet {
  final int? id;
  final String name;
  final WalletKind kind;
  final String icon;
  final int color;
  final int initialBalance;
  final bool archived;
  final int sortOrder;

  const Wallet({
    this.id,
    required this.name,
    this.kind = WalletKind.cash,
    this.icon = 'wallet',
    this.color = 0xFF10B981,
    this.initialBalance = 0,
    this.archived = false,
    this.sortOrder = 0,
  });

  factory Wallet.fromMap(Map<String, Object?> m) => Wallet(
        id: m['id'] as int?,
        name: m['name'] as String,
        kind: WalletKindX.parse(m['kind'] as String),
        icon: m['icon'] as String,
        color: m['color'] as int,
        initialBalance: m['initial_balance'] as int,
        archived: _b(m['archived']),
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'kind': kind.name,
        'icon': icon,
        'color': color,
        'initial_balance': initialBalance,
        'archived': archived ? 1 : 0,
        'sort_order': sortOrder,
      };

  Wallet copyWith({
    int? id,
    String? name,
    WalletKind? kind,
    String? icon,
    int? color,
    int? initialBalance,
    bool? archived,
    int? sortOrder,
  }) =>
      Wallet(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        initialBalance: initialBalance ?? this.initialBalance,
        archived: archived ?? this.archived,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// Pos anggaran (untuk pengeluaran) atau sumber pemasukan.
class Pos {
  final int? id;
  final String name;
  final PosKind kind;
  final String icon;
  final int color;

  /// Batas per periode gajian. 0 = tanpa batas.
  final int monthlyLimit;

  /// Pos tabungan: uangnya disisihkan, bukan "dihabiskan".
  final bool isSaving;
  final bool archived;
  final int sortOrder;

  const Pos({
    this.id,
    required this.name,
    required this.kind,
    this.icon = 'category',
    this.color = 0xFF64748B,
    this.monthlyLimit = 0,
    this.isSaving = false,
    this.archived = false,
    this.sortOrder = 0,
  });

  bool get isExpense => kind == PosKind.expense;
  bool get hasLimit => monthlyLimit > 0;

  factory Pos.fromMap(Map<String, Object?> m) => Pos(
        id: m['id'] as int?,
        name: m['name'] as String,
        kind: (m['kind'] as String) == 'income' ? PosKind.income : PosKind.expense,
        icon: m['icon'] as String,
        color: m['color'] as int,
        monthlyLimit: m['monthly_limit'] as int? ?? 0,
        isSaving: _b(m['is_saving']),
        archived: _b(m['archived']),
        sortOrder: m['sort_order'] as int? ?? 0,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'kind': kind.name,
        'icon': icon,
        'color': color,
        'monthly_limit': monthlyLimit,
        'is_saving': isSaving ? 1 : 0,
        'archived': archived ? 1 : 0,
        'sort_order': sortOrder,
      };

  Pos copyWith({
    int? id,
    String? name,
    PosKind? kind,
    String? icon,
    int? color,
    int? monthlyLimit,
    bool? isSaving,
    bool? archived,
    int? sortOrder,
  }) =>
      Pos(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        monthlyLimit: monthlyLimit ?? this.monthlyLimit,
        isSaving: isSaving ?? this.isSaving,
        archived: archived ?? this.archived,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// Satu transaksi.
class Txn {
  final int? id;
  final TxnType type;
  final int amount;
  final int? categoryId;
  final int walletId;

  /// Dompet tujuan (khusus transfer).
  final int? toWalletId;

  /// Target tabungan yang diisi (khusus setoran ke pos tabungan).
  final int? goalId;
  final int? recurringId;
  final DateTime date;
  final String note;
  final DateTime createdAt;

  Txn({
    this.id,
    required this.type,
    required this.amount,
    this.categoryId,
    required this.walletId,
    this.toWalletId,
    this.goalId,
    this.recurringId,
    required this.date,
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isExpense => type == TxnType.expense;
  bool get isIncome => type == TxnType.income;
  bool get isTransfer => type == TxnType.transfer;

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
        id: m['id'] as int?,
        type: TxnTypeX.parse(m['type'] as String),
        amount: m['amount'] as int,
        categoryId: m['category_id'] as int?,
        walletId: m['wallet_id'] as int,
        toWalletId: m['to_wallet_id'] as int?,
        goalId: m['goal_id'] as int?,
        recurringId: m['recurring_id'] as int?,
        date: DateTime.parse(m['date'] as String),
        note: m['note'] as String? ?? '',
        createdAt: _parseDate(m['created_at']) ?? DateTime.now(),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type.name,
        'amount': amount,
        'category_id': categoryId,
        'wallet_id': walletId,
        'to_wallet_id': toWalletId,
        'goal_id': goalId,
        'recurring_id': recurringId,
        'date': date.toIso8601String(),
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };

  Txn copyWith({int? id}) => Txn(
        id: id ?? this.id,
        type: type,
        amount: amount,
        categoryId: categoryId,
        walletId: walletId,
        toWalletId: toWalletId,
        goalId: goalId,
        recurringId: recurringId,
        date: date,
        note: note,
        createdAt: createdAt,
      );
}

/// Target tabungan (dana darurat, liburan, dll).
class Goal {
  final int? id;
  final String name;
  final int target;
  final String icon;
  final int color;
  final DateTime? deadline;
  final bool archived;
  final DateTime createdAt;

  Goal({
    this.id,
    required this.name,
    required this.target,
    this.icon = 'savings',
    this.color = 0xFF6366F1,
    this.deadline,
    this.archived = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Goal.fromMap(Map<String, Object?> m) => Goal(
        id: m['id'] as int?,
        name: m['name'] as String,
        target: m['target'] as int,
        icon: m['icon'] as String,
        color: m['color'] as int,
        deadline: _parseDate(m['deadline']),
        archived: _b(m['archived']),
        createdAt: _parseDate(m['created_at']),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'target': target,
        'icon': icon,
        'color': color,
        'deadline': deadline?.toIso8601String(),
        'archived': archived ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Transaksi rutin bulanan (kos, internet, cicilan, gaji...).
class Recurring {
  final int? id;
  final String title;
  final TxnType type; // expense / income
  final int amount;
  final int? categoryId;
  final int walletId;
  final int dayOfMonth;

  /// Tanggal jatuh tempo berikutnya (tanpa jam).
  final DateTime nextDate;

  /// true = langsung dicatat otomatis saat jatuh tempo.
  /// false = hanya diingatkan, pengguna konfirmasi nominalnya.
  final bool autoRecord;
  final bool active;
  final String note;

  const Recurring({
    this.id,
    required this.title,
    required this.type,
    required this.amount,
    this.categoryId,
    required this.walletId,
    required this.dayOfMonth,
    required this.nextDate,
    this.autoRecord = true,
    this.active = true,
    this.note = '',
  });

  factory Recurring.fromMap(Map<String, Object?> m) => Recurring(
        id: m['id'] as int?,
        title: m['title'] as String,
        type: TxnTypeX.parse(m['type'] as String),
        amount: m['amount'] as int,
        categoryId: m['category_id'] as int?,
        walletId: m['wallet_id'] as int,
        dayOfMonth: m['day_of_month'] as int,
        nextDate: DateTime.parse(m['next_date'] as String),
        autoRecord: _b(m['auto_record']),
        active: _b(m['active']),
        note: m['note'] as String? ?? '',
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'type': type.name,
        'amount': amount,
        'category_id': categoryId,
        'wallet_id': walletId,
        'day_of_month': dayOfMonth,
        'next_date': nextDate.toIso8601String(),
        'auto_record': autoRecord ? 1 : 0,
        'active': active ? 1 : 0,
        'note': note,
      };

  Recurring copyWith({
    int? id,
    String? title,
    TxnType? type,
    int? amount,
    int? categoryId,
    int? walletId,
    int? dayOfMonth,
    DateTime? nextDate,
    bool? autoRecord,
    bool? active,
    String? note,
  }) =>
      Recurring(
        id: id ?? this.id,
        title: title ?? this.title,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        walletId: walletId ?? this.walletId,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        nextDate: nextDate ?? this.nextDate,
        autoRecord: autoRecord ?? this.autoRecord,
        active: active ?? this.active,
        note: note ?? this.note,
      );
}
