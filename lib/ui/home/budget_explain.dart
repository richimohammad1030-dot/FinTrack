// Lembar "Cara hitung batas harian": menjelaskan asal angka jatah hari ini.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../logic/budget.dart';
import '../../state/finance_store.dart';
import '../budget/budget_screen.dart';
import '../reports/daily_calendar.dart';

Future<void> showDailyBudgetExplain(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ExplainSheet(),
  );
}

class _ExplainSheet extends StatelessWidget {
  const _ExplainSheet();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final summary = store.currentSummary;
    final b = store.dailyBudget;
    final bd = BudgetBreakdown.of(summary, store.categories);
    final left = b.periodBudget - b.spentBefore;
    final raw = b.daysLeft > 0 && left > 0 ? left ~/ b.daysLeft : 0;

    Widget line(String label, String value, {bool bold = false, Color? color, String? note}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: bold ? context.text.titleSmall : context.text.bodyMedium),
                    if (note != null) Text(note, style: context.text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(value,
                  style: (bold ? context.text.titleSmall : context.text.bodyMedium)
                      ?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        );

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Cara hitung batas harian', style: context.text.titleLarge),
            const SizedBox(height: 6),
            Text(
              b.isManual
                  ? 'Batas harian diatur manual di Pengaturan, jadi angkanya tetap setiap hari.'
                  : 'Jatah hari ini = (anggaran pos harian − yang sudah terpakai sebelum hari ini) '
                      '÷ sisa hari sampai gajian. Pos bulanan (kos, tagihan, dll.) tidak ikut.',
              style: context.text.bodyMedium?.copyWith(color: context.palette.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (b.isManual) ...[
              line('Batas manual', rupiah(b.allowance), bold: true),
            ] else ...[
              Text(bd.usesFallback ? '1. Anggaran (belum ada batas pos harian)' : '1. Anggaran pos harian',
                  style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
              const SizedBox(height: 4),
              if (!bd.usesFallback)
                for (final (pos, limit) in bd.dailyPos)
                  line(pos.name, limit > 0 ? rupiah(limit) : '–', note: limit > 0 ? null : 'belum diberi batas')
              else ...[
                line('Pemasukan periode ini', rupiah(bd.income)),
                for (final (pos, v) in bd.reservedPos) line('− ${pos.name}', rupiah(v)),
              ],
              line('Total anggaran harian', rupiah(b.periodBudget), bold: true),
              const Divider(height: 24),
              Text('2. Sisa anggaran', style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
              const SizedBox(height: 4),
              line('Terpakai pos harian sebelum hari ini', '− ${rupiah(b.spentBefore)}'),
              line('Sisa anggaran harian', rupiah(left > 0 ? left : 0), bold: true),
              const Divider(height: 24),
              Text('3. Dibagi sisa hari', style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
              const SizedBox(height: 4),
              line('Sisa hari (termasuk hari ini)', '÷ ${b.daysLeft} hari',
                  note: 'sampai ${fmtDate(summary.period.lastDay)}'),
              line('Hasil', rupiah(raw)),
              line('Jatah hari ini', rupiah(b.allowance),
                  bold: true, color: context.colors.primary, note: 'dibulatkan ke bawah kelipatan Rp 500'),
            ],
            const Divider(height: 24),
            line('Terpakai hari ini', rupiah(b.spentToday)),
            line(b.remainingToday >= 0 ? 'Sisa jatah hari ini' : 'Lewat dari jatah', rupiah(b.remainingToday.abs()),
                bold: true, color: b.remainingToday >= 0 ? context.palette.income : context.palette.expense),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Hemat hari ini → sisanya dibagi ke hari-hari berikutnya, jatah besok naik. '
                'Boros hari ini → jatah besok turun. Untuk mengubah besarnya, atur batas pos harian di Bagi Gaji.',
                style: context.text.bodySmall?.copyWith(height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DailyCalendarPage()));
              },
              icon: const Icon(Icons.calendar_month_rounded),
              label: const Text('Lihat laporan harian (kalender)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                openAllocate(context);
              },
              icon: const Icon(Icons.pie_chart_rounded),
              label: const Text('Atur batas pos (Bagi Gaji)'),
            ),
          ],
        ),
      ),
    );
  }
}

