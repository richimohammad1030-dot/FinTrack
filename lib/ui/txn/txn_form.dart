// Form catat / ubah transaksi. Dirancang supaya cepat: nominal → pos → simpan.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../logic/budget.dart';
import '../../state/finance_store.dart';
import '../../state/settings.dart';
import '../../logic/period.dart';
import '../../logic/receipt_parser.dart';
import '../../services/receipt_scanner.dart';
import '../widgets/common.dart';

/// Buka form transaksi. Setelah disimpan, peringatan anggaran (jika ada)
/// ditampilkan otomatis.
Future<void> openTxnForm(
  BuildContext context, {
  Txn? edit,
  TxnType type = TxnType.expense,
  int? categoryId,
  int? goalId,
  int? amount,
  bool scan = false,
}) async {
  final alerts = await Navigator.of(context).push<List<BudgetAlert>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TxnFormPage(
        startScan: scan,
        edit: edit,
        initialType: type,
        initialCategoryId: categoryId,
        initialGoalId: goalId,
        initialAmount: amount,
      ),
    ),
  );
  if (!context.mounted || alerts == null) return;
  if (alerts.isEmpty) {
    toast(context, edit == null ? 'Tersimpan ✓' : 'Perubahan disimpan ✓');
  } else {
    await showAlertsSheet(context, alerts);
  }
}

Future<void> showAlertsSheet(BuildContext context, List<BudgetAlert> alerts) {
  return showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tersimpan, tapi perhatikan ini', style: ctx.text.titleLarge),
            const SizedBox(height: 16),
            for (final a in alerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: levelColor(ctx, a.level).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        a.level == BudgetLevel.over ? Icons.error_rounded : Icons.warning_amber_rounded,
                        color: levelColor(ctx, a.level),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.title, style: ctx.text.titleSmall),
                            const SizedBox(height: 2),
                            Text(a.message, style: ctx.text.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Oke, mengerti')),
          ],
        ),
      ),
    ),
  );
}

class TxnFormPage extends StatefulWidget {
  const TxnFormPage({
    super.key,
    this.edit,
    this.initialType = TxnType.expense,
    this.initialCategoryId,
    this.initialGoalId,
    this.initialAmount,
    this.startScan = false,
  });

  /// Langsung buka pemindai struk saat form dibuka.
  final bool startScan;
  final Txn? edit;
  final TxnType initialType;
  final int? initialCategoryId;
  final int? initialGoalId;
  final int? initialAmount;

  @override
  State<TxnFormPage> createState() => _TxnFormPageState();
}

