// Transaksi rutin bulanan: kos, internet, cicilan, gaji, dll.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../logic/period.dart';
import '../../logic/recurring.dart';
import '../../state/finance_store.dart';
import '../debt/debt_screen.dart';
import '../widgets/common.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final items = store.recurrings;
    final monthlyOut = items
        .where((r) => r.active && (r.type == TxnType.expense || r.type == TxnType.debtOut))
        .fold(0, (s, r) => s + r.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('Transaksi Rutin')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showRecurringEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah'),
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.event_repeat_rounded,
              title: 'Belum ada transaksi rutin',
              message: 'Tambahkan tagihan bulanan seperti kos, internet, BPJS, atau cicilan. '
                  'KAIT akan mencatatnya otomatis (atau mengingatkanmu) setiap jatuh tempo.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pengeluaran tetap per bulan', style: context.text.bodySmall),
                            Money(monthlyOut, style: context.text.titleLarge),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final r in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RecurringCard(r: r),
                  ),
              ],
            ),
    );
  }
}

class _RecurringCard extends StatelessWidget {
  const _RecurringCard({required this.r});
  final Recurring r;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final cat = store.category(r.categoryId);
    final wallet = store.wallet(r.walletId);
    final debt = store.debt(r.debtId);
    final isIncome = r.type.isInflow;
    return Opacity(
      opacity: r.active ? 1 : 0.5,
      child: AppCard(
        onTap: () => debt != null
            ? showInstallmentEditor(context, debt, edit: r)
            : showRecurringEditor(context, edit: r),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconBadge(
                icon: debt != null ? 'loan' : (cat?.icon ?? 'receipt'),
                color: debt != null ? debtColor(context, debt.kind).toARGB32() : (cat?.color ?? 0xFF64748B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    [
                      'Tiap tgl ${r.dayOfMonth}',
                      if (r.active) 'berikutnya ${fmtDayMonth(r.nextDate)}' else 'nonaktif',
                      wallet?.name ?? '',
                    ].join(' · '),
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Pill(r.autoRecord ? 'Otomatis dicatat' : 'Diingatkan',
                      color: r.autoRecord ? context.colors.primary : context.palette.warning,
                      icon: r.autoRecord ? Icons.bolt_rounded : Icons.notifications_rounded),
                ],
              ),
            ),
            Money(isIncome ? r.amount : -r.amount,
                signed: true,
                color: isIncome ? context.palette.income : null,
                style: context.text.titleSmall),
          ],
        ),
      ),
    );
  }
}

Future<void> showRecurringEditor(BuildContext context, {Recurring? edit}) {
  final store = context.read<FinanceStore>();
  if (store.activeWallets.isEmpty) {
    toast(context, 'Tambahkan dompet dulu');
    return Future.value();
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecurringEditor(edit: edit),
  );
}

class _RecurringEditor extends StatefulWidget {
  const _RecurringEditor({this.edit});
  final Recurring? edit;

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late TxnType _type;
  int? _categoryId;
  late int _walletId;
  late int _day;
  late bool _auto;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final store = context.read<FinanceStore>();
    final e = widget.edit;
    _title = TextEditingController(text: e?.title ?? '');
    _amount = TextEditingController(text: e == null ? '' : groupDigits(e.amount));
    _type = e?.type ?? TxnType.expense;
    _categoryId = e?.categoryId;
    _walletId = e?.walletId ?? store.activeWallets.first.id!;
    _day = e?.dayOfMonth ?? store.now.day;
    _auto = e?.autoRecord ?? true;
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      toast(context, 'Pilih pos');
      return;
    }
    final store = context.read<FinanceStore>();
    final e = widget.edit;
    // Jatuh tempo berikutnya:
    // - baru dibuat → tanggal terdekat mulai hari ini
    // - tanggal diubah → tetap di bulan yang BELUM tercatat (tidak ganda / terlewat)
    // - diaktifkan lagi → tidak menagih bulan-bulan saat nonaktif
    DateTime next;
    if (e == null) {
      next = firstDueOnOrAfter(store.now, _day);
    } else {
      next = e.dayOfMonth != _day ? paydayIn(e.nextDate.year, e.nextDate.month, _day) : e.nextDate;
      if (!e.active && _active && next.isBefore(dateOnly(store.now))) {
        next = firstDueOnOrAfter(store.now, _day);
      }
    }
    await store.saveRecurring(Recurring(
      id: e?.id,
      title: _title.text.trim(),
      type: _type,
      amount: parseDigits(_amount.text),
      categoryId: _categoryId,
      walletId: _walletId,
      dayOfMonth: _day,
      nextDate: next,
      autoRecord: _auto,
      active: _active,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final store = context.read<FinanceStore>();
    final nav = Navigator.of(context);
    final ok = await confirm(context,
        title: 'Hapus "${widget.edit!.title}"?',
        message: 'Transaksi yang sudah tercatat tidak ikut terhapus.',
        ok: 'Hapus',
        destructive: true);
    if (!ok) return;
    await store.deleteRecurring(widget.edit!.id!);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final cats = _type == TxnType.income ? store.incomeCategories : store.expenseCategories;
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
                Row(children: [
                  Expanded(
                    child: Text(widget.edit == null ? 'Transaksi rutin baru' : 'Ubah transaksi rutin',
                        style: context.text.titleLarge),
                  ),
                  if (widget.edit != null)
                    IconButton(
                      tooltip: 'Hapus',
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline_rounded, color: context.palette.expense),
                    ),
                ]),
                const SizedBox(height: 12),
                SegmentedButton<TxnType>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: TxnType.expense, label: Text('Pengeluaran')),
                    ButtonSegment(value: TxnType.income, label: Text('Pemasukan')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() {
                    _type = s.first;
                    _categoryId = null;
                  }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nama', hintText: 'mis. Bayar kos, Indihome'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Isi nama' : null,
                ),
                const SizedBox(height: 12),
                MoneyField(controller: _amount, label: 'Nominal', validator: requiredAmount),
                const SizedBox(height: 16),
                Text('Pos', style: context.text.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in cats)
                      ChoiceChip(
                        avatar: Icon(iconFor(c.icon), size: 18, color: Color(c.color)),
                        label: Text(c.name),
                        selected: _categoryId == c.id,
                        onSelected: (_) => setState(() => _categoryId = c.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Dompet', style: context.text.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final w in store.activeWallets)
                      ChoiceChip(
                        label: Text(w.name),
                        selected: _walletId == w.id,
                        onSelected: (_) => setState(() => _walletId = w.id!),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Tanggal setiap bulan', style: context.text.labelLarge)),
                    DropdownButton<int>(
                      value: _day,
                      borderRadius: BorderRadius.circular(14),
                      items: [
                        for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('Tgl $d')),
                      ],
                      onChanged: (v) => setState(() => _day = v!),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Catat otomatis'),
                  subtitle: Text(_auto
                      ? 'Langsung tercatat saat jatuh tempo (cocok untuk nominal tetap)'
                      : 'Hanya diingatkan, kamu isi nominal aktual (cocok untuk listrik/air)'),
                  value: _auto,
                  onChanged: (v) => setState(() => _auto = v),
                ),
                if (widget.edit != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktif'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _save, child: const Text('Simpan')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
