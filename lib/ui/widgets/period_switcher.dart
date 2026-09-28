import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../logic/period.dart';

/// Navigasi periode gajian: ‹ 25 Sep – 24 Okt ›
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    super.key,
    required this.period,
    required this.current,
    required this.onChanged,
  });

  final PayPeriod period;
  final PayPeriod current;
  final ValueChanged<PayPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCurrent = period == current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Periode sebelumnya',
            onPressed: () => onChanged(period.previous),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: GestureDetector(
              onTap: isCurrent ? null : () => onChanged(current),
              child: Column(
                children: [
                  Text(fmtPeriod(period), style: context.text.titleSmall, textAlign: TextAlign.center),
                  Text(
                    isCurrent ? 'Periode ini' : 'Ketuk untuk kembali ke periode ini',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Periode berikutnya',
            onPressed: isCurrent ? null : () => onChanged(period.next),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
