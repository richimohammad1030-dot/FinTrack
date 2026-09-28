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
}) async {
  final alerts = await Navigator.of(context).push<List<BudgetAlert>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TxnFormPage(
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
  });

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
