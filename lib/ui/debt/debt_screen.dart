// Hutang & piutang: daftar, detail, catat baru, pembayaran, cicilan rutin.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../logic/period.dart';
import '../../logic/recurring.dart';
import '../../state/finance_store.dart';
import '../../state/settings.dart';
import '../widgets/common.dart';

void openDebts(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DebtsScreen()));

void openDebtDetail(BuildContext context, int debtId) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: debtId)));

/// Warna identitas: hutang (merah) & piutang (biru).
Color debtColor(BuildContext context, DebtKind k) =>
    k == DebtKind.payable ? context.palette.expense : const Color(0xFF2A78D6);

/// Judul transaksi hutang untuk daftar riwayat.
String debtTxnTitle(Txn t, Debt? d) {
  if (d == null) return t.type == TxnType.debtIn ? 'Hutang masuk' : 'Hutang keluar';
  final increase = t.type == d.increaseType;
  if (d.isPayable) return increase ? 'Pinjam dari ${d.name}' : 'Bayar hutang ke ${d.name}';
  return increase ? 'Pinjamkan ke ${d.name}' : 'Terima bayaran dari ${d.name}';
}

/// Teks status jatuh tempo: "Jatuh tempo 3 hari lagi", "Terlambat 2 hari".
(String, bool)? dueLabel(Debt d, DateTime now) {
  final due = d.dueDate;
  if (due == null) return null;
  final days = daysBetween(now, due);
  if (days < 0) return ('Terlambat ${-days} hari', true);
  if (days == 0) return ('Jatuh tempo hari ini', true);
  if (days <= 7) return ('Jatuh tempo $days hari lagi', true);
  return ('Jatuh tempo ${fmtDate(due)}', false);
}

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  DebtKind _kind = DebtKind.payable;
  bool _showSettled = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final all = store.debtStatuses.where((s) => s.debt.kind == _kind).toList();
    final active = all.where((s) => !s.settled).toList();
    final settled = all.where((s) => s.settled).toList();
    final total = active.fold(0, (a, s) => a + s.remaining);
    final isPay = _kind == DebtKind.payable;

    return Scaffold(
      appBar: AppBar(title: const Text('Hutang & Piutang')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDebtEditor(context, kind: _kind),
        icon: const Icon(Icons.add_rounded),
        label: Text(isPay ? 'Catat hutang' : 'Catat piutang'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          SegmentedButton<DebtKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: DebtKind.payable, label: Text('Hutang saya')),
              ButtonSegment(value: DebtKind.receivable, label: Text('Piutang')),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isPay ? 'Total sisa hutang' : 'Total piutang belum kembali',
                          style: context.text.bodySmall),
                      const SizedBox(height: 4),
                      Money(total, style: context.text.headlineSmall, color: total > 0 ? debtColor(context, _kind) : null),
                      const SizedBox(height: 2),
                      Text('${active.length} aktif · ${settled.length} lunas', style: context.text.bodySmall),
                    ],
                  ),
                ),
                Icon(isPay ? Icons.call_made_rounded : Icons.call_received_rounded,
                    size: 32, color: debtColor(context, _kind).withValues(alpha: 0.6)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (active.isEmpty)
            EmptyState(
              icon: isPay ? Icons.handshake_rounded : Icons.volunteer_activism_rounded,
              title: isPay ? 'Tidak ada hutang aktif 🎉' : 'Tidak ada piutang aktif',
              message: isPay
                  ? 'Catat pinjaman, paylater, atau cicilan supaya sisa dan jatuh temponya terpantau.'
                  : 'Catat uang yang kamu pinjamkan supaya tidak lupa ditagih.',
            )
          else
            for (final s in active) Padding(padding: const EdgeInsets.only(bottom: 8), child: DebtCard(status: s)),
          if (settled.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => setState(() => _showSettled = !_showSettled),
              icon: Icon(_showSettled ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text('${_showSettled ? 'Sembunyikan' : 'Tampilkan'} yang sudah lunas (${settled.length})'),
            ),
            if (_showSettled)
              for (final s in settled) Padding(padding: const EdgeInsets.only(bottom: 8), child: DebtCard(status: s)),
          ],
        ],
      ),
    );
  }
}

