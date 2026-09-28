// Dompet & rekening: saldo per dompet, tambah/ubah, transfer.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/finance_store.dart';
import '../txn/txn_form.dart';
import '../widgets/common.dart';

class WalletsScreen extends StatelessWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final wallets = store.activeWallets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dompet & Rekening'),
        actions: [
          IconButton(
            tooltip: 'Tambah dompet',
            onPressed: () => showWalletEditor(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: wallets.length >= 2
          ? FloatingActionButton.extended(
              onPressed: () => openTxnForm(context, type: TxnType.transfer),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Transfer'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total saldo', style: context.text.bodySmall),
                Money(store.totalBalance, style: context.text.headlineMedium),
                const SizedBox(height: 4),
                Text('Tidak termasuk uang yang sudah masuk pos tabungan (${rupiah(store.totalSaved)}).',
                    style: context.text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final w in wallets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => showWalletEditor(context, edit: w),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    IconBadge(icon: w.icon, color: w.color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.name, style: context.text.titleSmall),
                          Text(w.kind.label, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    Money(store.walletBalance(w.id!),
                        style: context.text.titleSmall,
                        color: store.walletBalance(w.id!) < 0 ? context.palette.expense : null),
                  ],
                ),
              ),
            ),
          if (wallets.isEmpty)
            EmptyState(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Belum ada dompet',
              action: 'Tambah dompet',
              onAction: () => showWalletEditor(context),
            ),
          const SizedBox(height: 8),
          Text(
            'Tips: pisahkan dompet sesuai tempat uangmu (Tunai, BCA, GoPay…). '
            'Saat tarik tunai atau top-up, catat sebagai Transfer supaya saldo tiap dompet tetap akurat.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

Future<void> showWalletEditor(BuildContext context, {Wallet? edit}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WalletEditor(edit: edit),
  );
}

class _WalletEditor extends StatefulWidget {
  const _WalletEditor({this.edit});
  final Wallet? edit;

  @override
  State<_WalletEditor> createState() => _WalletEditorState();
}

class _WalletEditorState extends State<_WalletEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late WalletKind _kind;
  late bool _negative;
  bool _balanceEdited = false;
  late String _icon;
  late int _color;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _name = TextEditingController(text: e?.name ?? '');
    _kind = e?.kind ?? WalletKind.bank;
    _icon = e?.icon ?? _kind.defaultIcon;
    _color = e?.color ?? 0xFF2A78D6;
    // Saat mengubah, tampilkan saldo SEKARANG (lebih intuitif daripada saldo awal).
    final bal = e == null ? 0 : context.read<FinanceStore>().walletBalance(e.id!);
    _balance = TextEditingController(text: bal != 0 ? groupDigits(bal.abs()) : '');
    _negative = bal < 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final store = context.read<FinanceStore>();
    final target = parseDigits(_balance.text) * (_negative ? -1 : 1);
    final e = widget.edit;
    int initial;
    if (e == null) {
      initial = target;
    } else if (!_balanceEdited) {
      // Saldo tidak disentuh → jangan ubah apa pun.
      initial = e.initialBalance;
    } else {
      // Sesuaikan saldo awal supaya saldo sekarang = angka yang diisi.
      final current = store.walletBalance(e.id!);
      initial = e.initialBalance + (target - current);
    }
    await store.saveWallet((e ?? const Wallet(name: '')).copyWith(
      name: _name.text.trim(),
      kind: _kind,
      icon: _icon,
      color: _color,
      initialBalance: initial,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final store = context.read<FinanceStore>();
    final nav = Navigator.of(context);
    final ok = await confirm(context,
        title: 'Hapus dompet "${widget.edit!.name}"?',
        message: 'Kalau dompet ini sudah punya transaksi, dompet akan diarsipkan agar riwayat tetap utuh.',
        ok: 'Hapus',
        destructive: true);
    if (!ok) return;
    await store.removeWallet(widget.edit!);
    nav.pop();
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
                Row(children: [
                  IconBadge(icon: _icon, color: _color, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.edit == null ? 'Dompet baru' : 'Ubah dompet',
                        style: context.text.titleLarge),
                  ),
                  if (widget.edit != null)
                    IconButton(
                      tooltip: 'Hapus',
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline_rounded, color: context.palette.expense),
                    ),
                ]),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final k in WalletKind.values)
                      ChoiceChip(
                        label: Text(k.label),
                        selected: _kind == k,
                        onSelected: (_) => setState(() {
                          _kind = k;
                          _icon = k.defaultIcon;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama', hintText: 'mis. BCA, GoPay, Dompet'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Isi nama dompet' : null,
                ),
                const SizedBox(height: 12),
                MoneyField(
                  controller: _balance,
                  label: widget.edit == null ? 'Saldo saat ini' : 'Saldo sekarang (koreksi jika beda)',
                  onChanged: (_) => _balanceEdited = true,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Saldo minus'),
                  subtitle: const Text('mis. kartu kredit / paylater yang masih terutang'),
                  value: _negative,
                  onChanged: (v) => setState(() {
                    _negative = v;
                    _balanceEdited = true;
                  }),
                ),
                const SizedBox(height: 16),
                Text('Warna', style: context.text.labelLarge),
                const SizedBox(height: 8),
                ColorChooser(value: _color, onChanged: (c) => setState(() => _color = c)),
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
