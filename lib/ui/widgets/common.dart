// Komponen UI yang dipakai berulang di banyak layar.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../logic/budget.dart';
import '../../state/settings.dart';

/// Nominal rupiah; otomatis disamarkan kalau mode privasi aktif.
class Money extends StatelessWidget {
  const Money(
    this.amount, {
    super.key,
    this.style,
    this.signed = false,
    this.compact = false,
    this.color,
    this.maskable = true,
  });

  final int amount;
  final TextStyle? style;
  final bool signed;
  final bool compact;
  final Color? color;
  final bool maskable;

  @override
  Widget build(BuildContext context) {
    final hide = maskable && context.select<Settings, bool>((s) => s.hideAmounts);
    final text = hide
        ? 'Rp •••••'
        : compact
            ? '${signed ? (amount >= 0 ? '+' : '-') : (amount < 0 ? '-' : '')}Rp ${compactRupiah(amount.abs())}'
            : signed
                ? signedRupiah(amount)
                : rupiah(amount);
    return Text(
      text,
      style: (style ?? const TextStyle()).copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Ikon bulat berwarna (dipakai untuk pos, dompet, target).
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 42});

  final String icon;
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: dark ? 0.22 : 0.13),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(iconFor(icon), color: c, size: size * 0.52),
    );
  }
}

Color levelColor(BuildContext context, BudgetLevel level, {Color? normal}) => switch (level) {
      BudgetLevel.over => context.palette.expense,
      BudgetLevel.warning => context.palette.warning,
      _ => normal ?? context.colors.primary,
    };

/// Bar progres membulat. Kalau lewat 100%, bar penuh berwarna merah.
class Bar extends StatelessWidget {
  const Bar({super.key, required this.ratio, required this.color, this.height = 8, this.background});

  final double ratio;
  final Color color;
  final double height;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final r = ratio.isNaN ? 0.0 : ratio.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: background ?? context.colors.onSurface.withValues(alpha: 0.07),
              ),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: r,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(height),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.padding});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 20, 12, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleMedium)),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: context.colors.primaryContainer.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: context.colors.primary),
          ),
          const SizedBox(height: 16),
          Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: context.text.bodyMedium?.copyWith(color: context.palette.muted),
                textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: onAction,
              style: FilledButton.styleFrom(minimumSize: const Size(160, 44)),
              child: Text(action!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Label kecil berwarna (misal "82%" atau "Habis").
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
          ],
          Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Dialog konfirmasi sederhana. Mengembalikan true kalau pengguna setuju.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String ok = 'Ya',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: ctx.palette.expense,
                  minimumSize: const Size(88, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

/// Pemilih warna (baris bulatan).
class ColorChooser extends StatelessWidget {
  const ColorChooser({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in appColors)
          GestureDetector(
            onTap: () => onChanged(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: value == c ? context.colors.onSurface : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: value == c ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
            ),
          ),
      ],
    );
  }
}

/// Pemilih ikon (grid).
class IconChooser extends StatelessWidget {
  const IconChooser({super.key, required this.value, required this.color, required this.onChanged});

  final String value;
  final int color;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in appIcons.keys)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(key),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: key == value ? Color(color).withValues(alpha: 0.18) : context.colors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: key == value ? Color(color) : Colors.transparent, width: 1.6),
              ),
              child: Icon(appIcons[key], size: 22, color: key == value ? Color(color) : context.palette.muted),
            ),
          ),
      ],
    );
  }
}

/// Kolom input nominal rupiah dengan titik ribuan otomatis.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.autofocus = false,
    this.validator,
    this.onChanged,
    this.large = false,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool autofocus;
  final bool large;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      inputFormatters: const [ThousandsInputFormatter()],
      validator: validator,
      onChanged: onChanged,
      style: large
          ? context.text.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint ?? '0',
        prefixText: 'Rp ',
        prefixStyle: large
            ? context.text.headlineMedium?.copyWith(color: context.palette.muted)
            : TextStyle(color: context.palette.muted),
      ),
    );
  }
}

String? requiredAmount(String? v) => parseDigits(v ?? '') <= 0 ? 'Isi nominal' : null;
