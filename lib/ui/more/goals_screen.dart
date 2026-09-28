// Target tabungan: dana darurat, liburan, DP rumah, dll.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../logic/period.dart';
import '../../state/finance_store.dart';
import '../txn/txn_form.dart';
import '../txn/txn_tile.dart';
import '../widgets/common.dart';

void openGoalDetail(BuildContext context, Goal g) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => GoalDetailScreen(goalId: g.id!)));

/// Setor ke target: buka form pengeluaran ke pos tabungan dengan target terpilih.
Future<void> depositToGoal(BuildContext context, Goal g) async {
  final saving = context.read<FinanceStore>().savingCategory;
  if (saving == null) {
    toast(context, 'Buat pos tabungan dulu di tab Pos (aktifkan "Ini pos tabungan").');
    return;
  }
  await openTxnForm(context, type: TxnType.expense, categoryId: saving.id, goalId: g.id);
}

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final goals = store.goals;
    return Scaffold(
      appBar: AppBar(title: const Text('Target Tabungan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showGoalEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Target baru'),
      ),
      body: goals.isEmpty
          ? const EmptyState(
              icon: Icons.flag_rounded,
              title: 'Belum ada target',
              message: 'Buat target seperti "Dana darurat 3× gaji" atau "Liburan akhir tahun", '
                  'lalu setor sedikit demi sedikit setiap gajian.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                for (final g in goals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GoalCard(goal: g),
                  ),
              ],
            ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FinanceStore>();
    final saved = store.goalSaved(goal.id!);
    final r = goal.target <= 0 ? 0.0 : saved / goal.target;
    final plan = _monthlyNeed(goal, saved, store.now);
    return Opacity(
      opacity: goal.archived ? 0.55 : 1,
      child: AppCard(
        onTap: () => openGoalDetail(context, goal),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconBadge(icon: goal.icon, color: goal.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal.name, style: context.text.titleSmall),
                    Text(
                      goal.deadline == null ? 'Tanpa tenggat' : 'Tenggat ${fmtDate(goal.deadline!)}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (r >= 1) Pill('Tercapai', color: context.palette.income, icon: Icons.check_circle_rounded),
            ]),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Money(saved, style: context.text.titleLarge),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('/ ${rupiah(goal.target)}', style: context.text.bodySmall),
                ),
                const Spacer(),
                Text(percent(r.clamp(0, 1)), style: context.text.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Bar(ratio: r, color: Color(goal.color), height: 8),
            if (plan != null) ...[
              const SizedBox(height: 8),
              Text(plan, style: context.text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Setor ±Rp X per bulan supaya tercapai tepat waktu".
String? _monthlyNeed(Goal g, int saved, DateTime now) {
  final left = g.target - saved;
  if (left <= 0 || g.deadline == null) return null;
  final months = math.max(1, (daysBetween(now, g.deadline!) / 30).ceil());
  if (daysBetween(now, g.deadline!) < 0) return 'Tenggat sudah lewat · kurang ${rupiah(left)}';
  return 'Setor ±${rupiah((left / months).ceil())}/bulan supaya tercapai tepat waktu';
}

class GoalDetailScreen extends StatelessWidget {
  const GoalDetailScreen({super.key, required this.goalId});
  final int goalId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final g = store.goal(goalId);
    if (g == null) return const Scaffold();
    final txns = store.transactions.where((t) => t.goalId == goalId).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(g.name),
        actions: [
          IconButton(
            tooltip: 'Ubah',
            onPressed: () => showGoalEditor(context, edit: g),
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => depositToGoal(context, g),
        icon: const Icon(Icons.savings_rounded),
        label: const Text('Setor'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: _GoalCard(goal: g)),
          const SectionHeader('Riwayat setoran'),
          if (txns.isEmpty)
            const EmptyState(icon: Icons.savings_rounded, title: 'Belum ada setoran')
          else
            for (final t in txns) DismissibleTxnTile(t, showDate: true),
        ],
      ),
    );
  }
}

Future<void> showGoalEditor(BuildContext context, {Goal? edit}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GoalEditor(edit: edit),
  );
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({this.edit});
  final Goal? edit;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _target;
  late String _icon;
  late int _color;
  DateTime? _deadline;
  late bool _archived;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _name = TextEditingController(text: e?.name ?? '');
    _target = TextEditingController(text: e == null ? '' : groupDigits(e.target));
    _icon = e?.icon ?? 'emergency';
    _color = e?.color ?? 0xFF4A3AA7;
    _deadline = e?.deadline;
    _archived = e?.archived ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final e = widget.edit;
    await context.read<FinanceStore>().saveGoal(Goal(
          id: e?.id,
          name: _name.text.trim(),
          target: parseDigits(_target.text),
          icon: _icon,
          color: _color,
          deadline: _deadline,
          archived: _archived,
          createdAt: e?.createdAt,
        ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final store = context.read<FinanceStore>();
    final nav = Navigator.of(context);
    final ok = await confirm(context,
        title: 'Hapus target "${widget.edit!.name}"?',
        message: 'Setoran yang sudah tercatat tetap ada di pos Tabungan.',
        ok: 'Hapus',
        destructive: true);
    if (!ok) return;
    await store.deleteGoal(widget.edit!.id!);
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
                Row(children: [
                  IconBadge(icon: _icon, color: _color, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.edit == null ? 'Target baru' : 'Ubah target',
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
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nama target', hintText: 'mis. Dana darurat'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Isi nama target' : null,
                ),
                const SizedBox(height: 12),
                MoneyField(controller: _target, label: 'Jumlah target', validator: requiredAmount),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: Text(_deadline == null ? 'Tanpa tenggat' : 'Tenggat ${fmtDate(_deadline!)}'),
                  trailing: _deadline == null
                      ? const Icon(Icons.chevron_right_rounded)
                      : IconButton(
                          tooltip: 'Hapus tenggat',
                          onPressed: () => setState(() => _deadline = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  onTap: () async {
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final first = _deadline != null && _deadline!.isBefore(today) ? _deadline! : today;
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _deadline ?? DateTime(now.year + 1, now.month, now.day),
                      firstDate: first,
                      lastDate: DateTime(now.year + 30),
                    );
                    if (d != null) setState(() => _deadline = d);
                  },
                ),
                if (widget.edit != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Arsipkan'),
                    subtitle: const Text('Sembunyikan dari beranda & pilihan setoran'),
                    value: _archived,
                    onChanged: (v) => setState(() => _archived = v),
                  ),
                const SizedBox(height: 8),
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
