// Riwayat transaksi per periode gajian: cari, filter, dikelompokkan per hari.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../logic/period.dart';
import '../../state/finance_store.dart';
import '../txn/txn_tile.dart';
import '../widgets/common.dart';
import '../widgets/period_switcher.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  PayPeriod? _period;
  TxnType? _type;
  int? _categoryId;
  int? _walletId;
  String _query = '';
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _filtered => _type != null || _categoryId != null || _walletId != null;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    // Kalau tanggal gajian diubah, periode yang sedang dilihat ikut disesuaikan.
    final p0 = _period;
    final period = p0 != null && p0.payday == store.settings.payday ? p0 : store.currentPeriod;
    final q = _query.trim().toLowerCase();

    final list = store.transactions.where((t) {
      if (!period.contains(t.date)) return false;
      if (_type != null && t.type != _type) return false;
      if (_categoryId != null && t.categoryId != _categoryId) return false;
      if (_walletId != null && t.walletId != _walletId && t.toWalletId != _walletId) return false;
      if (q.isNotEmpty) {
        final cat = store.category(t.categoryId)?.name.toLowerCase() ?? '';
        if (!t.note.toLowerCase().contains(q) && !cat.contains(q) && !t.amount.toString().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    // Kelompokkan per hari
    final groups = <DateTime, List<Txn>>{};
    for (final t in list) {
      groups.putIfAbsent(dateOnly(t.date), () => []).add(t);
    }
    var totalIn = 0, totalOut = 0;
    for (final t in list) {
      if (t.isIncome) totalIn += t.amount;
      if (t.isExpense && !store.savingCategoryIds.contains(t.categoryId)) totalOut += t.amount;
    }

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Cari catatan, pos, nominal…',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('Riwayat'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Tutup pencarian' : 'Cari',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _search.clear();
                _query = '';
              }
            }),
          ),
          IconButton(
            tooltip: 'Filter',
            icon: Badge(isLabelVisible: _filtered, child: const Icon(Icons.tune_rounded)),
            onPressed: _openFilter,
          ),
        ],
      ),
      body: Column(
        children: [
          PeriodSwitcher(
            period: period,
            current: store.currentPeriod,
            onChanged: (p) => setState(() => _period = p),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                for (final (label, type) in [
                  ('Semua', null),
                  ('Keluar', TxnType.expense),
                  ('Masuk', TxnType.income),
                  ('Transfer', TxnType.transfer),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(child: Text('${list.length} transaksi', style: context.text.bodySmall)),
                Money(totalIn, signed: true, compact: true,
                    style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                    color: context.palette.income),
                const SizedBox(width: 12),
                Money(-totalOut, signed: true, compact: true,
                    style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                    color: context.palette.expense),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: list.isEmpty
                ? ListView(children: [
                    EmptyState(
                      icon: Icons.inbox_rounded,
                      title: q.isNotEmpty || _filtered ? 'Tidak ada yang cocok' : 'Belum ada transaksi',
                      message: q.isNotEmpty || _filtered
                          ? 'Coba ubah kata kunci atau filter.'
                          : 'Transaksi di periode ini akan muncul di sini.',
                    ),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: groups.length,
                    itemBuilder: (_, i) {
                      final day = groups.keys.elementAt(i);
                      final items = groups[day]!;
                      final dayOut = items.where((t) => t.isExpense && !store.savingCategoryIds.contains(t.categoryId))
                          .fold(0, (s, t) => s + t.amount);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                            child: Row(
                              children: [
                                Text(fmtRelativeDay(day, now: store.now),
                                    style: context.text.labelLarge?.copyWith(color: context.palette.muted)),
                                const Spacer(),
                                if (dayOut > 0)
                                  Money(-dayOut, signed: true,
                                      style: context.text.labelLarge?.copyWith(color: context.palette.muted)),
                              ],
                            ),
                          ),
                          for (final t in items) DismissibleTxnTile(t),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilter() async {
    final store = context.read<FinanceStore>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void update(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filter', style: ctx.text.titleLarge),
                  const SizedBox(height: 16),
                  Text('Pos / sumber', style: ctx.text.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Semua'),
                        selected: _categoryId == null,
                        onSelected: (_) => update(() => _categoryId = null),
                      ),
                      for (final c in store.categories.where((c) => !c.archived))
                        ChoiceChip(
                          avatar: Icon(iconFor(c.icon), size: 18, color: Color(c.color)),
                          label: Text(c.name),
                          selected: _categoryId == c.id,
                          onSelected: (_) => update(() => _categoryId = c.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Dompet', style: ctx.text.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Semua'),
                        selected: _walletId == null,
                        onSelected: (_) => update(() => _walletId = null),
                      ),
                      for (final w in store.wallets)
                        ChoiceChip(
                          avatar: Icon(iconFor(w.icon), size: 18, color: Color(w.color)),
                          label: Text(w.name),
                          selected: _walletId == w.id,
                          onSelected: (_) => update(() => _walletId = w.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => update(() {
                            _categoryId = null;
                            _walletId = null;
                            _type = null;
                          }),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Terapkan'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
