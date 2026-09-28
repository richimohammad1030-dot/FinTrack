// Beranda: jatah aman hari ini, ringkasan periode, pos yang perlu diwaspadai,
// target tabungan, tagihan jatuh tempo, dan transaksi terakhir.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../logic/budget.dart';
import '../../logic/period.dart';
import '../../state/finance_store.dart';
import '../../state/settings.dart';
import '../budget/budget_screen.dart';
import '../debt/debt_screen.dart';
import '../more/goals_screen.dart';
import '../more/recurring_screen.dart';
import '../more/settings_screen.dart';
import '../txn/txn_form.dart';
import '../txn/txn_tile.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  /// Pindah ke tab lain di navigasi bawah.
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final settings = context.watch<Settings>();
    final period = store.currentPeriod;
    final summary = store.currentSummary;
    final recent = store.transactions.take(6).toList();
    final warnings = store.warnings;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    const KaitLogo(size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_greeting(store.now), style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                          const SizedBox(height: 2),
                          Text(fmtPeriod(period),
                              style: context.text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Scan struk',
                      onPressed: () => openTxnForm(context, scan: true),
                      icon: const Icon(Icons.document_scanner_rounded),
                    ),
                    IconButton(
                      tooltip: settings.hideAmounts ? 'Tampilkan nominal' : 'Sembunyikan nominal',
                      onPressed: () => settings.hideAmounts = !settings.hideAmounts,
                      icon: Icon(settings.hideAmounts ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    ),
                    IconButton(
                      tooltip: 'Pengaturan',
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      icon: const Icon(Icons.settings_rounded),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _TodayCard(budget: store.dailyBudget, period: period, now: store.now)),
            SliverToBoxAdapter(child: _PeriodStats(summary: summary)),
            if (store.pendingRecurring.isNotEmpty)
              SliverToBoxAdapter(child: _DueBills(items: store.pendingRecurring)),
            if (warnings.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader('Perlu diwaspadai')),
              SliverList.list(children: [for (final w in warnings.take(3)) _WarningTile(status: w)]),
            ],
            SliverToBoxAdapter(
              child: SectionHeader('Pos anggaran', action: 'Semua', onAction: () => onOpenTab(2)),
            ),
            SliverToBoxAdapter(child: _PosOverview(statuses: store.currentStatuses)),
            if (store.activeDebts.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader('Hutang & piutang', action: 'Kelola', onAction: () => openDebts(context)),
              ),
              SliverToBoxAdapter(child: _DebtSummary(store: store)),
            ],
            if (store.activeGoals.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader('Target tabungan',
                    action: 'Kelola',
                    onAction: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen()))),
              ),
              SliverToBoxAdapter(child: _GoalsStrip(goals: store.activeGoals)),
            ],
            SliverToBoxAdapter(
              child: SectionHeader('Transaksi terakhir', action: 'Riwayat', onAction: () => onOpenTab(1)),
            ),
            if (recent.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'Belum ada transaksi',
                  message: 'Tekan tombol + di bawah untuk mencatat pengeluaran pertamamu.',
                ),
              )
            else
              SliverList.list(children: [for (final t in recent) DismissibleTxnTile(t, showDate: true)]),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  static String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 11) return 'Selamat pagi 👋';
    if (h < 15) return 'Selamat siang 👋';
    if (h < 18) return 'Selamat sore 👋';
    return 'Selamat malam 👋';
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.budget, required this.period, required this.now});

  final DailyBudget budget;
  final PayPeriod period;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final over = budget.remainingToday < 0;
    final noBudget = budget.periodBudget <= 0 && !budget.isManual;
    final usedUp = !noBudget && budget.allowance <= 0;
    final onHero = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.78);
    final daysToPayday = period.daysLeft(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: over
                ? [const Color(0xFF9F1239), const Color(0xFFE11D48)]
                : [p.heroStart, p.heroEnd],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(over ? Icons.local_fire_department_rounded : Icons.shield_moon_rounded,
                    color: muted, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    over ? 'Hari ini sudah lewat batas' : 'Aman dipakai hari ini',
                    style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    daysToPayday <= 1 ? 'Besok gajian 🎉' : '$daysToPayday hari lagi gajian',
                    style: TextStyle(color: onHero, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (noBudget)
              Text('Atur pos anggaran dulu',
                  style: context.text.headlineSmall?.copyWith(color: onHero))
            else
              Money(
                over ? -budget.remainingToday : budget.remainingToday,
                style: context.text.displaySmall?.copyWith(color: onHero, fontSize: 36),
              ),
            const SizedBox(height: 14),
            Bar(
              ratio: budget.ratio,
              color: over ? Colors.white : const Color(0xFF3DDC97),
              background: Colors.white.withValues(alpha: 0.22),
              height: 8,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _HeroFigure(
                    label: 'Terpakai hari ini',
                    child: Money(budget.spentToday,
                        style: TextStyle(color: onHero, fontWeight: FontWeight.w700)),
                  ),
                ),
                Expanded(
                  child: _HeroFigure(
                    label: budget.isManual ? 'Batas harian (manual)' : 'Batas harian',
                    child: Money(budget.allowance,
                        style: TextStyle(color: onHero, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            if (noBudget) ...[
              const SizedBox(height: 12),
              Text(
                'Batas harian dihitung dari total pos anggaran dibagi sisa hari sampai gajian. '
                'Buka tab Pos → Bagi Gaji.',
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
            ] else if (usedUp) ...[
              const SizedBox(height: 12),
              Text(
                'Anggaran periode ini sudah habis. Tahan pengeluaran sampai gajian, '
                'atau sesuaikan pembagian di tab Pos.',
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
            ] else if (over) ...[
              const SizedBox(height: 12),
              Text(
                'Kelebihan ${rupiah(-budget.remainingToday)} akan mengurangi jatah hari-hari berikutnya.',
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 2),
          child,
        ],
      );
}

class _PeriodStats extends StatelessWidget {
  const _PeriodStats({required this.summary});
  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget stat(String label, int v, Color c, IconData icon) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 15, color: c),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(label,
                        style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 6),
                Money(v, compact: true, style: context.text.titleMedium, color: c),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          stat('Masuk', summary.income, p.income, Icons.south_west_rounded),
          const SizedBox(width: 8),
          stat('Keluar', summary.expense, p.expense, Icons.north_east_rounded),
          const SizedBox(width: 8),
          stat('Ditabung', summary.saving, p.saving, Icons.savings_rounded),
        ],
      ),
    );
  }
}

class _DueBills extends StatelessWidget {
  const _DueBills({required this.items});
  final List<Recurring> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AppCard(
        color: context.palette.warning.withValues(alpha: 0.10),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.notifications_active_rounded, color: context.palette.warning, size: 20),
              const SizedBox(width: 8),
              Text('Tagihan jatuh tempo', style: context.text.titleSmall),
            ]),
            for (final r in items)
              Row(
                children: [
                  Expanded(
                    child: Text('${r.title} · ${rupiah(r.amount)}',
                        style: context.text.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    onPressed: () => confirmRecurringDialog(context, r),
                    child: const Text('Bayar'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _WarningTile extends StatelessWidget {
  const _WarningTile({required this.status});
  final PosStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.category;
    final color = levelColor(context, status.level);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AppCard(
        onTap: () => openPosDetail(context, c),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconBadge(icon: c.icon, color: c.color, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    status.remaining >= 0
                        ? 'Sisa ${rupiah(status.remaining)} untuk ${status.daysLeft} hari'
                        : 'Lewat ${rupiah(-status.remaining)} dari batas',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            Pill(
              status.level == BudgetLevel.over ? 'Habis' : percent(status.ratio),
              color: color,
              icon: status.level == BudgetLevel.over ? Icons.error_rounded : Icons.warning_amber_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _PosOverview extends StatelessWidget {
  const _PosOverview({required this.statuses});
  final List<PosStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final withLimit = statuses.where((s) => s.limit > 0 || s.spent > 0).toList()
      ..sort((a, b) => b.spent.compareTo(a.spent));
    if (withLimit.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppCard(
          onTap: () => openAllocate(context),
          child: Row(
            children: [
              Icon(Icons.pie_chart_rounded, color: context.colors.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Bagi gajimu ke pos-pos supaya tahu uang lari ke mana.'),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            for (final s in withLimit.take(5)) _PosRow(status: s),
          ],
        ),
      ),
    );
  }
}

class _PosRow extends StatelessWidget {
  const _PosRow({required this.status});
  final PosStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.category;
    final color = c.isSaving ? context.palette.saving : levelColor(context, status.level, normal: Color(c.color));
    return InkWell(
      onTap: () => openPosDetail(context, c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            IconBadge(icon: c.icon, color: c.color, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(c.name,
                            style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Money(status.spent, compact: true, style: context.text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700, color: context.colors.onSurface)),
                      if (status.limit > 0)
                        Text(' / ${compactRupiah(status.limit)}', style: context.text.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Bar(ratio: status.limit > 0 ? status.ratio : 0, color: color, height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtSummary extends StatelessWidget {
  const _DebtSummary({required this.store});
  final FinanceStore store;

  @override
  Widget build(BuildContext context) {
    final due = store.dueSoonDebts();
    Widget fig(String label, int v, Color c) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.bodySmall),
              const SizedBox(height: 2),
              Money(v, style: context.text.titleMedium, color: v > 0 ? c : null),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          AppCard(
            onTap: () => openDebts(context),
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              fig('Sisa hutang saya', store.totalPayable, debtColor(context, DebtKind.payable)),
              fig('Piutang belum kembali', store.totalReceivable, debtColor(context, DebtKind.receivable)),
            ]),
          ),
          for (final s in due.take(2))
            Padding(padding: const EdgeInsets.only(top: 8), child: DebtCard(status: s, compact: true)),
        ],
      ),
    );
  }
}

class _GoalsStrip extends StatelessWidget {
  const _GoalsStrip({required this.goals});
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    return SizedBox(
      height: 132,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: goals.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final g = goals[i];
          final saved = store.goalSaved(g.id!);
          final r = g.target <= 0 ? 0.0 : saved / g.target;
          return SizedBox(
            width: 200,
            child: AppCard(
              onTap: () => openGoalDetail(context, g),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    IconBadge(icon: g.icon, color: g.color, size: 32),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(g.name,
                          style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  const Spacer(),
                  Money(saved, compact: true, style: context.text.titleMedium),
                  Text('dari ${compactRupiah(g.target)} · ${percent(r.clamp(0, 1))}',
                      style: context.text.bodySmall),
                  const SizedBox(height: 8),
                  Bar(ratio: r, color: Color(g.color), height: 6),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Dialog bayar tagihan rutin (mode "ingatkan saja"): konfirmasi nominal aktual.
Future<void> confirmRecurringDialog(BuildContext context, Recurring r) async {
  final store = context.read<FinanceStore>();
  final result = await showDialog<(String, int)>(
    context: context,
    builder: (_) => _PayBillDialog(r: r),
  );
  if (!context.mounted || result == null) return;
  final (action, amount) = result;
  if (action == 'skip') {
    await store.skipRecurring(r);
  } else if (action == 'pay' && amount > 0) {
    final alerts = await store.confirmRecurring(r, amount);
    if (!context.mounted) return;
    if (alerts.isNotEmpty) {
      await showAlertsSheet(context, alerts);
    } else {
      toast(context, '${r.title} tercatat ✓');
    }
  }
}

class _PayBillDialog extends StatefulWidget {
  const _PayBillDialog({required this.r});
  final Recurring r;

  @override
  State<_PayBillDialog> createState() => _PayBillDialogState();
}

class _PayBillDialogState extends State<_PayBillDialog> {
  late final _ctrl = TextEditingController(text: groupDigits(widget.r.amount));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.r.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Catat pembayaran bulan ini. Ubah nominal kalau berbeda.', style: context.text.bodyMedium),
          const SizedBox(height: 16),
          MoneyField(controller: _ctrl, autofocus: true),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, ('skip', 0)), child: const Text('Lewati bulan ini')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(context, ('pay', parseDigits(_ctrl.text))),
          child: const Text('Catat'),
        ),
      ],
    );
  }
}

/// Buka daftar transaksi rutin (dipakai dari beberapa tempat).
void openRecurring(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurringScreen()));

/// Tombol cepat untuk mencatat (dipakai FAB di shell).
Future<void> quickAdd(BuildContext context) => openTxnForm(context);
