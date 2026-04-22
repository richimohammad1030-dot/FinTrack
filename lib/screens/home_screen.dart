// lib/screens/home_screen.dart
// Pro-Tracker - Dashboard UI (v3)
// Update: swipe-to-delete, format ribuan otomatis, kategori bersih.

// ignore_for_file: unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';

// ── Warna ─────────────────────────────────────────────────────────────────────
const _accent     = Color(0xFF00E5A0);
const _danger     = Color(0xFFFF4D6A);
const _bgSurface  = Color(0xFF1A1A1A);
const _bgElevated = Color(0xFF242424);
const _textMuted  = Color(0xFF7A7A7A);
const _textPrimary = Color(0xFFF0F0F0);

// ── Formatter ─────────────────────────────────────────────────────────────────
final _currencyFmt = NumberFormat.currency(
  locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0,
);
final _dateFmt = DateFormat('dd MMM yyyy', 'id_ID');

// ── Warna kategori expense ─────────────────────────────────────────────────────
Color _categoryColor(String label) {
  switch (label) {
    case 'Makan & Minum':       return const Color(0xFFFF8C42);
    case 'Jajan & Hiburan':     return const Color(0xFFCC88FF);
    case 'Kebutuhan Bulanan':   return const Color(0xFF4D9BFF);
    case 'Transportasi':        return const Color(0xFF00D4FF);
    case 'Kesehatan':           return const Color(0xFFFF6B9D);
    case 'Belanja/Shopping':    return const Color(0xFFFFD93D);
    default:                    return const Color(0xFF7A7A7A);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CURRENCY INPUT FORMATTER
// Otomatis tambah titik ribuan saat mengetik, simpan sebagai angka murni.
// ═════════════════════════════════════════════════════════════════════════════

class _ThousandSeparatorFormatter extends TextInputFormatter {
  final _fmt = NumberFormat('#,###', 'id_ID');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Hapus semua karakter non-digit
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final number = int.tryParse(digits) ?? 0;
    // Format dengan pemisah ribuan menggunakan titik (locale id_ID)
    final formatted = _fmt.format(number);

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Konversi teks berformat ("20.000") kembali ke double (20000.0)
  static double parse(String formatted) {
    final clean = formatted.replaceAll(RegExp(r'[^\d]'), '');
    return double.tryParse(clean) ?? 0;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HOME SCREEN
// ═════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 720) return const _TabletLayout();
          return const _PhoneLayout();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTransactionSheet(context),
        tooltip: 'Tambah Transaksi',
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }
}

// ── Phone Layout ──────────────────────────────────────────────────────────────

class _PhoneLayout extends StatelessWidget {
  const _PhoneLayout();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          const SliverToBoxAdapter(child: _BalanceCard()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverToBoxAdapter(child: _IncomeSummaryRow()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverToBoxAdapter(child: _ExpenseProgressSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverToBoxAdapter(child: _TransactionListSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

// ── Tablet Layout ─────────────────────────────────────────────────────────────

class _TabletLayout extends StatelessWidget {
  const _TabletLayout();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: CustomScrollView(
              slivers: [
                _buildAppBar(context),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                const SliverToBoxAdapter(child: _BalanceCard()),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(child: _IncomeSummaryRow()),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(child: _ExpenseProgressSection()),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
          Container(width: 1, color: const Color(0xFF222222)),
          const Expanded(flex: 5, child: _TransactionPanelTablet()),
        ],
      ),
    );
  }
}

class _TransactionPanelTablet extends StatelessWidget {
  const _TransactionPanelTablet();
  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'Riwayat Transaksi',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _FilterChips()),
        SliverToBoxAdapter(child: SizedBox(height: 8)),
        _TransactionSliverList(),
        SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

// ── AppBar ────────────────────────────────────────────────────────────────────

SliverAppBar _buildAppBar(BuildContext context) {
  return SliverAppBar(
    floating: true,
    title: Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.bar_chart_rounded, color: _accent, size: 18),
          ),
        ),
        const SizedBox(width: 10),
        const Text('Pro-Tracker'),
      ],
    ),
    actions: [
      Consumer<TransactionProvider>(
        builder: (_, p, _) => p.isLoading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: p.refresh,
                tooltip: 'Refresh',
              ),
      ),
      const SizedBox(width: 4),
    ],
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// BALANCE CARD
// ═════════════════════════════════════════════════════════════════════════════

class _BalanceCard extends StatelessWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (_, p, __) {
        final balance = p.netBalance;
        final isPos = balance >= 0;
        final color = isPos ? _accent : _danger;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isPos
                  ? [const Color(0xFF0A2A1E), const Color(0xFF0D1F16)]
                  : [const Color(0xFF2A0A12), const Color(0xFF1F0D10)],
            ),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Balance',
                      style: TextStyle(color: _textMuted, fontSize: 13)),
                  _Badge(label: isPos ? 'Positif' : 'Defisit', color: color,
                      icon: isPos ? Icons.trending_up_rounded : Icons.trending_down_rounded),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _currencyFmt.format(balance.abs()),
                style: TextStyle(
                  color: color, fontSize: 32,
                  fontWeight: FontWeight.w800, letterSpacing: -1.0,
                ),
              ),
              const SizedBox(height: 20),
              _ProgressRow(label: 'Penggunaan Dana',
                  ratio: p.expenseRatio, color: color),
            ],
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Badge({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final double ratio;
  final Color color;
  const _ProgressRow({required this.label, required this.ratio, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: _textMuted, fontSize: 12)),
            Text('${(ratio * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio, minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// INCOME SUMMARY ROW
// ═════════════════════════════════════════════════════════════════════════════

class _IncomeSummaryRow extends StatelessWidget {
  const _IncomeSummaryRow();

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (_, p, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: _SummaryTile(
              label: 'Pemasukan', amount: p.totalIncome,
              icon: Icons.arrow_downward_rounded, color: _accent,
            )),
            const SizedBox(width: 12),
            Expanded(child: _SummaryTile(
              label: 'Pengeluaran', amount: p.totalExpense,
              icon: Icons.arrow_upward_rounded, color: _danger,
            )),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  const _SummaryTile({required this.label, required this.amount,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: _textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _currencyFmt.format(amount),
            style: TextStyle(
              color: color, fontSize: 15,
              fontWeight: FontWeight.w700, letterSpacing: -0.3,
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EXPENSE PROGRESS SECTION
// ═════════════════════════════════════════════════════════════════════════════

class _ExpenseProgressSection extends StatelessWidget {
  const _ExpenseProgressSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (_, p, __) {
        final data = p.expenseByCategory;
        final total = p.totalExpense;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _bgSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF242424)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart_outline_rounded, color: _accent, size: 16),
                  SizedBox(width: 8),
                  Text('Pengeluaran per Kategori',
                      style: TextStyle(color: _textPrimary, fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
              if (data.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Belum ada pengeluaran tercatat',
                        style: TextStyle(color: _textMuted, fontSize: 13)),
                  ),
                )
              else
                ...data.entries.map((e) => _CategoryBar(
                  label: e.key, amount: e.value,
                  ratio: total > 0 ? e.value / total : 0,
                )),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String label;
  final double amount;
  final double ratio;
  const _CategoryBar({required this.label, required this.amount, required this.ratio});

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: _textPrimary, fontSize: 13)),
              ]),
              Text(
                '${(ratio * 100).toStringAsFixed(1)}% · ${_currencyFmt.format(amount)}',
                style: const TextStyle(color: _textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio, minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TRANSACTION LIST SECTION
// ═════════════════════════════════════════════════════════════════════════════

class _TransactionListSection extends StatelessWidget {
  const _TransactionListSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Riwayat Transaksi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textPrimary)),
        ),
        const SizedBox(height: 10),
        const _FilterChips(),
        const SizedBox(height: 8),
        Consumer<TransactionProvider>(
          builder: (_, p, __) {
            final list = p.filteredTransactions;
            if (list.isEmpty) return _EmptyState();
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _TransactionTile(transaction: list[i]),
            );
          },
        ),
      ],
    );
  }
}

