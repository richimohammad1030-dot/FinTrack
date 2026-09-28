// State utama aplikasi: memuat semua data dari database, menyediakan
// perhitungan (ringkasan periode, batas harian, saldo dompet, progres target),
// dan aksi CRUD.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/format.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../logic/budget.dart';
import '../logic/period.dart';
import '../logic/recurring.dart';
import '../services/notifications.dart';
import 'settings.dart';

typedef Clock = DateTime Function();

class FinanceStore extends ChangeNotifier {
  FinanceStore({
    required this.db,
    required this.settings,
    Notifier? notifier,
    Clock? clock,
  })  : notifier = notifier ?? NoopNotifier(),
        _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final Settings settings;
  final Notifier notifier;
  final Clock _clock;

  DateTime get now => _clock();

  List<Wallet> _wallets = [];
  List<Pos> _categories = [];
  List<Goal> _goals = [];
  List<Recurring> _recurrings = [];
  List<Txn> _txns = [];
  bool _loaded = false;

  bool get loaded => _loaded;
  List<Wallet> get wallets => _wallets;
  List<Wallet> get activeWallets => _wallets.where((w) => !w.archived).toList();
  List<Pos> get categories => _categories;
  List<Pos> get expenseCategories =>
      _categories.where((c) => c.isExpense && !c.archived).toList();
  List<Pos> get incomeCategories =>
      _categories.where((c) => !c.isExpense && !c.archived).toList();
  List<Goal> get goals => _goals;
  List<Goal> get activeGoals => _goals.where((g) => !g.archived).toList();
  List<Recurring> get recurrings => _recurrings;

  /// Semua transaksi, terbaru di atas.
  List<Txn> get transactions => _txns;

  Map<int, Pos> _catById = {};
  Map<int, Wallet> _walletById = {};
  Pos? category(int? id) => id == null ? null : _catById[id];
  Wallet? wallet(int? id) => id == null ? null : _walletById[id];
  Goal? goal(int? id) => id == null ? null : _goals.where((g) => g.id == id).firstOrNull;

  Set<int> get savingCategoryIds =>
      {for (final c in _categories) if (c.isSaving && c.id != null) c.id!};

  Pos? get savingCategory => expenseCategories.where((c) => c.isSaving).firstOrNull;

  // ── Load ────────────────────────────────────────────────────────────────

