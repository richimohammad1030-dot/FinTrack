// Laporan harian: kalender pengeluaran per hari + rincian hari yang dipilih.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../logic/daily_report.dart';
import '../../logic/period.dart';
import '../../state/finance_store.dart';
import '../txn/txn_tile.dart';
import '../widgets/common.dart';
import '../widgets/period_switcher.dart';

/// Halaman berdiri sendiri (dibuka dari Riwayat / rincian batas harian).
class DailyCalendarPage extends StatefulWidget {
  const DailyCalendarPage({super.key});

  @override
  State<DailyCalendarPage> createState() => _DailyCalendarPageState();
}

class _DailyCalendarPageState extends State<DailyCalendarPage> {
  PayPeriod? _period;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final p0 = _period;
    final period = p0 != null && p0.payday == store.settings.payday ? p0 : store.currentPeriod;
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Harian')),
      body: Column(
        children: [
          PeriodSwitcher(period: period, current: store.currentPeriod, onChanged: (p) => setState(() => _period = p)),
          Expanded(child: DailyCalendarTab(period: period)),
        ],
      ),
    );
  }
}

Color dayStatusColor(BuildContext context, DayStatus s) => switch (s) {
      DayStatus.ok => context.palette.income,
      DayStatus.near => context.palette.warning,
      DayStatus.over => context.palette.expense,
      DayStatus.zero => context.palette.muted,
      DayStatus.future => context.palette.muted,
    };

String dayStatusLabel(DayStatus s) => switch (s) {
      DayStatus.ok => 'Aman',
      DayStatus.near => 'Hampir batas',
      DayStatus.over => 'Lewat jatah',
      DayStatus.zero => 'Tanpa pengeluaran',
      DayStatus.future => 'Belum terjadi',
    };

IconData dayStatusIcon(DayStatus s) => switch (s) {
      DayStatus.ok => Icons.check_circle_rounded,
      DayStatus.near => Icons.warning_amber_rounded,
      DayStatus.over => Icons.error_rounded,
      DayStatus.zero => Icons.savings_rounded,
      DayStatus.future => Icons.schedule_rounded,
    };

class DailyCalendarTab extends StatefulWidget {
  const DailyCalendarTab({super.key, required this.period});
  final PayPeriod period;

  @override
  State<DailyCalendarTab> createState() => _DailyCalendarTabState();
}

class _DailyCalendarTabState extends State<DailyCalendarTab> {
  DateTime? _selected;

