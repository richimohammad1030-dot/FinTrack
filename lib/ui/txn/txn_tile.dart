// Satu baris transaksi di daftar.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/finance_store.dart';
import '../debt/debt_screen.dart';
import '../widgets/common.dart';
import 'txn_form.dart';

class TxnTile extends StatelessWidget {
  const TxnTile(this.txn, {super.key, this.showDate = false});

  final Txn txn;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final cat = store.category(txn.categoryId);
    final wallet = store.wallet(txn.walletId);
    final p = context.palette;

    final String title;
    final String icon;
    final int color;
    final Color amountColor;
    final String subtitle;
    if (txn.isDebt) {
      final d = store.debt(txn.debtId);
      title = debtTxnTitle(txn, d);
      icon = 'loan';
      color = d == null ? 0xFF64748B : debtColor(context, d.kind).toARGB32();
      amountColor = txn.type.isInflow ? p.income : context.colors.onSurface;
      subtitle = [if (txn.note.isNotEmpty) txn.note, wallet?.name ?? '?'].join(' · ');
    } else if (txn.isTransfer) {
      final to = store.wallet(txn.toWalletId);
      title = txn.note.isNotEmpty ? txn.note : 'Transfer';
      icon = 'wallet';
      color = 0xFF64748B;
      amountColor = context.colors.onSurface;
      subtitle = '${wallet?.name ?? '?'} → ${to?.name ?? '?'}';
    } else {
      title = txn.note.isNotEmpty ? txn.note : (cat?.name ?? 'Tanpa pos');
      icon = cat?.icon ?? 'category';
      color = cat?.color ?? 0xFF64748B;
      amountColor = txn.isIncome
          ? p.income
          : (cat?.isSaving ?? false)
              ? p.saving
              : context.colors.onSurface;
      final goal = store.goal(txn.goalId);
      subtitle = [
        if (txn.note.isNotEmpty) cat?.name ?? 'Tanpa pos',
        if (goal != null) '🎯 ${goal.name}',
        wallet?.name ?? '?',
      ].join(' · ');
    }

    return InkWell(
      onTap: () => txn.isDebt && txn.debtId != null
          ? openDebtDetail(context, txn.debtId!)
          : openTxnForm(context, edit: txn),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    showDate ? '${fmtDayMonth(txn.date)} · $subtitle' : subtitle,
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Money(
              txn.isExpense || txn.type == TxnType.debtOut ? -txn.amount : txn.amount,
              signed: !txn.isTransfer,
              color: amountColor,
              style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bungkus [TxnTile] dengan geser-kiri-untuk-hapus + tombol Urungkan.
class DismissibleTxnTile extends StatelessWidget {
  const DismissibleTxnTile(this.txn, {super.key, this.showDate = false});

  final Txn txn;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    return Dismissible(
      key: ValueKey('txn-${txn.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: context.palette.expense.withValues(alpha: 0.15),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hapus',
                style: TextStyle(color: context.palette.expense, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Icon(Icons.delete_outline_rounded, color: context.palette.expense),
          ],
        ),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        final removed = await store.deleteTxn(txn.id!);
        if (removed == null) return;
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('Transaksi dihapus'),
            action: SnackBarAction(label: 'Urungkan', onPressed: () => store.restoreTxn(removed)),
          ));
      },
      child: TxnTile(txn, showDate: showDate),
    );
  }
}
