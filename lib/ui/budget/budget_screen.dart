// Tab "Pos": daftar pos anggaran & sumber pemasukan, bagi gaji, detail pos.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../logic/budget.dart';
import '../../state/finance_store.dart';
import '../../state/settings.dart';
import '../txn/txn_form.dart';
import '../txn/txn_tile.dart';
import '../widgets/common.dart';
import 'allocation_editor.dart';

void openPosDetail(BuildContext context, Pos c) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => PosDetailScreen(posId: c.id!)));

void openAllocate(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AllocateScreen()));

class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final settings = context.watch<Settings>();
    final statuses = store.currentStatuses;
    final summary = store.currentSummary;
    final allocated = store.totalAllocated;
    final income = summary.income > 0 ? summary.income : settings.estimatedIncome;

    final spending = statuses.where((s) => !s.category.isSaving).toList();
    final saving = statuses.where((s) => s.category.isSaving).toList();
    final totalLimit = spending.fold(0, (s, x) => s + x.limit);
    final totalSpent = spending.fold(0, (s, x) => s + x.spent);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pos Anggaran'),
        actions: [
          IconButton(
            tooltip: 'Tambah pos',
            onPressed: () => showPosEditor(context, kind: PosKind.expense),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Terpakai periode ini', style: context.text.bodySmall),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(child: Money(totalSpent, style: context.text.headlineSmall)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(totalLimit > 0 ? 'dari ${rupiah(totalLimit)}' : '',
                              style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Bar(
                    ratio: totalLimit > 0 ? totalSpent / totalLimit : 0,
                    color: levelColor(context, levelFor(totalSpent, totalLimit)),
                    height: 10,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          income > 0
                              ? 'Dialokasikan ${compactRupiah(allocated)} dari ${compactRupiah(income)}'
                              : 'Belum ada perkiraan gaji',
                          style: context.text.bodySmall,
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        onPressed: () => openAllocate(context),
                        icon: const Icon(Icons.pie_chart_rounded, size: 18),
                        label: const Text('Bagi Gaji'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (saving.isNotEmpty) ...[
            const SectionHeader('Tabungan'),
            for (final s in saving) _PosCard(status: s),
          ],
          const SectionHeader('Pengeluaran'),
          for (final s in spending) _PosCard(status: s),
          SectionHeader('Sumber pemasukan',
              action: 'Tambah', onAction: () => showPosEditor(context, kind: PosKind.income)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final c in store.incomeCategories)
                    ListTile(
                      leading: IconBadge(icon: c.icon, color: c.color, size: 36),
                      title: Text(c.name),
                      trailing: Money(summary.incomeByCategory[c.id] ?? 0,
                          color: context.palette.income,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => showPosEditor(context, kind: PosKind.income, edit: c),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PosCard extends StatelessWidget {
  const _PosCard({required this.status});
  final PosStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.category;
    final color = c.isSaving ? context.palette.saving : levelColor(context, status.level, normal: Color(c.color));
    final String info;
    if (c.isSaving) {
      info = status.limit > 0
          ? (status.spent >= status.limit
              ? 'Target setoran bulan ini tercapai 🎉'
              : 'Kurang ${rupiah(status.limit - status.spent)} dari target setoran')
          : 'Belum ada target setoran';
    } else if (status.limit <= 0) {
      info = 'Tanpa batas';
    } else if (status.remaining < 0) {
      info = 'Lewat ${rupiah(-status.remaining)}';
    } else {
      info = 'Sisa ${rupiah(status.remaining)} · ≈${compactRupiah(status.perDayLeft)}/hari';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AppCard(
        onTap: () => openPosDetail(context, c),
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                IconBadge(icon: c.icon, color: c.color, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: context.text.titleSmall),
                      const SizedBox(height: 2),
                      Text(info,
                          style: context.text.bodySmall?.copyWith(
                              color: status.level == BudgetLevel.over ? context.palette.expense : null)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Money(status.spent, style: context.text.titleSmall),
                    if (status.limit > 0)
                      Text('dari ${compactRupiah(status.limit)}', style: context.text.bodySmall),
                  ],
                ),
              ],
            ),
            if (status.limit > 0) ...[
              const SizedBox(height: 12),
              Bar(ratio: status.ratio, color: color, height: 7),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Detail pos ─────────────────────────────────────────────────────────────

class PosDetailScreen extends StatelessWidget {
  const PosDetailScreen({super.key, required this.posId});
  final int posId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final c = store.category(posId);
    if (c == null) return const Scaffold();
    final period = store.currentPeriod;
    final txns = store.transactions.where((t) => t.categoryId == posId && period.contains(t.date)).toList();
    final status = store.currentStatuses.where((s) => s.category.id == posId).firstOrNull;
    final total = c.isExpense ? (status?.spent ?? 0) : (store.currentSummary.incomeByCategory[posId] ?? 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Ubah pos',
            onPressed: () => showPosEditor(context, kind: c.kind, edit: c),
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTxnForm(context,
            type: c.isExpense ? TxnType.expense : TxnType.income, categoryId: c.id),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Catat'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    IconBadge(icon: c.icon, color: c.color, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fmtPeriod(period), style: context.text.bodySmall),
                          Money(total, style: context.text.headlineSmall),
                        ],
                      ),
                    ),
                  ]),
                  if (status != null && status.limit > 0) ...[
                    const SizedBox(height: 16),
                    Bar(
                      ratio: status.ratio,
                      color: c.isSaving ? context.palette.saving : levelColor(context, status.level),
                      height: 10,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _Fig(label: c.isSaving ? 'Target setoran' : 'Batas', value: status.limit)),
                        Expanded(
                            child: _Fig(
                                label: status.remaining >= 0 ? 'Sisa' : 'Kelebihan', value: status.remaining.abs())),
                        if (!c.isSaving)
                          Expanded(child: _Fig(label: 'Jatah/hari', value: status.perDayLeft)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (txns.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'Belum ada transaksi di pos ini',
              message: 'Transaksi periode ini akan tampil di sini.',
            )
          else
            for (final t in txns) DismissibleTxnTile(t, showDate: true),
        ],
      ),
    );
  }
}

class _Fig extends StatelessWidget {
  const _Fig({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.bodySmall),
          Money(value, compact: true, style: context.text.titleSmall),
        ],
      );
}

