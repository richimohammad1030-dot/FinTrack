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
  List<Debt> _debts = [];
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
  List<Debt> get debts => _debts;
  Debt? debt(int? id) => id == null ? null : _debts.where((d) => d.id == id).firstOrNull;

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
    syncDebtReminders();
  }

  Future<void> _reloadAll() async {
    _wallets = await db.wallets();
    _categories = await db.categories();
    _goals = await db.goals();
    _recurrings = await db.recurrings();
    _debts = await db.debts();
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
        bal += t.type.isInflow ? t.amount : -t.amount;
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
    if (t.debtId != null) await _afterDebtChange(t.debtId!);
    return t;
  }

  /// Batalkan hapus (tombol "Urungkan").
  Future<void> restoreTxn(Txn t) async {
    await db.insertTxn(t);
    _insertSorted(t);
    _changed();
    if (t.debtId != null) await _afterDebtChange(t.debtId!);
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
    var touchedDebt = false;
    // Selalu baca ulang dari database supaya tanggal jatuh tempo terbaru.
    for (final r in await db.recurrings()) {
      if (!r.autoRecord) continue;
      final due = dueDates(r, now);
      if (due.isEmpty) continue;
      final txns = <Txn>[];
      var stillActive = true;
      // Cicilan hutang: jangan melebihi sisa, dan berhenti otomatis saat lunas.
      var left = -1;
      if (r.debtId != null) {
        final d = debt(r.debtId) ?? (await db.debts()).where((x) => x.id == r.debtId).firstOrNull;
        final st = d == null ? null : debtStatus(d);
        left = st == null || st.settled ? 0 : (st.remaining < 0 ? 0 : st.remaining);
        touchedDebt = true;
      }
      for (final d in due) {
        var amount = r.amount;
        if (left >= 0) {
          if (left <= 0) {
            stillActive = false;
            break;
          }
          if (amount > left) amount = left;
          left -= amount;
        }
        txns.add(Txn(
          type: r.type,
          amount: amount,
          categoryId: r.categoryId,
          walletId: r.walletId,
          recurringId: r.id,
          debtId: r.debtId,
          date: DateTime(d.year, d.month, d.day, 8),
          note: r.title,
        ));
      }
      if (left == 0) stillActive = false;
      final next = txns.isEmpty ? r.nextDate : nextDue(due[txns.length - 1], r.dayOfMonth);
      // Transaksi + tanggal berikutnya disimpan dalam satu transaksi database.
      await db.postRecurring(r.copyWith(nextDate: next, active: stillActive), txns);
      created += txns.length;
    }
    if (created > 0 || touchedDebt) {
      _recurrings = await db.recurrings();
      _txns = await db.transactions();
      _changed();
    }
    return created;
  }

  /// Konfirmasi tagihan rutin (mode "ingatkan saja") dengan nominal aktual.
  Future<List<BudgetAlert>> confirmRecurring(Recurring r, int amount) async {
    final d = debt(r.debtId);
    if (d != null) {
      final left = debtStatus(d).remaining;
      if (left <= 0) {
        await skipRecurring(r);
        await _afterDebtChange(d.id!);
        return const [];
      }
      if (amount > left) amount = left;
    }
    final alerts = await addTxn(Txn(
      type: r.type,
      amount: amount,
      categoryId: r.categoryId,
      walletId: r.walletId,
      recurringId: r.id,
      debtId: r.debtId,
      date: DateTime(now.year, now.month, now.day, now.hour, now.minute),
      note: r.title,
    ));
    await skipRecurring(r);
    if (r.debtId != null) await _afterDebtChange(r.debtId!);
    return alerts;
  }

  /// Lewati jatuh tempo ini (maju ke bulan berikutnya).
  Future<void> skipRecurring(Recurring r) async {
    await db.updateRecurring(r.copyWith(nextDate: nextDue(r.nextDate, r.dayOfMonth)));
    _recurrings = await db.recurrings();
    _changed();
  }

  // ── Hutang & piutang ────────────────────────────────────────────────────

  DebtStatus debtStatus(Debt d) {
    var total = d.principal, paid = 0;
    DateTime? last;
    for (final t in _txns) {
      if (t.debtId != d.id) continue;
      if (t.type == d.increaseType) {
        total += t.amount;
      } else if (t.type == d.decreaseType) {
        paid += t.amount;
        if (last == null || t.date.isAfter(last)) last = t.date;
      }
    }
    return DebtStatus(d, total, paid, last);
  }

  List<DebtStatus> get debtStatuses {
    final list = [for (final d in _debts) debtStatus(d)];
    int rank(DebtStatus s) => s.settled ? 1 : 0;
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final da = a.debt.dueDate, dbb = b.debt.dueDate;
      if (da != null && dbb != null) return da.compareTo(dbb);
      if (da != null) return -1;
      if (dbb != null) return 1;
      return b.remaining.compareTo(a.remaining);
    });
    return list;
  }

  List<DebtStatus> get activeDebts => debtStatuses.where((s) => !s.settled).toList();

  /// Total sisa hutang saya (aktif).
  int get totalPayable =>
      activeDebts.where((s) => s.debt.isPayable).fold(0, (a, s) => a + s.remaining);

  /// Total sisa piutang (orang berhutang ke saya).
  int get totalReceivable =>
      activeDebts.where((s) => !s.debt.isPayable).fold(0, (a, s) => a + s.remaining);

  /// Hutang/piutang yang jatuh tempo dalam [days] hari atau sudah lewat.
  List<DebtStatus> dueSoonDebts({int days = 7}) {
    final limit = dateOnly(now).add(Duration(days: days));
    return activeDebts.where((s) => s.debt.dueDate != null && !dateOnly(s.debt.dueDate!).isAfter(limit)).toList();
  }

  List<Txn> debtTxns(int debtId) => _txns.where((t) => t.debtId == debtId).toList();

  List<Recurring> debtRecurrings(int debtId) => _recurrings.where((r) => r.debtId == debtId).toList();

  /// Catat hutang/piutang baru. Kalau [walletId] diisi, uangnya ikut
  /// masuk/keluar dompet (mis. pinjam uang tunai). Kalau tidak, jumlahnya
  /// dicatat sebagai hutang lama tanpa mengubah saldo.
  Future<int> createDebt(Debt d, {required int amount, int? walletId}) async {
    final id = await db.insertDebt(Debt(
      kind: d.kind,
      name: d.name,
      principal: walletId == null ? amount : 0,
      startDate: d.startDate,
      dueDate: d.dueDate,
      note: d.note,
    ));
    if (walletId != null && amount > 0) {
      await db.insertTxn(Txn(
        type: d.increaseType,
        amount: amount,
        walletId: walletId,
        debtId: id,
        date: d.startDate,
        note: d.note,
      ));
    }
    _debts = await db.debts();
    _txns = await db.transactions();
    _changed();
    syncDebtReminders();
    return id;
  }

  Future<void> updateDebt(Debt d) async {
    await db.updateDebt(d);
    _debts = await db.debts();
    _changed();
    await _afterDebtChange(d.id!);
  }

  /// Hapus hutang beserta semua pembayaran & cicilan rutinnya.
  Future<void> deleteDebt(int id) async {
    await notifier.cancel(_debtReminderId(id, 0));
    await notifier.cancel(_debtReminderId(id, 1));
    await db.deleteDebt(id);
    _debts = await db.debts();
    _txns = await db.transactions();
    _recurrings = await db.recurrings();
    _changed();
  }

  /// Catat pembayaran (mengurangi) atau tambahan pinjaman (menambah).
  Future<void> recordDebtTxn(
    Debt d, {
    required int amount,
    required int walletId,
    required DateTime date,
    String note = '',
    bool increase = false,
    Txn? edit,
  }) async {
    final t = Txn(
      id: edit?.id,
      type: increase ? d.increaseType : d.decreaseType,
      amount: amount,
      walletId: walletId,
      debtId: d.id,
      recurringId: edit?.recurringId,
      date: date,
      note: note,
      createdAt: edit?.createdAt,
    );
    if (edit == null) {
      await addTxn(t);
    } else {
      await updateTxn(t);
    }
    await _afterDebtChange(d.id!);
  }

  Future<void> setDebtClosed(Debt d, bool closed) => updateDebt(d.copyWith(closed: closed));

  /// Buat cicilan bulanan otomatis/diingatkan untuk hutang/piutang.
  Future<void> saveDebtInstallment(Debt d, Recurring r) =>
      saveRecurring(r.copyWith(type: d.decreaseType, categoryId: null));

  /// Setelah lunas: matikan cicilan rutin & pengingat.
  Future<void> _afterDebtChange(int debtId) async {
    final d = debt(debtId);
    if (d == null) return;
    if (debtStatus(d).settled) {
      for (final r in debtRecurrings(debtId).where((r) => r.active)) {
        await db.updateRecurring(r.copyWith(active: false));
      }
      _recurrings = await db.recurrings();
      _changed();
    }
    syncDebtReminders();
  }

  static int _debtReminderId(int debtId, int which) => 5000 + debtId * 2 + which;

  /// Jadwalkan pengingat H-3 dan hari-H (jam 09.00) untuk semua hutang aktif.
  /// ID yang pernah dijadwalkan disimpan, supaya pengingat hutang yang sudah
  /// dihapus/di-reset juga ikut dibatalkan.
  Future<void> syncDebtReminders() async {
    for (final id in settings.debtReminderIds) {
      await notifier.cancel(id);
    }
    final scheduled = <int>[];
    if (settings.alertsEnabled) {
      for (final d in _debts) {
        final st = debtStatus(d);
        final due = d.dueDate;
        if (st.settled || due == null) continue;
        final who = d.isPayable ? 'Hutang ke ${d.name}' : 'Piutang dari ${d.name}';
        final dueDay = DateTime(due.year, due.month, due.day, 9);
        final before = DateTime(due.year, due.month, due.day - 3, 9);
        if (before.isAfter(now)) {
          final id = _debtReminderId(d.id!, 0);
          await notifier.scheduleOnce(id, before, '$who jatuh tempo 3 hari lagi',
              'Sisa ${rupiah(st.remaining)} · jatuh tempo ${fmtDate(due)}');
          scheduled.add(id);
        }
        if (dueDay.isAfter(now)) {
          final id = _debtReminderId(d.id!, 1);
          await notifier.scheduleOnce(id, dueDay, '$who jatuh tempo hari ini',
              'Sisa ${rupiah(st.remaining)}. Jangan lupa ${d.isPayable ? 'dibayar' : 'ditagih'} ya.');
          scheduled.add(id);
        }
      }
    }
    settings.debtReminderIds = scheduled;
  }

  // ── Backup ──────────────────────────────────────────────────────────────

  static const backupFormat = 'kait-backup';
  static const _legacyFormat = 'fintrack-backup';

  Future<String> exportJson() async {
    final data = await db.dumpAll();
    return const JsonEncoder.withIndent(' ').convert({
      'format': backupFormat,
      'version': 2,
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
      throw const FormatException('File bukan backup KAIT yang valid.');
    }
    if (decoded is! Map ||
        (decoded['format'] != backupFormat && decoded['format'] != _legacyFormat) ||
        decoded['data'] is! Map) {
      throw const FormatException('File bukan backup KAIT yang valid.');
    }
    final version = decoded['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('Versi backup tidak dikenali. Perbarui aplikasi terlebih dahulu.');
    }
    final raw = decoded['data'] as Map;
    // Backup versi 1 belum punya tabel hutang.
    for (final t in AppDatabase.tables.where((t) => version == 2 || t != 'debts')) {
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