  Future<void> load() async {
    await _reloadAll();
    await processRecurring();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _reloadAll() async {
    _wallets = await db.wallets();
    _categories = await db.categories();
    _goals = await db.goals();
    _recurrings = await db.recurrings();
    _txns = await db.transactions();
    _reindex();
  }

  void _reindex() {
    _catById = {for (final c in _categories) c.id!: c};
    _walletById = {for (final w in _wallets) w.id!: w};
    _summaryCache.clear();
  }

  void _changed() {
    _summaryCache.clear();
    notifyListeners();
  }

  // ── Periode & anggaran ──────────────────────────────────────────────────

  PayPeriod get currentPeriod => PayPeriod.containing(now, settings.payday);

  final _summaryCache = <PayPeriod, PeriodSummary>{};

  PeriodSummary summaryFor(PayPeriod p) =>
      _summaryCache[p] ??= PeriodSummary.compute(_txns, p, savingCategoryIds);

  PeriodSummary get currentSummary => summaryFor(currentPeriod);

  DailyBudget get dailyBudget => DailyBudget.compute(
        summary: currentSummary,
        categories: _categories,
        today: now,
        manualLimit: settings.manualDailyLimit,
      );

  List<PosStatus> statusesFor(PayPeriod p) => posStatuses(summaryFor(p), _categories, now);

  List<PosStatus> get currentStatuses => statusesFor(currentPeriod);

  /// Pos yang sudah ≥80% terpakai di periode ini.
  List<PosStatus> get warnings => currentStatuses
      .where((s) => s.level == BudgetLevel.warning || s.level == BudgetLevel.over)
      .toList()
    ..sort((a, b) => b.ratio.compareTo(a.ratio));

  /// Total batas semua pos (termasuk tabungan) — dipakai di "Bagi Gaji".
  int get totalAllocated =>
      expenseCategories.fold(0, (sum, c) => sum + c.monthlyLimit);

  // ── Saldo ───────────────────────────────────────────────────────────────

  int walletBalance(int walletId) {
    final w = _walletById[walletId];
    var bal = w?.initialBalance ?? 0;
    for (final t in _txns) {
      if (t.walletId == walletId) {
        bal += t.isIncome ? t.amount : -t.amount;
      }
      if (t.isTransfer && t.toWalletId == walletId) bal += t.amount;
    }
    return bal;
  }

  /// Total saldo semua dompet aktif.
  int get totalBalance => activeWallets.fold(0, (s, w) => s + walletBalance(w.id!));

  /// Total uang yang sudah masuk ke target tabungan tertentu.
  int goalSaved(int goalId) =>
      _txns.where((t) => t.goalId == goalId).fold(0, (s, t) => s + (t.isIncome ? -t.amount : t.amount));

  /// Total semua tabungan (setoran ke pos tabungan sepanjang waktu).
  int get totalSaved {
    final ids = savingCategoryIds;
    return _txns
        .where((t) => t.isExpense && ids.contains(t.categoryId))
        .fold(0, (s, t) => s + t.amount);
  }

  // ── Transaksi ───────────────────────────────────────────────────────────

  /// Simpan transaksi baru. Mengembalikan daftar peringatan anggaran yang
  /// baru terpicu (juga dikirim sebagai notifikasi kalau diaktifkan).
  Future<List<BudgetAlert>> addTxn(Txn t) async {
    final before = currentSummary;
    final id = await db.insertTxn(t);
    _insertSorted(t.copyWith(id: id));
    if (t.walletId != settings.lastWalletId) settings.lastWalletId = t.walletId;
    _changed();
    return _checkAlerts(before, t);
  }

  Future<List<BudgetAlert>> updateTxn(Txn t) async {
    final before = currentSummary;
    await db.updateTxn(t);
    _txns.removeWhere((x) => x.id == t.id);
    _insertSorted(t);
    _changed();
    return _checkAlerts(before, t);
  }

  /// Hapus transaksi. Langsung hilang dari daftar (supaya animasi geser-hapus
  /// mulus), lalu dihapus dari database.
  Future<Txn?> deleteTxn(int id) async {
    final t = _txns.where((x) => x.id == id).firstOrNull;
    if (t == null) return null;
    _txns.remove(t);
    _changed();
    await db.deleteTxn(id);
    return t;
  }

  /// Batalkan hapus (tombol "Urungkan").
  Future<void> restoreTxn(Txn t) async {
    await db.insertTxn(t);
    _insertSorted(t);
    _changed();
  }

  void _insertSorted(Txn t) {
    final i = _txns.indexWhere((x) =>
        x.date.isBefore(t.date) || (x.date == t.date && (x.id ?? 0) < (t.id ?? 0)));
    if (i < 0) {
      _txns.add(t);
    } else {
      _txns.insert(i, t);
    }
  }

  List<BudgetAlert> _checkAlerts(PeriodSummary before, Txn t) {
    if (!t.isExpense || !currentPeriod.contains(t.date)) return const [];
    final alerts = alertsAfterChange(
      before: before,
      after: currentSummary,
      categories: _categories,
      today: now,
      manualDailyLimit: settings.manualDailyLimit,
      fmt: rupiah,
    );
    if (settings.alertsEnabled) {
      for (final a in alerts) {
        notifier.showAlert(a);
      }
    }
    return alerts;
  }

  // ── Dompet ──────────────────────────────────────────────────────────────

  Future<int> saveWallet(Wallet w) async {
    int id;
    if (w.id == null) {
      id = await db.insertWallet(w.copyWith(sortOrder: _wallets.length));
    } else {
      await db.updateWallet(w);
      id = w.id!;
    }
    _wallets = await db.wallets();
    _reindex();
    _changed();
    return id;
  }

  /// Dompet yang sudah punya transaksi diarsipkan (bukan dihapus) supaya
  /// riwayat tetap utuh.
  Future<void> removeWallet(Wallet w) async {
    final used = _txns.any((t) => t.walletId == w.id || t.toWalletId == w.id) ||
        _recurrings.any((r) => r.walletId == w.id);
    if (used) {
      await db.updateWallet(w.copyWith(archived: true));
    } else {
      await db.deleteWallet(w.id!);
    }
    _wallets = await db.wallets();
    _reindex();
    _changed();
  }

  // ── Pos / kategori ──────────────────────────────────────────────────────

  Future<int> saveCategory(Pos c) async {
    int id;
    if (c.id == null) {
      id = await db.insertCategory(c.copyWith(sortOrder: _categories.length));
    } else {
      await db.updateCategory(c);
      id = c.id!;
    }
    _categories = await db.categories();
    _reindex();
    _changed();
    return id;
  }

  Future<void> removeCategory(Pos c) async {
    final used = _txns.any((t) => t.categoryId == c.id) ||
        _recurrings.any((r) => r.categoryId == c.id);
    if (used) {
      await db.updateCategory(c.copyWith(archived: true, monthlyLimit: 0));
    } else {
      await db.deleteCategory(c.id!);
    }
    _categories = await db.categories();
    _reindex();
    _changed();
  }

  Future<void> saveLimits(Map<int, int> limits) async {
    await db.updateLimits(limits);
    _categories = await db.categories();
    _reindex();
    _changed();
  }

  Future<void> reorderCategories(List<int> ids) async {
    await db.reorderCategories(ids);
    _categories = await db.categories();
    _reindex();
    _changed();
  }

  // ── Target tabungan ─────────────────────────────────────────────────────

  Future<void> saveGoal(Goal g) async {
    if (g.id == null) {
      await db.insertGoal(g);
    } else {
      await db.updateGoal(g);
    }
    _goals = await db.goals();
    _changed();
  }

  Future<void> deleteGoal(int id) async {
    await db.deleteGoal(id);
    _goals = await db.goals();
    _txns = await db.transactions();
    _changed();
  }

  // ── Transaksi rutin ─────────────────────────────────────────────────────

  /// Transaksi rutin mode "ingatkan saja" yang sudah jatuh tempo.
  List<Recurring> get pendingRecurring => _recurrings
      .where((r) => r.active && !r.autoRecord && !dateOnly(r.nextDate).isAfter(dateOnly(now)))
      .toList();

  /// Transaksi rutin aktif yang jatuh tempo dalam [days] hari ke depan.
  List<Recurring> upcomingRecurring({int days = 7}) {
    final limit = dateOnly(now).add(Duration(days: days));
    return _recurrings
        .where((r) => r.active && dateOnly(r.nextDate).isAfter(dateOnly(now)) && !r.nextDate.isAfter(limit))
        .toList();
  }

  Future<void> saveRecurring(Recurring r) async {
    if (r.id == null) {
      await db.insertRecurring(r);
    } else {
      await db.updateRecurring(r);
    }
    _recurrings = await db.recurrings();
    await processRecurring();
    _changed();
  }

  Future<void> deleteRecurring(int id) async {
    await db.deleteRecurring(id);
    _recurrings = await db.recurrings();
    _changed();
  }

  Future<int>? _processing;

  /// Catat otomatis semua transaksi rutin (mode otomatis) yang sudah jatuh tempo.
  /// Kalau sedang berjalan, pemanggilan berikutnya menunggu proses yang sama
  /// (mencegah transaksi ganda).
  Future<int> processRecurring() => _processing ??= _processRecurring().whenComplete(() => _processing = null);

  Future<int> _processRecurring() async {
    var created = 0;
    // Selalu baca ulang dari database supaya tanggal jatuh tempo terbaru.
    for (final r in await db.recurrings()) {
      if (!r.autoRecord) continue;
      final due = dueDates(r, now);
      if (due.isEmpty) continue;
      final txns = [
        for (final d in due)
          Txn(
            type: r.type,
            amount: r.amount,
            categoryId: r.categoryId,
            walletId: r.walletId,
            recurringId: r.id,
            date: DateTime(d.year, d.month, d.day, 8),
            note: r.title,
          ),
      ];
      // Transaksi + tanggal berikutnya disimpan dalam satu transaksi database.
      await db.postRecurring(r.copyWith(nextDate: nextDue(due.last, r.dayOfMonth)), txns);
      created += txns.length;
    }
    if (created > 0) {
      _recurrings = await db.recurrings();
      _txns = await db.transactions();
      _changed();
    }
    return created;
  }

  /// Konfirmasi tagihan rutin (mode "ingatkan saja") dengan nominal aktual.
  Future<List<BudgetAlert>> confirmRecurring(Recurring r, int amount) async {
    final alerts = await addTxn(Txn(
      type: r.type,
      amount: amount,
      categoryId: r.categoryId,
      walletId: r.walletId,
      recurringId: r.id,
      date: DateTime(now.year, now.month, now.day, now.hour, now.minute),
      note: r.title,
    ));
    await skipRecurring(r);
    return alerts;
  }

  /// Lewati jatuh tempo ini (maju ke bulan berikutnya).
  Future<void> skipRecurring(Recurring r) async {
    await db.updateRecurring(r.copyWith(nextDate: nextDue(r.nextDate, r.dayOfMonth)));
    _recurrings = await db.recurrings();
    _changed();
  }

  // ── Backup ──────────────────────────────────────────────────────────────

  static const backupFormat = 'fintrack-backup';

  Future<String> exportJson() async {
    final data = await db.dumpAll();
    return const JsonEncoder.withIndent(' ').convert({
      'format': backupFormat,
      'version': 1,
      'exported_at': now.toIso8601String(),
      'settings': {
        'payday': settings.payday,
        'estimated_income': settings.estimatedIncome,
        'manual_daily_limit': settings.manualDailyLimit,
      },
      'data': data,
    });
  }

  /// Pulihkan dari backup. Melempar [FormatException] kalau file tidak valid.
  Future<void> importJson(String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw const FormatException('File bukan backup FinTrack yang valid.');
    }
    if (decoded is! Map || decoded['format'] != backupFormat || decoded['data'] is! Map) {
      throw const FormatException('File bukan backup FinTrack yang valid.');
    }
    if (decoded['version'] != 1) {
      throw const FormatException('Versi backup tidak dikenali. Perbarui aplikasi terlebih dahulu.');
    }
    final raw = decoded['data'] as Map;
    for (final t in AppDatabase.tables) {
      if (raw[t] is! List) {
        throw FormatException('File backup tidak lengkap (bagian "$t" tidak ada).');
      }
    }
    final data = <String, List<Map<String, Object?>>>{
      for (final e in raw.entries)
        e.key as String: [
          for (final row in (e.value as List)) Map<String, Object?>.from(row as Map),
        ],
    };
    await db.replaceAll(data);
    final s = decoded['settings'];
    if (s is Map) {
      if (s['payday'] is int) settings.payday = s['payday'] as int;
      if (s['estimated_income'] is int) settings.estimatedIncome = s['estimated_income'] as int;
      if (s['manual_daily_limit'] is int) settings.manualDailyLimit = s['manual_daily_limit'] as int;
    }
    settings.onboarded = true;
    await load();
  }

  /// Hapus semua data & kembali ke onboarding (PIN dan tema tetap).
  Future<void> resetAll() async {
    await db.resetAll();
    settings.resetBudgetSettings();
    await load();
  }
}
