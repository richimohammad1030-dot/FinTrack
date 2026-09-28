// Tab "Lainnya": dompet, target tabungan, transaksi rutin, pengaturan.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/finance_store.dart';
import '../widgets/common.dart';
import 'goals_screen.dart';
import 'recurring_screen.dart';
import 'settings_screen.dart';
import 'wallets_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    Widget tile(IconData icon, Color color, String title, String subtitle, Widget page) => ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color),
          ),
          title: Text(title, style: context.text.titleSmall),
          subtitle: Text(subtitle, style: context.text.bodySmall),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => go(page),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          AppCard(
            onTap: () => go(const WalletsScreen()),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total saldo semua dompet', style: context.text.bodySmall),
                      const SizedBox(height: 4),
                      Money(store.totalBalance, style: context.text.headlineSmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                tile(Icons.account_balance_wallet_rounded, const Color(0xFF2A78D6), 'Dompet & Rekening',
                    '${store.activeWallets.length} dompet · transfer antar dompet', const WalletsScreen()),
                tile(Icons.flag_rounded, context.palette.saving, 'Target Tabungan',
                    '${store.activeGoals.length} target aktif', const GoalsScreen()),
                tile(Icons.event_repeat_rounded, const Color(0xFFEB6834), 'Transaksi Rutin',
                    '${store.recurrings.where((r) => r.active).length} aktif · kos, internet, cicilan…',
                    const RecurringScreen()),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                tile(Icons.tune_rounded, context.palette.muted, 'Pengaturan',
                    'Tanggal gajian, batas harian, tema, notifikasi', const SettingsScreen()),
                tile(Icons.lock_rounded, context.palette.muted, 'Keamanan & Backup',
                    'PIN, sidik jari, cadangkan data', const SettingsScreen(scrollToSecurity: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