class DebtCard extends StatelessWidget {
  const DebtCard({super.key, required this.status, this.compact = false});
  final DebtStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = status.debt;
    final color = debtColor(context, d.kind);
    final due = status.settled ? null : dueLabel(d, context.read<FinanceStore>().now);
    return Opacity(
      opacity: status.settled ? 0.6 : 1,
      child: AppCard(
        onTap: () => openDebtDetail(context, d.id!),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon: d.isPayable ? 'loan' : 'charity', color: color.toARGB32(), size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      if (status.settled)
                        Text('Lunas', style: context.text.bodySmall?.copyWith(color: context.palette.income))
                      else if (due != null)
                        Text(due.$1,
                            style: context.text.bodySmall?.copyWith(
                                color: due.$2 ? context.palette.warning : null,
                                fontWeight: due.$2 ? FontWeight.w700 : null))
                      else
                        Text(d.isPayable ? 'Tanpa jatuh tempo' : 'Belum ditentukan kapan kembali',
                            style: context.text.bodySmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Money(status.settled ? status.total : status.remaining, style: context.text.titleSmall),
                    Text(status.settled ? 'total' : 'sisa', style: context.text.bodySmall),
                  ],
                ),
              ],
            ),
            if (!compact && status.total > 0) ...[
              const SizedBox(height: 12),
              Bar(ratio: status.ratio, color: status.settled ? context.palette.income : color, height: 7),
              const SizedBox(height: 6),
              Text(
                '${d.isPayable ? 'Terbayar' : 'Kembali'} ${rupiah(status.paid)} dari ${rupiah(status.total)} · ${percent(status.ratio)}',
                style: context.text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Detail ────────────────────────────────────────────────────────────────

class DebtDetailScreen extends StatelessWidget {
  const DebtDetailScreen({super.key, required this.debtId});
  final int debtId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final d = store.debt(debtId);
    if (d == null) return const Scaffold();
    final st = store.debtStatus(d);
    final txns = store.debtTxns(debtId);
    final plans = store.debtRecurrings(debtId);
    final color = debtColor(context, d.kind);
    final due = st.settled ? null : dueLabel(d, store.now);

    return Scaffold(
      appBar: AppBar(
        title: Text(d.name),
        actions: [
          IconButton(
            tooltip: 'Ubah',
            onPressed: () => showDebtEditor(context, kind: d.kind, edit: d),
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      floatingActionButton: st.settled
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showDebtPayment(context, d),
              icon: const Icon(Icons.payments_rounded),
              label: Text(d.isPayable ? 'Bayar' : 'Terima bayaran'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Pill(d.isPayable ? 'Hutang saya' : 'Piutang', color: color),
                  const Spacer(),
                  if (st.settled)
                    Pill('Lunas', color: context.palette.income, icon: Icons.check_circle_rounded)
                  else if (due != null)
                    Pill(due.$1, color: due.$2 ? context.palette.warning : context.palette.muted,
                        icon: Icons.event_rounded),
                ]),
                const SizedBox(height: 14),
                Text(st.settled ? 'Sudah lunas' : 'Sisa', style: context.text.bodySmall),
                Money(st.settled ? st.total : st.remaining, style: context.text.headlineMedium),
                const SizedBox(height: 14),
                Bar(ratio: st.ratio, color: st.settled ? context.palette.income : color, height: 10),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _Fig(label: 'Total pinjaman', value: st.total)),
                  Expanded(child: _Fig(label: d.isPayable ? 'Sudah dibayar' : 'Sudah kembali', value: st.paid)),
                ]),
                if (d.note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(d.note, style: context.text.bodyMedium),
                ],
                const SizedBox(height: 8),
                Text('Sejak ${fmtDate(d.startDate)}', style: context.text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showDebtPayment(context, d, increase: true),
                icon: const Icon(Icons.add_rounded),
                label: Text(d.isPayable ? 'Pinjam lagi' : 'Pinjamkan lagi'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showInstallmentEditor(context, d, edit: plans.firstOrNull),
                icon: const Icon(Icons.event_repeat_rounded),
                label: Text(plans.isEmpty ? 'Cicilan rutin' : 'Ubah cicilan'),
              ),
            ),
          ]),
          if (plans.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in plans)
              AppCard(
                padding: const EdgeInsets.all(14),
                onTap: () => showInstallmentEditor(context, d, edit: r),
                child: Row(children: [
                  Icon(Icons.event_repeat_rounded, color: r.active ? context.colors.primary : context.palette.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      r.active
                          ? '${rupiah(r.amount)} tiap tgl ${r.dayOfMonth} · berikutnya ${fmtDayMonth(r.nextDate)}'
                              '${r.autoRecord ? '' : ' (diingatkan)'}'
                          : 'Cicilan ${rupiah(r.amount)} berhenti (nonaktif / sudah lunas)',
                      style: context.text.bodyMedium,
                    ),
                  ),
                ]),
              ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Riwayat', style: context.text.titleMedium)),
            if (!st.settled)
              TextButton(
                onPressed: () async {
                  final ok = await confirm(context,
                      title: d.isPayable ? 'Tandai lunas?' : 'Ikhlaskan sisa piutang?',
                      message: 'Sisa ${rupiah(st.remaining)} dianggap selesai tanpa mencatat uang keluar/masuk.',
                      ok: 'Ya, tutup');
                  if (ok) await store.setDebtClosed(d, true);
                },
                child: const Text('Tutup tanpa bayar'),
              )
            else if (d.closed)
              TextButton(onPressed: () => store.setDebtClosed(d, false), child: const Text('Buka lagi')),
          ]),
          if (txns.isEmpty && d.principal > 0)
            Text('Hutang lama ${rupiah(d.principal)} dicatat tanpa mengubah saldo dompet.',
                style: context.text.bodySmall),
          for (final t in txns) _DebtTxnTile(debt: d, txn: t),
          if (d.principal > 0 && txns.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('+ saldo awal ${rupiah(d.principal)} (tanpa mutasi dompet)', style: context.text.bodySmall),
            ),
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
          Money(value, style: context.text.titleSmall),
        ],
      );
}