// ── Filter Chips ──────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (_, p, __) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _Chip(label: 'Semua',
                isSelected: p.activeTypeFilter == null, onTap: p.clearFilters),
            const SizedBox(width: 8),
            _Chip(label: 'Pemasukan', color: _accent,
                isSelected: p.activeTypeFilter == TransactionType.income,
                onTap: () => p.setTypeFilter(TransactionType.income)),
            const SizedBox(width: 8),
            _Chip(label: 'Pengeluaran', color: _danger,
                isSelected: p.activeTypeFilter == TransactionType.expense,
                onTap: () => p.setTypeFilter(TransactionType.expense)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.isSelected,
      this.color = _accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : _bgElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.5) : const Color(0xFF2E2E2E),
          ),
        ),
        child: Text(label, style: TextStyle(
          color: isSelected ? color : _textMuted,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
        )),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TRANSACTION TILE — dengan swipe-to-delete & tombol hapus
// ═════════════════════════════════════════════════════════════════════════════

class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;
  const _TransactionTile({required this.transaction});

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Transaksi?'),
        content: Text(
          '"${transaction.title}" akan dihapus permanen dan saldo akan diperbarui.',
          style: const TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Hapus', style: TextStyle(color: _danger)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted && transaction.id != null) {
      final success = await context
          .read<TransactionProvider>()
          .deleteTransaction(transaction.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? '"${transaction.title}" berhasil dihapus'
                : 'Gagal menghapus transaksi'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type == TransactionType.income;
    final color = isIncome ? _accent : _danger;

    return Dismissible(
      key: Key('txn-${transaction.id}'),
      direction: DismissDirection.endToStart,
      // Background merah saat swipe kiri
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: _danger.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_outline_rounded, color: _danger, size: 22),
            const SizedBox(height: 4),
            Text('Hapus', style: TextStyle(color: _danger, fontSize: 11,
                fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _bgSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Hapus Transaksi?'),
            content: Text(
              '"${transaction.title}" akan dihapus permanen.',
              style: const TextStyle(color: _textMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Hapus', style: TextStyle(color: _danger)),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      },
      onDismissed: (_) async {
        if (transaction.id != null) {
          await context.read<TransactionProvider>()
              .deleteTransaction(transaction.id!);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('"${transaction.title}" dihapus')),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF242424)),
        ),
        child: Row(
          children: [
            // Emoji icon
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(transaction.category.emoji,
                    style: const TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.title,
                    style: const TextStyle(color: _textPrimary, fontSize: 14,
                        fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(transaction.category.value,
                        style: const TextStyle(color: _textMuted, fontSize: 11)),
                    const Text(' · ', style: TextStyle(color: _textMuted, fontSize: 11)),
                    Text(_dateFmt.format(transaction.date),
                        style: const TextStyle(color: _textMuted, fontSize: 11)),
                  ]),
                  if (transaction.notes != null && transaction.notes!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        transaction.notes!,
                        style: TextStyle(
                          color: _textMuted.withValues(alpha: 0.7),
                          fontSize: 11, fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Jumlah + tombol hapus
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isIncome ? '+' : '-'}${_currencyFmt.format(transaction.amount)}',
                  style: TextStyle(
                    color: color, fontSize: 14,
                    fontWeight: FontWeight.w700, letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                // Tombol hapus kecil di setiap tile
                GestureDetector(
                  onTap: () => _confirmDelete(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: _danger.withValues(alpha: 0.7), size: 12),
                        const SizedBox(width: 2),
                        Text('Hapus',
                            style: TextStyle(color: _danger.withValues(alpha: 0.7),
                                fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sliver list tablet ────────────────────────────────────────────────────────

class _TransactionSliverList extends StatelessWidget {
  const _TransactionSliverList();

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (_, p, __) {
        final list = p.filteredTransactions;
        if (list.isEmpty) return SliverToBoxAdapter(child: _EmptyState());
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TransactionTile(transaction: list[i]),
              ),
              childCount: list.length,
            ),
          ),
        );
      },
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 48,
              color: _textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('Belum ada transaksi',
              style: TextStyle(color: _textMuted, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('Tekan tombol + untuk menambah',
              style: TextStyle(color: Color(0xFF555555), fontSize: 12)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ADD TRANSACTION BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════

void _showAddTransactionSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _AddTransactionSheet(),
  );
}

class _AddTransactionSheet extends StatefulWidget {
  const _AddTransactionSheet();
  @override
  State<_AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<_AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl  = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();

  // Instance formatter sekali pakai
  final _formatter = _ThousandSeparatorFormatter();

  TransactionType _type = TransactionType.expense;
  TransactionCategory _category = TransactionCategory.makanMinum;
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  List<TransactionCategory> get _availableCategories =>
      _type == TransactionType.income ? kIncomeCategories : kExpenseCategories;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: _accent),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    // Hapus format titik ribuan sebelum parse ke double
    final rawAmount = _ThousandSeparatorFormatter.parse(_amountCtrl.text);
    final notes = _notesCtrl.text.trim();

    final transaction = TransactionModel(
      title:    _titleCtrl.text.trim(),
      amount:   rawAmount,
      type:     _type,
      category: _category,
      date:     _date,
      notes:    notes.isEmpty ? null : notes,
    );

    final success = await context
        .read<TransactionProvider>()
        .addTransaction(transaction);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          success ? 'Transaksi berhasil disimpan ✓' : 'Gagal menyimpan',
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomPadding),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const Text('Tambah Transaksi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                    color: _textPrimary)),
            const SizedBox(height: 20),

            // ── Toggle Income / Expense ──────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: _bgElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _TypeToggle(
                    label: 'Pemasukan', icon: Icons.arrow_downward_rounded,
                    isSelected: _type == TransactionType.income, color: _accent,
                    onTap: () => setState(() {
                      _type = TransactionType.income;
                      _category = TransactionCategory.gajiUtama;
                    }),
                  ),
                  _TypeToggle(
                    label: 'Pengeluaran', icon: Icons.arrow_upward_rounded,
                    isSelected: _type == TransactionType.expense, color: _danger,
                    onTap: () => setState(() {
                      _type = TransactionType.expense;
                      _category = TransactionCategory.makanMinum;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Nama Transaksi ───────────────────────────────────────────
            TextFormField(
              controller: _titleCtrl,
              style: const TextStyle(color: _textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nama Transaksi',
                prefixIcon: Icon(Icons.edit_outlined, size: 18),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 12),

            // ── Jumlah dengan format ribuan otomatis ─────────────────────
            TextFormField(
              controller: _amountCtrl,
              style: const TextStyle(color: _textPrimary),
              keyboardType: TextInputType.number,
              // Format otomatis saat mengetik
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly, // hanya digit
                _formatter,                              // tambah titik ribuan
              ],
              decoration: const InputDecoration(
                labelText: 'Jumlah (Rp)',
                hintText: 'Contoh: 20.000',
                prefixIcon: Icon(Icons.attach_money_rounded, size: 18),
                prefixText: 'Rp  ',
                prefixStyle: TextStyle(color: _textMuted, fontSize: 14),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Wajib diisi';
                final n = _ThousandSeparatorFormatter.parse(v);
                if (n <= 0) return 'Masukkan jumlah yang valid';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // ── Kategori ─────────────────────────────────────────────────
            DropdownButtonFormField<TransactionCategory>(
              initialValue: _category,
              dropdownColor: _bgElevated,
              style: const TextStyle(color: _textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Kategori',
                prefixIcon: Icon(Icons.category_outlined, size: 18),
              ),
              items: _availableCategories.map((c) => DropdownMenuItem(
                value: c,
                child: Row(children: [
                  Text(c.emoji),
                  const SizedBox(width: 8),
                  Text(c.value),
                ]),
              )).toList(),
              onChanged: (val) => setState(() => _category = val!),
            ),
            const SizedBox(height: 12),

            // ── Keterangan (Opsional) ────────────────────────────────────
            TextFormField(
              controller: _notesCtrl,
              style: const TextStyle(color: _textPrimary),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Keterangan (Opsional)',
                hintText: 'Contoh: makan siang di warteg, bayar listrik...',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Icon(Icons.notes_rounded, size: 18),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),

            // ── Tanggal ──────────────────────────────────────────────────
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2E2E)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: _textMuted),
                    const SizedBox(width: 12),
                    Text(_dateFmt.format(_date),
                        style: const TextStyle(color: _textPrimary, fontSize: 14)),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded, color: _textMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Simpan ───────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Simpan Transaksi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Type Toggle ───────────────────────────────────────────────────────────────

class _TypeToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;
  const _TypeToggle({required this.label, required this.icon,
      required this.isSelected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isSelected ? color : _textMuted),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                color: isSelected ? color : _textMuted,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              )),
            ],
          ),
        ),
      ),
    );
  }
}