// Kerangka utama: navigasi bawah + tombol catat.

import 'package:flutter/material.dart';

import 'budget/budget_screen.dart';
import 'history/history_screen.dart';
import 'home/home_screen.dart';
import 'more/more_screen.dart';
import 'reports/reports_screen.dart';
import 'txn/txn_form.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  void _open(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenTab: _open),
      const HistoryScreen(),
      const BudgetScreen(),
      const ReportsScreen(),
      const MoreScreen(),
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _open(0);
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        floatingActionButton: _index == 4
            ? null
            : FloatingActionButton.extended(
                heroTag: 'add-txn',
                onPressed: () => openTxnForm(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Catat'),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _open,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Beranda'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Riwayat'),
            NavigationDestination(
                icon: Icon(Icons.pie_chart_outline_rounded), selectedIcon: Icon(Icons.pie_chart_rounded), label: 'Pos'),
            NavigationDestination(
                icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Laporan'),
            NavigationDestination(
                icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Lainnya'),
          ],
        ),
      ),
    );
  }
}