class _TxnFormPageState extends State<TxnFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late TxnType _type;
  int? _categoryId;
  int? _walletId;
  int? _toWalletId;
  int? _goalId;
  late DateTime _date;
  bool _saving = false;
  bool _scanning = false;

  /// Keterangan hasil scan terakhir (ditampilkan sebagai banner).
  String? _scanInfo;
  bool _scanConfident = true;

  FinanceStore get _store => context.read<FinanceStore>();

  @override
  void initState() {
    super.initState();
    final store = context.read<FinanceStore>();
    final settings = context.read<Settings>();
    final e = widget.edit;
    final wallets = store.activeWallets;
    int? defaultWallet() {
      final last = settings.lastWalletId;
      if (last != null && wallets.any((w) => w.id == last)) return last;
      return wallets.firstOrNull?.id;
    }

    if (e != null) {
      _type = e.type;
      _amount.text = groupDigits(e.amount);
      _note.text = e.note;
      _categoryId = e.categoryId;
      _walletId = e.walletId;
      _toWalletId = e.toWalletId;
      _goalId = e.goalId;
      _date = e.date;
    } else {
      _type = widget.initialType;
      if (widget.initialAmount != null) _amount.text = groupDigits(widget.initialAmount!);
      _categoryId = widget.initialCategoryId;
      _goalId = widget.initialGoalId;
      _walletId = defaultWallet();
      _toWalletId = wallets.where((w) => w.id != _walletId).firstOrNull?.id;
      _date = store.now;
    }
    if (widget.startScan && e == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    final source = await showModalBottomSheet<ScanSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text('Scan struk', style: ctx.text.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Foto struk lurus dari atas, cukup terang, dan seluruh bagian TOTAL terlihat.',
                  style: ctx.text.bodySmall),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Ambil foto'),
              onTap: () => Navigator.pop(ctx, ScanSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.pop(ctx, ScanSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _scanning = true);
    ScanOutcome? out;
    try {
      out = await const ReceiptScanner().scan(source);
    } catch (e) {
      if (mounted) toast(context, 'Gagal membaca struk. Coba foto ulang dengan cahaya lebih terang.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
    if (out == null || !mounted) return;
    ReceiptScanner.discard(out.imagePath);
    _applyScan(out.result);
  }

  void _applyScan(ReceiptResult r) {
    if (r.isEmpty || r.total == null) {
      toast(context, 'Nominal tidak terbaca. Isi manual ya.');
      if (r.isEmpty) return;
    }
    setState(() {
      if (_type != TxnType.expense) {
        _type = TxnType.expense;
        if (!_store.expenseCategories.any((c) => c.id == _categoryId)) _categoryId = null;
        _goalId = null;
      }
      if (r.total != null) _amount.text = groupDigits(r.total!);
      if (r.merchant != null && _note.text.trim().isEmpty) _note.text = r.merchant!;
      if (r.date != null) {
        final n = _store.now;
        _date = DateTime(r.date!.year, r.date!.month, r.date!.day,
            dateOnly(r.date!) == dateOnly(n) ? n.hour : 12, dateOnly(r.date!) == dateOnly(n) ? n.minute : 0);
      }
      if (r.categoryName != null) {
        final c = _store.expenseCategories.where((c) => c.name == r.categoryName).firstOrNull;
        if (c != null) _categoryId = c.id;
      }
      _scanConfident = r.confident;
      _scanInfo = [
        if (r.merchant != null) r.merchant!,
        if (r.total != null) rupiah(r.total!),
        if (r.date != null) fmtDate(r.date!),
      ].join(' · ');
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  List<Pos> get _cats =>
      _type == TxnType.income ? _store.incomeCategories : _store.expenseCategories;

  void _setType(TxnType t) {
    setState(() {
      _type = t;
      if (!_cats.any((c) => c.id == _categoryId)) _categoryId = null;
      if (t == TxnType.transfer && _toWalletId == _walletId) {
        _toWalletId = _store.activeWallets.where((w) => w.id != _walletId).firstOrNull?.id;
      }
      _goalId = null;
    });
  }

  Future<void> _pickDate() async {
    final now = _store.now;
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, 12));
  }

  void _setDay(int daysAgo) {
    final n = _store.now;
    setState(() {
      _date = daysAgo == 0 ? n : DateTime(n.year, n.month, n.day - daysAgo, 12);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    String? problem;
    if (_walletId == null) problem = 'Pilih dompet dulu';
    if (_type != TxnType.transfer && _categoryId == null) {
      problem = _type == TxnType.income ? 'Pilih sumber pemasukan' : 'Pilih pos pengeluaran';
    }
    if (_type == TxnType.transfer && (_toWalletId == null || _toWalletId == _walletId)) {
      problem = 'Pilih dompet tujuan yang berbeda';
    }
    if (problem != null) {
      toast(context, problem);
      return;
    }
    setState(() => _saving = true);
    final cat = _store.category(_categoryId);
    final t = Txn(
      id: widget.edit?.id,
      type: _type,
      amount: parseDigits(_amount.text),
      categoryId: _type == TxnType.transfer ? null : _categoryId,
      walletId: _walletId!,
      toWalletId: _type == TxnType.transfer ? _toWalletId : null,
      goalId: (cat?.isSaving ?? false) && _type == TxnType.expense ? _goalId : null,
      recurringId: widget.edit?.recurringId,
      date: _date,
      note: _note.text.trim(),
      createdAt: widget.edit?.createdAt,
    );
    final alerts = widget.edit == null ? await _store.addTxn(t) : await _store.updateTxn(t);
    if (mounted) Navigator.pop(context, alerts);
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'Hapus transaksi ini?', ok: 'Hapus', destructive: true);
    if (!ok || !mounted) return;
    await _store.deleteTxn(widget.edit!.id!);
    if (mounted) {
      Navigator.pop(context);
      toast(context, 'Transaksi dihapus');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final wallets = store.activeWallets;
    final selected = store.category(_categoryId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.edit == null ? 'Catat Transaksi' : 'Ubah Transaksi'),
        actions: [
          if (widget.edit == null)
            IconButton(
              tooltip: 'Scan struk',
              onPressed: _scanning ? null : _scan,
              icon: const Icon(Icons.document_scanner_rounded),
            ),
          if (widget.edit != null)
            IconButton(
              tooltip: 'Hapus',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            SegmentedButton<TxnType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TxnType.expense, label: Text('Keluar'), icon: Icon(Icons.north_east_rounded)),
                ButtonSegment(value: TxnType.income, label: Text('Masuk'), icon: Icon(Icons.south_west_rounded)),
                ButtonSegment(value: TxnType.transfer, label: Text('Transfer'), icon: Icon(Icons.swap_horiz_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => _setType(s.first),
            ),
            if (widget.edit == null && _type == TxnType.expense) ...[
              const SizedBox(height: 12),
              _ScanBanner(
                scanning: _scanning,
                info: _scanInfo,
                confident: _scanConfident,
                onScan: _scan,
              ),
            ],
            const SizedBox(height: 20),
            MoneyField(
              controller: _amount,
              large: true,
              autofocus: widget.edit == null && widget.initialAmount == null,
              validator: requiredAmount,
              textInputAction: TextInputAction.done,
            ),
            if (_type != TxnType.transfer) ...[
              _Label(_type == TxnType.income ? 'Sumber pemasukan' : 'Pos pengeluaran'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _cats)
                    ChoiceChip(
                      avatar: Icon(iconFor(c.icon), size: 18, color: Color(c.color)),
                      label: Text(c.name),
                      selected: _categoryId == c.id,
                      onSelected: (_) => setState(() {
                        _categoryId = c.id;
                        if (!c.isSaving) _goalId = null;
                      }),
                    ),
                ],
              ),
              if (selected != null && selected.isExpense && !selected.isSaving)
                _PosHint(pos: selected, editing: widget.edit),
              if (selected != null && selected.isSaving && store.activeGoals.isNotEmpty) ...[
                const _Label('Untuk target tabungan'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Umum'),
                      selected: _goalId == null,
                      onSelected: (_) => setState(() => _goalId = null),
                    ),
                    for (final g in store.activeGoals)
                      ChoiceChip(
                        avatar: Icon(iconFor(g.icon), size: 18, color: Color(g.color)),
                        label: Text(g.name),
                        selected: _goalId == g.id,
                        onSelected: (_) => setState(() => _goalId = g.id),
                      ),
                  ],
                ),
              ],
            ],
            _Label(_type == TxnType.transfer ? 'Dari dompet' : 'Dompet'),
            _WalletChips(
              wallets: wallets,
              value: _walletId,
              onChanged: (id) => setState(() => _walletId = id),
            ),
            if (_type == TxnType.transfer) ...[
              const _Label('Ke dompet'),
              _WalletChips(
                wallets: wallets.where((w) => w.id != _walletId).toList(),
                value: _toWalletId,
                onChanged: (id) => setState(() => _toWalletId = id),
              ),
            ],
            const _Label('Tanggal'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Hari ini'),
                  selected: fmtRelativeDay(_date, now: store.now) == 'Hari ini',
                  onSelected: (_) => _setDay(0),
                ),
                ChoiceChip(
                  label: const Text('Kemarin'),
                  selected: fmtRelativeDay(_date, now: store.now) == 'Kemarin',
                  onSelected: (_) => _setDay(1),
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(fmtDate(_date)),
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: 'mis. makan siang, bensin, token listrik',
                prefixIcon: Icon(Icons.edit_note_rounded),
                counterText: '',
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(widget.edit == null ? 'Simpan' : 'Simpan perubahan'),
          ),
        ),
      ),
    );
  }
}

class _ScanBanner extends StatelessWidget {
  const _ScanBanner({required this.scanning, required this.info, required this.confident, required this.onScan});
  final bool scanning;
  final String? info;
  final bool confident;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasResult = info != null;
    final color = hasResult && !confident ? context.palette.warning : c.primary;
    return Material(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: scanning ? null : onScan,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (scanning)
                SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: color))
              else
                Icon(hasResult ? (confident ? Icons.check_circle_rounded : Icons.help_rounded) : Icons.document_scanner_rounded,
                    color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scanning
                          ? 'Membaca struk…'
                          : hasResult
                              ? (confident ? 'Hasil scan — cek lagi sebelum simpan' : 'Total ditebak — mohon dicek')
                              : 'Malas ngetik? Scan struk',
                      style: context.text.titleSmall,
                    ),
                    Text(
                      hasResult && !scanning ? info! : 'Nominal, tanggal, dan toko terisi otomatis',
                      style: context.text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!scanning) Icon(hasResult ? Icons.refresh_rounded : Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text, style: context.text.labelLarge?.copyWith(color: context.palette.muted)),
      );
}

