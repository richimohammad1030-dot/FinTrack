// Editor "Bagi Gaji": isi gaji, lalu bagi ke setiap pos.
// Dipakai di layar Bagi Gaji dan di onboarding.

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/seed.dart';
import '../widgets/common.dart';

class AllocationEditor extends StatefulWidget {
  const AllocationEditor({
    super.key,
    required this.categories,
    required this.income,
    required this.limits,
    required this.onChanged,
    this.shrinkWrap = false,
  });

  final List<Pos> categories;
  final int income;
  final Map<int, int> limits;
  final void Function(int income, Map<int, int> limits) onChanged;
  final bool shrinkWrap;

  @override
  State<AllocationEditor> createState() => AllocationEditorState();
}

class AllocationEditorState extends State<AllocationEditor> {
  late final TextEditingController _income;
  late final Map<int, TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _income = TextEditingController(text: widget.income > 0 ? groupDigits(widget.income) : '');
    _ctrls = {
      for (final c in widget.categories)
        c.id!: TextEditingController(
          text: (widget.limits[c.id] ?? 0) > 0 ? groupDigits(widget.limits[c.id]!) : '',
        ),
    };
  }

  @override
  void dispose() {
    _income.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get income => parseDigits(_income.text);
  Map<int, int> get limits => {for (final e in _ctrls.entries) e.key: parseDigits(e.value.text)};
  int get allocated => limits.values.fold(0, (a, b) => a + b);

  void _notify() {
    setState(() {});
    widget.onChanged(income, limits);
  }

  /// Isi otomatis berdasarkan persentase saran, dibulatkan ke 10rb.
  void suggest() {
    final inc = income;
    if (inc <= 0) {
      toast(context, 'Isi perkiraan gaji dulu');
      return;
    }
    final known = widget.categories.where((c) => suggestedSplit.containsKey(c.name)).toList();
    final totalPct = known.fold(0, (s, c) => s + suggestedSplit[c.name]!);
    var used = 0;
    for (final c in widget.categories) {
      final pct = suggestedSplit[c.name];
      if (pct == null) {
        _ctrls[c.id]!.text = '';
        continue;
      }
      var v = (inc * pct / totalPct / 10000).floor() * 10000;
      used += v;
      _ctrls[c.id]!.text = v > 0 ? groupDigits(v) : '';
    }
    // Sisa pembulatan masuk ke tabungan.
    final saving = widget.categories.where((c) => c.isSaving).firstOrNull;
    if (saving != null && inc - used > 0) {
      final cur = parseDigits(_ctrls[saving.id]!.text);
      _ctrls[saving.id]!.text = groupDigits(cur + inc - used);
    }
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final inc = income;
    final alloc = allocated;
    final left = inc - alloc;
    final leftColor = left < 0 ? context.palette.expense : (left == 0 ? context.palette.income : context.palette.warning);

    final children = <Widget>[
      MoneyField(
        controller: _income,
        label: 'Perkiraan gaji / pemasukan per bulan',
        onChanged: (_) => _notify(),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: leftColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    left < 0 ? 'Kelebihan alokasi' : (left == 0 ? 'Semua sudah dibagi 👍' : 'Belum dibagi'),
                    style: context.text.bodySmall,
                  ),
                  Text(rupiah(left.abs()), style: context.text.titleMedium?.copyWith(color: leftColor)),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: suggest,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Saran otomatis'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      for (final c in widget.categories)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              IconBadge(icon: c.icon, color: c.color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      inc > 0 && parseDigits(_ctrls[c.id]!.text) > 0
                          ? '${(parseDigits(_ctrls[c.id]!.text) * 100 / inc).toStringAsFixed(0)}% dari gaji'
                          : (c.isSaving ? 'Sisihkan di awal' : 'Tanpa batas'),
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _ctrls[c.id],
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsInputFormatter()],
                  textAlign: TextAlign.right,
                  onChanged: (_) => _notify(),
                  decoration: const InputDecoration(
                    hintText: '0',
                    prefixText: 'Rp ',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];

    if (widget.shrinkWrap) return Column(children: children);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: children);
  }
}