class _DebtTxnTile extends StatelessWidget {
  const _DebtTxnTile({required this.debt, required this.txn});
  final Debt debt;
  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final increase = txn.type == debt.increaseType;
    final wallet = store.wallet(txn.walletId);
    final inflow = txn.type.isInflow;
    return Dismissible(
      key: ValueKey('debt-txn-${txn.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: context.palette.expense.withValues(alpha: 0.15),
        child: Icon(Icons.delete_outline_rounded, color: context.palette.expense),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final removed = await store.deleteTxn(txn.id!);
        if (removed == null) return;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('Dihapus'),
            action: SnackBarAction(label: 'Urungkan', onPressed: () => store.restoreTxn(removed)),
          ));
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(
          increase ? Icons.add_circle_outline_rounded : Icons.check_circle_outline_rounded,
          color: increase ? debtColor(context, debt.kind) : context.palette.income,
        ),
        title: Text(increase
            ? (debt.isPayable ? 'Pinjaman' : 'Dipinjamkan')
            : (debt.isPayable ? 'Pembayaran' : 'Diterima kembali')),
        subtitle: Text([
          fmtDate(txn.date),
          wallet?.name ?? '?',
          if (txn.note.isNotEmpty) txn.note,
        ].join(' · ')),
        trailing: Money(inflow ? txn.amount : -txn.amount,
            signed: true,
            color: inflow ? context.palette.income : null,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () => showDebtPayment(context, debt, edit: txn),
      ),
    );
  }
}

// ── Catat hutang baru / ubah ──────────────────────────────────────────────

Future<void> showDebtEditor(BuildContext context, {required DebtKind kind, Debt? edit}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DebtEditor(kind: kind, edit: edit),
  );
}

class _DebtEditor extends StatefulWidget {
  const _DebtEditor({required this.kind, this.edit});
  final DebtKind kind;
  final Debt? edit;

  @override
  State<_DebtEditor> createState() => _DebtEditorState();
}

