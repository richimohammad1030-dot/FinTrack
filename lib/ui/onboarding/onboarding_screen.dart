// Onboarding 4 langkah: gajian → bagi gaji → dompet → keamanan.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/notifications.dart';
import '../../services/security.dart';
import '../../state/finance_store.dart';
import '../../state/settings.dart';
import '../budget/allocation_editor.dart';
import '../lock/pin_pad.dart';
import '../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _step = 0;
  static const _steps = 4;

  late int _payday;
  int _income = 0;
  Map<int, int> _limits = {};
  final _allocKey = GlobalKey<AllocationEditorState>();

  final _cash = TextEditingController();
  final _bankName = TextEditingController(text: 'Rekening Bank');
  final _bank = TextEditingController();
  final _ewalletName = TextEditingController(text: 'E-Wallet');
  final _ewallet = TextEditingController();

  @override
  void initState() {
    super.initState();
    _payday = context.read<Settings>().payday;
  }

  @override
  void dispose() {
    _page.dispose();
    for (final c in [_cash, _bankName, _bank, _ewalletName, _ewallet]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _page.animateToPage(step, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  bool _busy = false;

  Future<void> _finish({bool withPin = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      await _doFinish(withPin: withPin);
    } finally {
      if (mounted) _busy = false;
    }
  }

  Future<void> _doFinish({bool withPin = false}) async {
    final store = context.read<FinanceStore>();
    final settings = context.read<Settings>();
    final notifier = context.read<Notifier>();
    final sec = context.read<SecurityService>();

    if (withPin && !sec.hasPin) {
      final ok = await createPinFlow(context);
      if (!ok) return;
    }

    settings.payday = _payday;
    settings.estimatedIncome = _income;
    if (_limits.isNotEmpty) await store.saveLimits(_limits);

    if (store.activeWallets.isEmpty) {
      final cashId = await store.saveWallet(Wallet(
        name: 'Tunai',
        kind: WalletKind.cash,
        icon: 'cash',
        color: 0xFF1BAF7A,
        initialBalance: parseDigits(_cash.text),
      ));
      settings.lastWalletId = cashId;
      if (parseDigits(_bank.text) > 0 || _bank.text.isNotEmpty) {
        await store.saveWallet(Wallet(
          name: _bankName.text.trim().isEmpty ? 'Rekening Bank' : _bankName.text.trim(),
          kind: WalletKind.bank,
          icon: 'bank',
          color: 0xFF2A78D6,
          initialBalance: parseDigits(_bank.text),
        ));
      }
      if (parseDigits(_ewallet.text) > 0 || _ewallet.text.isNotEmpty) {
        await store.saveWallet(Wallet(
          name: _ewalletName.text.trim().isEmpty ? 'E-Wallet' : _ewalletName.text.trim(),
          kind: WalletKind.ewallet,
          icon: 'phone',
          color: 0xFF4A3AA7,
          initialBalance: parseDigits(_ewallet.text),
        ));
      }
    }

    await notifier.requestPermission();
    if (settings.dailyReminder) await notifier.scheduleDailyReminder(settings.reminderTime);
    settings.onboarded = true;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  for (var i = 0; i < _steps; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i <= _step ? context.colors.primary : context.colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StepPage(
                    emoji: '📅',
                    title: 'Kapan kamu gajian?',
                    body: 'FinTrack menghitung anggaran per periode gajian, bukan per tanggal 1. '
                        'Jadi "sisa uang" dan "jatah harian" selalu sampai gajian berikutnya.',
                    child: _PaydayGrid(value: _payday, onChanged: (d) => setState(() => _payday = d)),
                  ),
                  _StepPage(
                    emoji: '🧺',
                    title: 'Bagi gajimu ke pos-pos',
                    body: 'Sisihkan tabungan di awal, lalu beri jatah tiap kebutuhan. '
                        'Tekan "Saran otomatis" kalau bingung — nanti bisa diubah kapan saja.',
                    child: AllocationEditor(
                      key: _allocKey,
                      shrinkWrap: true,
                      categories: store.expenseCategories,
                      income: _income,
                      limits: _limits,
                      onChanged: (inc, l) {
                        _income = inc;
                        _limits = l;
                      },
                    ),
                  ),
                  _StepPage(
                    emoji: '👛',
                    title: 'Di mana uangmu sekarang?',
                    body: 'Isi saldo saat ini. Boleh dikosongkan dan diatur nanti di menu Dompet.',
                    child: Column(
                      children: [
                        _WalletRow(icon: 'cash', color: 0xFF1BAF7A, label: 'Tunai', amount: _cash),
                        _WalletRow(icon: 'bank', color: 0xFF2A78D6, name: _bankName, amount: _bank),
                        _WalletRow(icon: 'phone', color: 0xFF4A3AA7, name: _ewalletName, amount: _ewallet),
                      ],
                    ),
                  ),
                  const _StepPage(
                    emoji: '🔒',
                    title: 'Lindungi data keuanganmu',
                    body: 'Semua data hanya tersimpan di HP ini, tidak dikirim ke server mana pun. '
                        'Tambahkan PIN supaya orang lain tidak bisa membuka catatanmu.',
                    child: _SecurityPoints(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: _step < _steps - 1
                  ? Row(
                      children: [
                        if (_step > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: IconButton.outlined(
                              tooltip: 'Kembali',
                              onPressed: () => _go(_step - 1),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                          ),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _go(_step + 1),
                            child: Text(_step == 1 && _limits.values.every((v) => v == 0) ? 'Lewati dulu' : 'Lanjut'),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        FilledButton.icon(
                          onPressed: () => _finish(withPin: true),
                          icon: const Icon(Icons.lock_rounded),
                          label: const Text('Buat PIN & mulai'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(onPressed: () => _finish(), child: const Text('Nanti saja, langsung mulai')),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.emoji, required this.title, required this.body, required this.child});
  final String emoji;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(title, style: context.text.headlineSmall),
          const SizedBox(height: 8),
          Text(body, style: context.text.bodyMedium?.copyWith(color: context.palette.muted, height: 1.45)),
          const SizedBox(height: 24),
          child,
        ],
      );
}

class _PaydayGrid extends StatelessWidget {
  const _PaydayGrid({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var d = 1; d <= 31; d++)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: d == value ? context.colors.primary : context.colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$d',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: d == value ? context.colors.onPrimary : context.colors.onSurface,
                      )),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Gajian tanggal $value → periode $value s/d ${value == 1 ? 'akhir bulan' : '${value - 1} bulan berikutnya'}',
            style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({required this.icon, required this.color, this.label, this.name, required this.amount});
  final String icon;
  final int color;
  final String? label;
  final TextEditingController? name;
  final TextEditingController amount;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: name == null
                  ? Text(label!, style: context.text.titleSmall)
                  : TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(isDense: true, labelText: 'Nama'),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 6, child: MoneyField(controller: amount, label: 'Saldo')),
          ],
        ),
      );
}

class _SecurityPoints extends StatelessWidget {
  const _SecurityPoints();

  @override
  Widget build(BuildContext context) {
    Widget point(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Icon(i, color: context.colors.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(t, style: context.text.bodyMedium)),
            ],
          ),
        );
    return Column(
      children: [
        point(Icons.phonelink_lock_rounded, 'PIN disimpan terenkripsi di Android Keystore'),
        point(Icons.fingerprint_rounded, 'Bisa dibuka dengan sidik jari setelah PIN dibuat'),
        point(Icons.cloud_off_rounded, 'Tanpa akun, tanpa internet, tanpa iklan'),
        point(Icons.backup_rounded, 'Cadangkan manual ke file kapan saja (menu Pengaturan)'),
      ],
    );
  }
}