// ── Editor pos ─────────────────────────────────────────────────────────────

Future<void> showPosEditor(BuildContext context, {required PosKind kind, Pos? edit}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PosEditor(kind: kind, edit: edit),
  );
}

class _PosEditor extends StatefulWidget {
  const _PosEditor({required this.kind, this.edit});
  final PosKind kind;
  final Pos? edit;

  @override
  State<_PosEditor> createState() => _PosEditorState();
}

class _PosEditorState extends State<_PosEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _limit;
  late String _icon;
  late int _color;
  late bool _saving;

  bool get _isExpense => widget.kind == PosKind.expense;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _name = TextEditingController(text: e?.name ?? '');
    _limit = TextEditingController(text: (e?.monthlyLimit ?? 0) > 0 ? groupDigits(e!.monthlyLimit) : '');
    _icon = e?.icon ?? 'category';
    _color = e?.color ?? 0xFF10B981;
    _saving = e?.isSaving ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final store = context.read<FinanceStore>();
    final base = widget.edit ?? Pos(name: '', kind: widget.kind);
    await store.saveCategory(base.copyWith(
      name: _name.text.trim(),
      icon: _icon,
      color: _color,
      monthlyLimit: _isExpense ? parseDigits(_limit.text) : 0,
      isSaving: _isExpense && _saving,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final store = context.read<FinanceStore>();
    final nav = Navigator.of(context);
    final ok = await confirm(
      context,
      title: 'Hapus "${widget.edit!.name}"?',
      message: 'Transaksi lama di pos ini tetap tersimpan di riwayat.',
      ok: 'Hapus',
      destructive: true,
    );
    if (!ok) return;
    await store.removeCategory(widget.edit!);
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBadge(icon: _icon, color: _color, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.edit == null
                            ? (_isExpense ? 'Pos baru' : 'Sumber pemasukan baru')
                            : 'Ubah ${_isExpense ? 'pos' : 'sumber'}',
                        style: context.text.titleLarge,
                      ),
                    ),
                    if (widget.edit != null)
                      IconButton(
                        tooltip: 'Hapus',
                        onPressed: _delete,
                        icon: Icon(Icons.delete_outline_rounded, color: context.palette.expense),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Isi nama' : null,
                ),
                if (_isExpense) ...[
                  const SizedBox(height: 12),
                  MoneyField(
                    controller: _limit,
                    label: _saving ? 'Target setoran per periode' : 'Batas per periode (kosongkan = tanpa batas)',
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ini pos tabungan'),
                    subtitle: const Text('Uangnya disisihkan, tidak dihitung sebagai pengeluaran'),
                    value: _saving,
                    onChanged: (v) => setState(() => _saving = v),
                  ),
                ],
                const SizedBox(height: 12),
                Text('Warna', style: context.text.labelLarge),
                const SizedBox(height: 8),
                ColorChooser(value: _color, onChanged: (c) => setState(() => _color = c)),
                const SizedBox(height: 16),
                Text('Ikon', style: context.text.labelLarge),
                const SizedBox(height: 8),
                IconChooser(value: _icon, color: _color, onChanged: (i) => setState(() => _icon = i)),
                const SizedBox(height: 20),
                FilledButton(onPressed: _save, child: const Text('Simpan')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bagi gaji ──────────────────────────────────────────────────────────────

class AllocateScreen extends StatefulWidget {
  const AllocateScreen({super.key});

  @override
  State<AllocateScreen> createState() => _AllocateScreenState();
}

class _AllocateScreenState extends State<AllocateScreen> {
  late int _income;
  late Map<int, int> _limits;
  late List<Pos> _cats;

  @override
  void initState() {
    super.initState();
    final store = context.read<FinanceStore>();
    final settings = context.read<Settings>();
    _cats = store.expenseCategories;
    _limits = {for (final c in _cats) c.id!: c.monthlyLimit};
    final inc = store.currentSummary.income;
    _income = settings.estimatedIncome > 0 ? settings.estimatedIncome : inc;
  }

  Future<void> _save() async {
    final store = context.read<FinanceStore>();
    context.read<Settings>().estimatedIncome = _income;
    await store.saveLimits(_limits);
    if (mounted) {
      Navigator.pop(context);
      toast(context, 'Pembagian gaji disimpan ✓');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bagi Gaji')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Tentukan jatah tiap pos untuk satu periode gajian. Sisihkan tabungan di awal, '
              'baru sisanya untuk kebutuhan.',
              style: context.text.bodyMedium?.copyWith(color: context.palette.muted),
            ),
          ),
          Expanded(
            child: AllocationEditor(
              categories: _cats,
              income: _income,
              limits: _limits,
              onChanged: (inc, limits) {
                _income = inc;
                _limits = limits;
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: FilledButton(onPressed: _save, child: const Text('Simpan pembagian')),
        ),
      ),
    );
  }
}