  /// true = hanya pos harian (sesuai jatah), false = semua pengeluaran.
  bool _dailyOnly = true;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final report = store.dailyReportFor(widget.period);
    final today = dateOnly(store.now);
    var sel = _selected;
    if (sel == null || !widget.period.contains(sel)) {
      sel = widget.period.contains(today) ? today : widget.period.lastDay;
    }
    final day = report.dayOf(sel)!;
    final pastDays = report.past.toList().reversed.toList();

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _Stats(report: report, dailyOnly: _dailyOnly),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Pos harian')),
                ButtonSegment(value: false, label: Text('Semua pengeluaran')),
              ],
              selected: {_dailyOnly},
              onSelectionChanged: (v) => setState(() => _dailyOnly = v.first),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
            child: Column(
              children: [
                _CalendarGrid(
                  report: report,
                  selected: sel,
                  today: today,
                  dailyOnly: _dailyOnly,
                  onSelect: (d) => setState(() => _selected = d),
                ),
                const SizedBox(height: 12),
                _Legend(dailyOnly: _dailyOnly),
              ],
            ),
          ),
        ),
        _DayDetail(day: day, today: today),
        if (pastDays.isNotEmpty) ...[
          const SectionHeader('Rincian semua hari'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final d in pastDays)
                    _DayRow(
                      day: d,
                      dailyOnly: _dailyOnly,
                      selected: d.day == sel,
                      onTap: () {
                        setState(() => _selected = d.day);
                        _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.report, required this.dailyOnly});
  final PeriodDailyReport report;
  final bool dailyOnly;

  @override
  Widget build(BuildContext context) {
    final total = dailyOnly ? report.totalDaily : report.totalAll;
    final avg = report.elapsedDays == 0 ? 0 : total ~/ report.elapsedDays;
    Widget tile(String label, Widget value) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                value,
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          tile('Total', Money(total, compact: true, style: context.text.titleMedium)),
          const SizedBox(width: 8),
          tile('Rata-rata/hari', Money(avg, compact: true, style: context.text.titleMedium)),
          const SizedBox(width: 8),
          tile(
            'Lewat jatah',
            Text('${report.overDays} dari ${report.elapsedDays} hari',
                style: context.text.titleSmall?.copyWith(
                    color: report.overDays > 0 ? context.palette.expense : context.palette.income)),
          ),
        ],
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.report,
    required this.selected,
    required this.today,
    required this.dailyOnly,
    required this.onSelect,
  });

  final PeriodDailyReport report;
  final DateTime selected;
  final DateTime today;
  final bool dailyOnly;
  final ValueChanged<DateTime> onSelect;

  static const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  @override
  Widget build(BuildContext context) {
    final days = report.days;
    final lead = days.first.day.weekday - 1; // Senin = 0
    final cells = <DayReport?>[...List.filled(lead, null), ...days];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final maxAll = days.fold(0, (m, d) => d.allSpent > m ? d.allSpent : m);

    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Center(child: Text(w, style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < cells.length ~/ 7; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: cells[r * 7 + c] == null
                      ? const SizedBox(height: 58)
                      : _Cell(
                          day: cells[r * 7 + c]!,
                          selected: cells[r * 7 + c]!.day == selected,
                          isToday: cells[r * 7 + c]!.day == today,
                          dailyOnly: dailyOnly,
                          maxAll: maxAll,
                          onTap: () => onSelect(cells[r * 7 + c]!.day),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.dailyOnly,
    required this.maxAll,
    required this.onTap,
  });

  final DayReport day;
  final bool selected;
  final bool isToday;
  final bool dailyOnly;
  final int maxAll;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final future = day.status == DayStatus.future;
    final amount = dailyOnly ? day.dailySpent : day.allSpent;
    Color bg;
    if (future) {
      bg = Colors.transparent;
    } else if (dailyOnly) {
      bg = day.status == DayStatus.zero
          ? context.colors.onSurface.withValues(alpha: 0.04)
          : dayStatusColor(context, day.status).withValues(alpha: 0.16);
    } else {
      final r = maxAll == 0 ? 0.0 : amount / maxAll;
      bg = context.colors.primary.withValues(alpha: amount == 0 ? 0.04 : 0.08 + 0.32 * r);
    }
    final label = day.day.day == 1 ? '1 ${fmtMonthShort(day.day)}' : '${day.day.day}';

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 54,
            padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? context.colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                            color: future ? context.palette.muted : context.colors.onSurface,
                          )),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 3),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                if (!future)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      amount == 0 ? '–' : compactRupiah(amount),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.colors.onSurface.withValues(alpha: amount == 0 ? 0.4 : 0.9),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.dailyOnly});
  final bool dailyOnly;

  @override
  Widget build(BuildContext context) {
    if (!dailyOnly) {
      return Text('Makin pekat warnanya, makin besar pengeluaran hari itu (termasuk pos bulanan).',
          style: context.text.bodySmall, textAlign: TextAlign.center);
    }
    Widget item(DayStatus s, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(dayStatusIcon(s), size: 14, color: dayStatusColor(context, s)),
            const SizedBox(width: 4),
            Text(text, style: context.text.bodySmall),
          ],
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        item(DayStatus.ok, 'Aman (<80%)'),
        item(DayStatus.near, 'Hampir (80–100%)'),
        item(DayStatus.over, 'Lewat jatah'),
        item(DayStatus.zero, 'Rp 0'),
      ],
    );
  }
}