class _DebtEditorState extends State<_DebtEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.edit?.name ?? '');
  late final _amount = TextEditingController(
      text: (widget.edit?.principal ?? 0) > 0 ? groupDigits(widget.edit!.principal) : '');
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  late DebtKind _kind = widget.kind;
  late DateTime _start;
  DateTime? _due;
  bool _viaWallet = true;
  int? _walletId;
  bool _busy = false;

  bool get _isEdit => widget.edit != null;

  @override
  void initState() {
    super.initState();
    final store = context.read<FinanceStore>();
    _start = widget.edit?.startDate ?? store.now;
    _due = widget.edit?.dueDate;
    final wallets = store.activeWallets;
    final last = context.read<Settings>().lastWalletId;
    _walletId = wallets.any((w) => w.id == last) ? last : wallets.firstOrNull?.id;
    _viaWallet = _walletId != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final base = _due ?? DateTime(now.year, now.month + 1, now.day);
    final first = DateTime(2000);
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: first,
      lastDate: DateTime(now.year + 30),
      helpText: 'Jatuh tempo',
    );
    if (d != null) setState(() => _due = d);
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day, 12));
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final store = context.read<FinanceStore>();
    final nav = Navigator.of(context);
    if (_isEdit) {
      final e = widget.edit!;
      final newPrincipal = parseDigits(_amount.text);
      await store.updateDebt(e.copyWith(
        name: _name.text.trim(),
        note: _note.text.trim(),
        startDate: _start,
        dueDate: _due,
        clearDueDate: _due == null,
        principal: newPrincipal,
      ));
      nav.pop();
    } else {
      final id = await store.createDebt(
        Debt(kind: _kind, name: _name.text.trim(), startDate: _start, dueDate: _due, note: _note.text.trim()),
        amount: parseDigits(_amount.text),
        walletId: _viaWallet ? _walletId : null,
      );
      nav.pop();
      if (nav.mounted) {
        nav.push(MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: id)));
      }
    }
  }

  Future<void> _delete() async {
    final store = context.read<FinanceStore>();
    final nav = Navigator.of(context);
    final ok = await confirm(context,
        title: 'Hapus "${widget.edit!.name}"?',
        message: 'Semua pembayaran & cicilan rutin untuk hutang ini ikut terhapus, dan saldo dompet menyesuaikan.',
        ok: 'Hapus',
        destructive: true);
    if (!ok) return;
    await store.deleteDebt(widget.edit!.id!);
    nav.pop(); // tutup lembar ini
    if (nav.canPop()) nav.pop(); // tutup halaman detail
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final isPay = _kind == DebtKind.payable;
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
                    child: Text(_isEdit ? 'Ubah ${isPay ? 'hutang' : 'piutang'}' : 'Catat ${isPay ? 'hutang' : 'piutang'}',
                        style: context.text.titleLarge),
                  ),
                  if (_isEdit)
                    IconButton(
                      tooltip: 'Hapus',
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline_rounded, color: context.palette.expense),
                    ),
                ]),
                const SizedBox(height: 12),
                if (!_isEdit)
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<DebtKind>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: DebtKind.payable, label: Text('Saya berhutang')),
                        ButtonSegment(value: DebtKind.receivable, label: Text('Orang berhutang')),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (v) => setState(() => _kind = v.first),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: isPay ? 'Berhutang ke siapa?' : 'Siapa yang berhutang?',
                    hintText: isPay ? 'mis. Budi, Kredivo, KPR BTN' : 'mis. Andi',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Isi nama' : null,
                ),
                const SizedBox(height: 12),
                MoneyField(
                  controller: _amount,
                  label: _isEdit ? 'Saldo awal tanpa mutasi dompet' : 'Jumlah',
                  validator: _isEdit ? null : requiredAmount,
                ),
                if (_isEdit)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Untuk menambah pinjaman atau mencatat pembayaran, pakai tombol di halaman detail.',
                        style: context.text.bodySmall),
                  ),
                if (!_isEdit) ...[
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(isPay ? 'Uangnya masuk ke dompet' : 'Uangnya keluar dari dompet'),
                    subtitle: Text(_viaWallet
                        ? (isPay ? 'Saldo dompet bertambah' : 'Saldo dompet berkurang')
                        : 'Matikan untuk hutang lama / barang (saldo tidak berubah)'),
                    value: _viaWallet,
                    onChanged: store.activeWallets.isEmpty ? null : (v) => setState(() => _viaWallet = v),
                  ),
                  if (_viaWallet)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final w in store.activeWallets)
                          ChoiceChip(
                            avatar: Icon(iconFor(w.icon), size: 18, color: Color(w.color)),
                            label: Text(w.name),
                            selected: _walletId == w.id,
                            onSelected: (_) => setState(() => _walletId = w.id),
                          ),
                      ],
                    ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.today_rounded),
                  title: Text('Tanggal ${fmtDate(_start)}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickStart,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: Text(_due == null ? 'Jatuh tempo (opsional)' : 'Jatuh tempo ${fmtDate(_due!)}'),
                  subtitle: const Text('Diingatkan H-3 dan pada hari jatuh tempo'),
                  trailing: _due == null
                      ? const Icon(Icons.chevron_right_rounded)
                      : IconButton(
                          tooltip: 'Hapus jatuh tempo',
                          onPressed: () => setState(() => _due = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  onTap: _pickDue,
                ),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Catatan (opsional)', hintText: 'mis. untuk bayar kos'),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pembayaran / tambah pinjaman ──────────────────────────────────────────

Future<void> showDebtPayment(BuildContext context, Debt d, {bool increase = false, Txn? edit}) {
  final store = context.read<FinanceStore>();
  if (store.activeWallets.isEmpty) {
    toast(context, 'Tambahkan dompet dulu di menu Lainnya → Dompet');
    return Future.value();
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaymentSheet(debt: d, increase: edit == null ? increase : edit.type == d.increaseType, edit: edit),
  );
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.debt, required this.increase, this.edit});
  final Debt debt;
  final bool increase;
  final Txn? edit;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.edit == null ? '' : groupDigits(widget.edit!.amount));
  late final _note = TextEditingController(text: widget.edit?.note ?? '');
  int? _walletId;
  late DateTime _date;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<FinanceStore>();
    final wallets = store.activeWallets;
    final last = context.read<Settings>().lastWalletId;
    _walletId = widget.edit?.walletId ?? (wallets.any((w) => w.id == last) ? last : wallets.first.id);
    _date = widget.edit?.date ?? store.now;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Sisa maksimum yang boleh dibayar (termasuk nominal lama saat mengedit).
  int get _maxPay {
    final st = context.read<FinanceStore>().debtStatus(widget.debt);
    return st.remaining + (widget.edit != null && !widget.increase ? widget.edit!.amount : 0);
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate() || _walletId == null) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    await context.read<FinanceStore>().recordDebtTxn(
          widget.debt,
          amount: parseDigits(_amount.text),
          walletId: _walletId!,
          date: _date,
          note: _note.text.trim(),
          increase: widget.increase,
          edit: widget.edit,
        );
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final d = widget.debt;
    final title = widget.increase
        ? (d.isPayable ? 'Tambah pinjaman dari ${d.name}' : 'Pinjamkan lagi ke ${d.name}')
        : (d.isPayable ? 'Bayar hutang ke ${d.name}' : 'Terima bayaran dari ${d.name}');
    final max = _maxPay;
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
                Text(title, style: context.text.titleLarge),
                if (!widget.increase) ...[
                  const SizedBox(height: 4),
                  Text('Sisa saat ini ${rupiah(store.debtStatus(d).remaining)}', style: context.text.bodySmall),
                ],
                const SizedBox(height: 16),
                MoneyField(
                  controller: _amount,
                  large: true,
                  autofocus: widget.edit == null,
                  validator: (v) {
                    final n = parseDigits(v ?? '');
                    if (n <= 0) return 'Isi nominal';
                    if (!widget.increase && n > max) return 'Melebihi sisa (${rupiah(max)})';
                    return null;
                  },
                ),
                if (!widget.increase && max > 0) ...[
                  const SizedBox(height: 8),
                  ActionChip(
                    avatar: const Icon(Icons.done_all_rounded, size: 18),
                    label: Text('Lunasi semua · ${rupiah(max)}'),
                    onPressed: () => setState(() => _amount.text = groupDigits(max)),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  d.isPayable == !widget.increase ? 'Dari dompet' : 'Ke dompet',
                  style: context.text.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final w in store.activeWallets)
                      ChoiceChip(
                        avatar: Icon(iconFor(w.icon), size: 18, color: Color(w.color)),
                        label: Text(w.name),
                        selected: _walletId == w.id,
                        onSelected: (_) => setState(() => _walletId = w.id),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.today_rounded),
                  title: Text(fmtDate(_date)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day, 12));
                  },
                ),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Cicilan rutin ─────────────────────────────────────────────────────────

