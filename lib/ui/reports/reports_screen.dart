// Laporan: ke mana uang pergi, pengeluaran harian, perbandingan periode lalu.

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../logic/budget.dart';
import '../../logic/period.dart';
import '../../state/finance_store.dart';
import '../txn/txn_tile.dart';
import '../widgets/common.dart';
import '../widgets/period_switcher.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  PayPeriod? _period;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final p0 = _period;
    final period = p0 != null && p0.payday == store.settings.payday ? p0 : store.currentPeriod;
    final s = store.summaryFor(period);
    final prev = store.summaryFor(period.previous);

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          PeriodSwitcher(
            period: period,
            current: store.currentPeriod,
            onChanged: (p) => setState(() => _period = p),
          ),
          _SummaryCard(summary: s),
          const SectionHeader('Ke mana uangmu pergi?'),
          _WhereItWent(summary: s, previous: prev),
          const SectionHeader('Pengeluaran harian'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Hanya pos harian. Pos bulanan (kos, tagihan, dll.) dipantau lewat batas posnya.',
                style: context.text.bodySmall),
          ),
          _DailyChart(summary: s, categories: store.categories, now: store.now),
          _Insights(summary: s, previous: prev, now: store.now),
          if (s.incomeByCategory.isNotEmpty) ...[
            const SectionHeader('Sumber pemasukan'),
            _IncomeList(summary: s),
          ],
          const SectionHeader('Pengeluaran terbesar'),
          _TopExpenses(period: period),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = summary;
    final rate = s.income > 0 ? s.saving / s.income : 0.0;
    Widget row(String label, int v, Color c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: context.text.bodyMedium)),
              Money(v, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sisa periode ini', style: context.text.bodySmall),
            Money(s.net, style: context.text.headlineMedium,
                color: s.net < 0 ? p.expense : context.colors.onSurface),
            const SizedBox(height: 12),
            row('Pemasukan', s.income, p.income),
            row('Pengeluaran', s.expense, p.expense),
            row('Ditabung', s.saving, p.saving),
            if (s.debtIn > 0) row('Uang pinjaman / piutang kembali', s.debtIn, const Color(0xFF2A78D6)),
            if (s.debtOut > 0) row('Bayar hutang / meminjamkan', s.debtOut, p.warning),
            if (s.income > 0) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.savings_rounded, size: 18, color: p.saving),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Rasio menabung ${percent(rate)} dari pemasukan',
                        style: context.text.bodyMedium),
                  ),
                  Pill(rate >= 0.2 ? 'Sehat' : (rate >= 0.1 ? 'Cukup' : 'Rendah'),
                      color: rate >= 0.2 ? p.income : (rate >= 0.1 ? p.warning : p.expense),
                      icon: rate >= 0.2 ? Icons.check_circle_rounded : Icons.info_rounded),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WhereItWent extends StatefulWidget {
  const _WhereItWent({required this.summary, required this.previous});
  final PeriodSummary summary;
  final PeriodSummary previous;

  @override
  State<_WhereItWent> createState() => _WhereItWentState();
}

class _WhereItWentState extends State<_WhereItWent> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final savingIds = store.savingCategoryIds;
    final entries = widget.summary.byCategory.entries
        .where((e) => !savingIds.contains(e.key) && e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = widget.summary.expense;

    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: AppCard(
          child: EmptyState(
            icon: Icons.donut_large_rounded,
            title: 'Belum ada pengeluaran',
            message: 'Grafik muncul setelah ada pengeluaran di periode ini.',
          ),
        ),
      );
    }

    Pos? cat(int id) => store.category(id);
    final surface = context.colors.surfaceContainerLow;
    final touched = _touched >= 0 && _touched < entries.length ? entries[_touched] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          children: [
            SizedBox(
              height: 210,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 64,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, resp) {
                          if (!event.isInterestedForInteractions) return;
                          setState(() => _touched = resp?.touchedSection?.touchedSectionIndex ?? -1);
                        },
                      ),
                      sections: [
                        for (var i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: entries[i].value.toDouble(),
                            color: Color(cat(entries[i].key)?.color ?? 0xFF64748B),
                            radius: i == _touched ? 38 : 32,
                            showTitle: false,
                            borderSide: BorderSide(color: surface, width: 0),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(touched == null ? 'Total keluar' : (cat(touched.key)?.name ?? 'Tanpa pos'),
                          style: context.text.bodySmall),
                      Money(touched?.value ?? total, compact: true, style: context.text.titleLarge),
                      if (touched != null)
                        Text(percent(touched.value / total), style: context.text.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < entries.length; i++)
              _LegendRow(
                pos: cat(entries[i].key),
                amount: entries[i].value,
                share: entries[i].value / total,
                previous: widget.previous.byCategory[entries[i].key] ?? 0,
                highlighted: i == _touched,
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.pos,
    required this.amount,
    required this.share,
    required this.previous,
    required this.highlighted,
  });

  final Pos? pos;
  final int amount;
  final double share;
  final int previous;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget? delta;
    if (previous > 0) {
      final d = (amount - previous) / previous;
      if (d.abs() >= 0.05) {
        final up = d > 0;
        delta = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 13, color: up ? p.expense : p.income),
          Text('${(d.abs() * 100).round()}%',
              style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        ]);
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: highlighted ? context.colors.surfaceContainer : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: Color(pos?.color ?? 0xFF64748B), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(pos?.name ?? 'Tanpa pos',
                style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (delta != null) ...[delta, const SizedBox(width: 10)],
          SizedBox(
            width: 38,
            child: Text(percent(share), style: context.text.bodySmall, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 10),
          Money(amount, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.summary, required this.categories, required this.now});
  final PeriodSummary summary;
  final List<Pos> categories;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final days = summary.period.days;
    final budget = periodBudgetFor(summary, categories);
    final avgAllowance = budget > 0 ? budget / days.length : 0.0;
    final values = [for (final d in days) summary.spentOn(d)];
    final rawMax = math.max(values.fold(0, math.max).toDouble(), avgAllowance);
    final step = _niceStep(rawMax / 4);
    final maxV = rawMax <= 0 ? 0.0 : (rawMax / step).ceil() * step;
    final p = context.palette;
    final normal = context.colors.primary;
    final muted = p.muted;
    final today = dateOnly(now);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _Key(color: normal, label: 'Dalam batas'),
                  _Key(color: p.expense, label: 'Lewat rata-rata jatah', icon: Icons.priority_high_rounded),
                  if (avgAllowance > 0) _Key(color: muted, label: 'Jatah rata-rata/hari', line: true),
                ],
              ),
            ),
            SizedBox(
              height: 190,
              child: maxV <= 0
                  ? Center(child: Text('Belum ada pengeluaran', style: context.text.bodySmall))
                  : BarChart(
                      BarChartData(
                        maxY: maxV,
                        alignment: BarChartAlignment.spaceBetween,
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval: step,
                          getDrawingHorizontalLine: (_) =>
                              FlLine(color: p.border, strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: false),
                        extraLinesData: ExtraLinesData(horizontalLines: [
                          if (avgAllowance > 0)
                            HorizontalLine(y: avgAllowance, color: muted, strokeWidth: 1.5, dashArray: [4, 4]),
                        ]),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                              interval: step,
                              getTitlesWidget: (v, meta) => SideTitleWidget(
                                      meta: meta,
                                      child: Text(compactRupiah(v.round()),
                                          style: TextStyle(fontSize: 10, color: muted)),
                                    ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              getTitlesWidget: (v, meta) {
                                final i = v.toInt();
                                if (i % 5 != 0 && i != days.length - 1) return const SizedBox.shrink();
                                return SideTitleWidget(
                                  meta: meta,
                                  child: Text('${days[i].day}', style: TextStyle(fontSize: 10, color: muted)),
                                );
                              },
                            ),
                          ),
                        ),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => context.colors.inverseSurface,
                            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                              '${fmtDayMonth(days[group.x])}\n${rupiah(rod.toY.round())}',
                              TextStyle(
                                color: context.colors.onInverseSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < days.length; i++)
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: values[i].toDouble(),
                                width: math.max(3, 200 / days.length),
                                color: avgAllowance > 0 && values[i] > avgAllowance
                                    ? p.expense
                                    : (days[i].isAfter(today) ? muted : normal),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ]),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interval sumbu yang "bulat": 1, 2, 2,5, atau 5 × 10^n.