class _DayDetail extends StatelessWidget {
  const _DayDetail({required this.day, required this.today});
  final DayReport day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final color = dayStatusColor(context, day.status);
    final future = day.status == DayStatus.future;
    final cats = day.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final catTotal = cats.fold(0, (a, e) => a + e.value);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(fmtRelativeDay(day.day, now: today), style: context.text.titleMedium)),
                Pill(dayStatusLabel(day.status), color: color, icon: dayStatusIcon(day.status)),
              ],
            ),
            if (day.day != today && fmtRelativeDay(day.day, now: today) != fmtFullDate(day.day))
              Text(fmtFullDate(day.day), style: context.text.bodySmall),
            const SizedBox(height: 14),
            if (future)
              Text('Jatah untuk hari ini akan dihitung saat harinya tiba.', style: context.text.bodyMedium)
            else ...[
              Row(
                children: [
                  Expanded(child: _Fig('Terpakai (pos harian)', day.dailySpent, color: context.colors.onSurface)),
                  Expanded(child: _Fig('Jatah hari itu', day.allowance)),
                ],
              ),
              const SizedBox(height: 10),
              Bar(
                ratio: day.allowance <= 0 ? (day.dailySpent > 0 ? 1 : 0) : day.dailySpent / day.allowance,
                color: day.status == DayStatus.zero ? context.palette.income : color,
                height: 8,
              ),
              const SizedBox(height: 8),
              Text(
                day.remaining >= 0
                    ? 'Sisa ${rupiah(day.remaining)} dari jatah hari itu'
                    : 'Lewat ${rupiah(-day.remaining)} dari jatah hari itu',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _Fig('Semua keluar', day.allSpent)),
                  Expanded(child: _Fig('Ditabung', day.saved, color: context.palette.saving)),
                  Expanded(child: _Fig('Masuk', day.income, color: context.palette.income)),
                ],
              ),
            ],
            if (cats.isNotEmpty) ...[
              const Divider(height: 28),
              Text('Per pos', style: context.text.labelLarge),
              const SizedBox(height: 8),
              for (final e in cats)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      IconBadge(
                        icon: store.category(e.key)?.icon ?? 'category',
                        color: store.category(e.key)?.color ?? 0xFF64748B,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    [
                                      store.category(e.key)?.name ?? 'Tanpa pos',
                                      if (store.category(e.key)?.isDaily == false &&
                                          store.category(e.key)?.isSaving == false)
                                        '(bulanan)',
                                    ].join(' '),
                                    style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Money(e.value, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Bar(
                              ratio: catTotal == 0 ? 0 : e.value / catTotal,
                              color: Color(store.category(e.key)?.color ?? 0xFF64748B),
                              height: 5,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (day.txns.isNotEmpty) ...[
              const Divider(height: 20),
              Text('Transaksi (${day.txns.length})', style: context.text.labelLarge),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    ).withTxns(context, day);
  }
}

extension on Widget {
  /// Daftar transaksi di bawah kartu rincian hari.
  Widget withTxns(BuildContext context, DayReport day) {
    if (day.txns.isEmpty) return this;
    return Column(
      children: [
        this,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            margin: const EdgeInsets.only(top: 8),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [for (final t in day.txns) TxnTile(t)]),
          ),
        ),
      ],
    );
  }
}

class _Fig extends StatelessWidget {
  const _Fig(this.label, this.value, {this.color});
  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Money(value, style: context.text.titleSmall, color: color),
        ],
      );
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.dailyOnly, required this.selected, required this.onTap});
  final DayReport day;
  final bool dailyOnly;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amount = dailyOnly ? day.dailySpent : day.allSpent;
    final color = dayStatusColor(context, day.status);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? context.colors.primary.withValues(alpha: 0.06) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(fmtWeekdayShort(day.day),
                  style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Icon(dayStatusIcon(day.status), size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: dailyOnly
                  ? Bar(
                      ratio: day.allowance <= 0 ? (amount > 0 ? 1 : 0) : amount / day.allowance,
                      color: day.status == DayStatus.zero ? context.palette.income : color,
                      height: 6,
                    )
                  : Text('${day.txns.length} transaksi', style: context.text.bodySmall),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: Align(
                alignment: Alignment.centerRight,
                child: Money(amount, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