class _WalletChips extends StatelessWidget {
  const _WalletChips({required this.wallets, required this.value, required this.onChanged});

  final List<Wallet> wallets;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (wallets.isEmpty) {
      return Text('Belum ada dompet lain. Tambahkan di menu Lainnya → Dompet.',
          style: context.text.bodySmall);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final w in wallets)
          ChoiceChip(
            avatar: Icon(iconFor(w.icon), size: 18, color: Color(w.color)),
            label: Text(w.name),
            selected: value == w.id,
            onSelected: (_) => onChanged(w.id!),
          ),
      ],
    );
  }
}

/// Info sisa pos yang dipilih, supaya sadar sebelum menyimpan.
class _PosHint extends StatelessWidget {
  const _PosHint({required this.pos, this.editing});

  final Pos pos;
  final Txn? editing;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    if (!pos.hasLimit) return const SizedBox.shrink();
    final status = store.currentStatuses.where((s) => s.category.id == pos.id).firstOrNull;
    if (status == null) return const SizedBox.shrink();
    final color = levelColor(context, status.level);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    status.remaining >= 0
                        ? 'Sisa pos ${pos.name}: ${rupiah(status.remaining)}'
                        : 'Pos ${pos.name} sudah lewat ${rupiah(-status.remaining)}',
                    style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(percent(status.ratio), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Bar(ratio: status.ratio, color: color, height: 6),
            if (status.perDayLeft > 0) ...[
              const SizedBox(height: 6),
              Text('≈ ${rupiah(status.perDayLeft)}/hari sampai gajian', style: context.text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