Future<void> showInstallmentEditor(BuildContext context, Debt d, {Recurring? edit}) {
  final store = context.read<FinanceStore>();
  if (store.activeWallets.isEmpty) {
    toast(context, 'Tambahkan dompet dulu');
    return Future.value();
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _InstallmentSheet(debt: d, edit: edit),
  );
}

class _InstallmentSheet extends StatefulWidget {
  const _InstallmentSheet({required this.debt, this.edit});
  final Debt debt;
  final Recurring? edit;

  @override
  State<_InstallmentSheet> createState() => _InstallmentSheetState();
}

class _InstallmentSheetState extends State<_InstallmentSheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.edit == null ? '' : groupDigits(widget.edit!.amount));
  late int _walletId;
  late int _day;
  late bool _auto;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final store = context.read<FinanceStore>();
    final e = widget.edit;
    _walletId = e?.walletId ?? store.activeWallets.first.id!;
    _day = e?.dayOfMonth ?? (widget.debt.dueDate?.day ?? store.now.day);
    _auto = e?.autoRecord ?? widget.debt.isPayable;
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final store = context.read<FinanceStore>();
    final nav = Navigator.of(context);
    final e = widget.edit;
    final d = widget.debt;
    DateTime next;
    if (e == null) {
      next = firstDueOnOrAfter(store.now, _day);
    } else {
      next = e.dayOfMonth != _day ? paydayIn(e.nextDate.year, e.nextDate.month, _day) : e.nextDate;
      if (!e.active && _active && next.isBefore(dateOnly(store.now))) next = firstDueOnOrAfter(store.now, _day);
    }
    await store.saveDebtInstallment(
      d,
      Recurring(
        id: e?.id,
        title: d.isPayable ? 'Cicilan ${d.name}' : 'Cicilan dari ${d.name}',
        type: d.decreaseType,
        amount: parseDigits(_amount.text),
        walletId: _walletId,
        dayOfMonth: _day,
        nextDate: next,
        autoRecord: _auto,
        active: _active,
        debtId: d.id,
      ),
    );
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final d = widget.debt;
    final remaining = store.debtStatus(d).remaining;
    final perMonth = parseDigits(_amount.text);
    final months = perMonth > 0 ? (remaining / perMonth).ceil() : 0;
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
                  Expanded(child: Text('Cicilan bulanan', style: context.text.titleLarge)),
                  if (widget.edit != null)
                    IconButton(
                      tooltip: 'Hapus cicilan',
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        await store.deleteRecurring(widget.edit!.id!);
                        nav.pop();
                      },
                      icon: Icon(Icons.delete_outline_rounded, color: context.palette.expense),
                    ),
                ]),
                const SizedBox(height: 4),
                Text('Dicatat tiap bulan sampai lunas, lalu berhenti sendiri.', style: context.text.bodySmall),
                const SizedBox(height: 16),
                MoneyField(
                  controller: _amount,
                  label: 'Nominal per bulan',
                  validator: requiredAmount,
                  onChanged: (_) => setState(() {}),
                ),
                if (months > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('≈ $months bulan lagi sampai lunas (sisa ${rupiah(remaining)})',
                        style: context.text.bodySmall),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text('Tanggal setiap bulan', style: context.text.labelLarge)),
                  DropdownButton<int>(
                    value: _day,
                    borderRadius: BorderRadius.circular(14),
                    items: [for (var i = 1; i <= 31; i++) DropdownMenuItem(value: i, child: Text('Tgl $i'))],
                    onChanged: (v) => setState(() => _day = v!),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(d.isPayable ? 'Dibayar dari dompet' : 'Masuk ke dompet', style: context.text.labelLarge),
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Catat otomatis'),
                  subtitle: Text(_auto
                      ? 'Langsung tercatat saat tanggalnya tiba (mis. autodebet)'
                      : 'Hanya diingatkan di beranda, kamu konfirmasi nominalnya'),
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