double _niceStep(double raw) {
  if (raw <= 0) return 1;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (raw <= m * mag) return m * mag;
  }
  return 10 * mag;
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, this.line = false, this.icon});
  final Color color;
  final String label;
  final bool line;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          line
              ? Container(width: 14, height: 2, color: color)
              : Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                ),
          const SizedBox(width: 6),
          Text(label, style: context.text.bodySmall),
        ],
      );
}

class _Insights extends StatelessWidget {
  const _Insights({required this.summary, required this.previous, required this.now});
  final PeriodSummary summary;
  final PeriodSummary previous;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final dailyTotal = s.daily.values.fold(0, (a, b) => a + b);
    if (dailyTotal <= 0) return const SizedBox.shrink();
    final p = context.palette;
    final elapsed = s.period.contains(now) ? s.period.dayIndex(now) : s.period.totalDays;
    final avg = dailyTotal ~/ math.max(1, elapsed);
    final worst = s.daily.entries.reduce((a, b) => a.value >= b.value ? a : b);

    // Bandingkan dengan periode lalu pada hari yang sama (adil untuk periode berjalan).
    var prevSameDays = 0;
    previous.daily.forEach((d, v) {
      if (previous.period.dayIndex(d) <= elapsed) prevSameDays += v;
    });

    final items = <(IconData, Color, String)>[
      (Icons.calendar_view_day_rounded, context.colors.primary, 'Rata-rata pengeluaran harian ${rupiah(avg)} per hari'),
      (Icons.local_fire_department_rounded, p.expense,
          'Paling boros: ${fmtRelativeDay(worst.key, now: now)} (${rupiah(worst.value)})'),
      if (prevSameDays > 0)
        () {
          final d = (dailyTotal - prevSameDays) / prevSameDays;
          final up = d > 0;
          return (
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            up ? p.expense : p.income,
            '${up ? 'Naik' : 'Turun'} ${(d.abs() * 100).round()}% dibanding periode lalu '
                '(di $elapsed hari pertama)'
          );
        }(),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            for (final (icon, color, text) in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: context.text.bodyMedium)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _IncomeList extends StatelessWidget {
  const _IncomeList({required this.summary});
  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final entries = summary.incomeByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final e in entries)
              ListTile(
                leading: IconBadge(
                    icon: store.category(e.key)?.icon ?? 'category',
                    color: store.category(e.key)?.color ?? 0xFF64748B,
                    size: 36),
                title: Text(store.category(e.key)?.name ?? 'Tanpa sumber'),
                subtitle: Text(percent(e.value / summary.income)),
                trailing: Money(e.value,
                    color: context.palette.income, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopExpenses extends StatelessWidget {
  const _TopExpenses({required this.period});
  final PayPeriod period;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final saving = store.savingCategoryIds;
    final list = store.transactions
        .where((t) => t.type == TxnType.expense && period.contains(t.date) && !saving.contains(t.categoryId))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Belum ada pengeluaran.', style: context.text.bodySmall),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [for (final t in list.take(5)) TxnTile(t, showDate: true)]),
      ),
    );
  }
}
