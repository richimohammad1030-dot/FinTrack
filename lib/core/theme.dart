// Tema aplikasi: terang & gelap, font Plus Jakarta Sans.

import 'package:flutter/material.dart';

const _seed = Color(0xFF0E9F6E);
const fontFamily = 'PlusJakartaSans';

/// Warna semantik tambahan (pemasukan, pengeluaran, tabungan, peringatan).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.income,
    required this.expense,
    required this.saving,
    required this.warning,
    required this.border,
    required this.muted,
    required this.heroStart,
    required this.heroEnd,
  });

  final Color income;
  final Color expense;
  final Color saving;
  final Color warning;
  final Color border;
  final Color muted;
  final Color heroStart;
  final Color heroEnd;

  static const light = AppPalette(
    income: Color(0xFF059669),
    expense: Color(0xFFE11D48),
    saving: Color(0xFF4F46E5),
    warning: Color(0xFFD97706),
    border: Color(0xFFE6E8EC),
    muted: Color(0xFF6B7280),
    heroStart: Color(0xFF047857),
    heroEnd: Color(0xFF0E9F6E),
  );

  static const dark = AppPalette(
    income: Color(0xFF34D399),
    expense: Color(0xFFFB7185),
    saving: Color(0xFF818CF8),
    warning: Color(0xFFFBBF24),
    border: Color(0xFF242A29),
    muted: Color(0xFF9CA3AF),
    heroStart: Color(0xFF065F46),
    heroEnd: Color(0xFF0B7A56),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      income: l(income, other.income),
      expense: l(expense, other.expense),
      saving: l(saving, other.saving),
      warning: l(warning, other.warning),
      border: l(border, other.border),
      muted: l(muted, other.muted),
      heroStart: l(heroStart, other.heroStart),
      heroEnd: l(heroEnd, other.heroEnd),
    );
  }
}

extension ThemeX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = dark ? AppPalette.dark : AppPalette.light;
  var scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  scheme = scheme.copyWith(
    surface: dark ? const Color(0xFF0D1110) : const Color(0xFFF5F7F6),
    surfaceContainerLowest: dark ? const Color(0xFF0A0D0C) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF141918) : Colors.white,
    surfaceContainer: dark ? const Color(0xFF1A201F) : const Color(0xFFEEF1F0),
    surfaceContainerHigh: dark ? const Color(0xFF212827) : const Color(0xFFE7EBEA),
    outlineVariant: palette.border,
    error: palette.expense,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fontFamily,
    // Hanya dipakai saat render screenshot di komputer; di HP emoji memakai font sistem.
    fontFamilyFallback: const ['NotoEmoji'],
    scaffoldBackgroundColor: scheme.surface,
    extensions: [palette],
  );
  final t = base.textTheme;
  final textTheme = t.copyWith(
    displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
    headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
    headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    bodySmall: t.bodySmall?.copyWith(color: palette.muted),
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: dark ? 0.28 : 0.14),
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? scheme.primary : palette.muted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          )),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: palette.border),
        textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: palette.border),
      showCheckmark: false,
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.primary.withValues(alpha: dark ? 0.28 : 0.16),
      labelStyle: TextStyle(
        fontFamily: fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: scheme.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    dividerTheme: DividerThemeData(color: palette.border, space: 1, thickness: 1),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700),
        side: BorderSide(color: palette.border),
      ),
    ),
  );
}
