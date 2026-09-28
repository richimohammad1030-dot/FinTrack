// Render layar-layar utama ke PNG (docs/screenshots) untuk dicek visual.
// Jalankan: SCREENSHOTS=1 flutter test test/screenshots_test.dart --update-goldens

import 'dart:io';

import 'package:fintrack/app.dart';
import 'package:fintrack/services/security.dart';
import 'package:fintrack/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'demo_data.dart';
import 'test_utils.dart';

final _enabled = Platform.environment.containsKey('SCREENSHOTS');

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'id_ID';
    await initializeDateFormatting('id_ID');
  });

  Future<Settings> pumpApp(WidgetTester tester, {bool dark = false, bool demo = true}) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    late Widget app;
    late Settings settings;
    await tester.runAsync(() async {
      final (store, s, notifier) = await makeStore(now: DateTime(2026, 9, 28, 19, 30));
      settings = s;
      if (demo) await seedDemo(store);
      s.themeMode = dark ? ThemeMode.dark : ThemeMode.light;
      final security = SecurityService(store: MemorySecretStore());
      await security.init();
      app = FinTrackApp(settings: s, store: store, security: security, notifier: notifier);
    });
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    return settings;
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/screenshots/$name.png'));
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    final suffix = dark ? '-dark' : '';
    testWidgets('screens$suffix', (tester) async {
      await pumpApp(tester, dark: dark);
      await shot(tester, '01-beranda$suffix');
      await tab(tester, 'Riwayat');
      await shot(tester, '02-riwayat$suffix');
      await tab(tester, 'Pos');
      await shot(tester, '03-pos$suffix');
      await tab(tester, 'Laporan');
      await shot(tester, '04-laporan$suffix');
      await tester.drag(find.byType(ListView).last, const Offset(0, -700));
      await shot(tester, '05-laporan-harian$suffix');
      await tab(tester, 'Lainnya');
      await shot(tester, '06-lainnya$suffix');
      await tab(tester, 'Beranda');
      await tester.tap(find.text('Catat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Makan & Minum'));
      await shot(tester, '07-catat$suffix');
    }, skip: !_enabled);
  }

  testWidgets('screens-extra', (tester) async {
    await pumpApp(tester);
    await tab(tester, 'Pos');
    await tester.tap(find.text('Bagi Gaji'));
    await tester.pumpAndSettle();
    await shot(tester, '08-bagi-gaji');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tab(tester, 'Lainnya');
    await tester.tap(find.text('Target Tabungan'));
    await tester.pumpAndSettle();
    await shot(tester, '09-target');
  }, skip: !_enabled);

  testWidgets('screens-onboarding', (tester) async {
    await pumpApp(tester, demo: false);
    await shot(tester, '10-onboarding-1');
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '7500000');
    await tester.tap(find.text('Saran otomatis'));
    await shot(tester, '11-onboarding-2');
  }, skip: !_enabled);
}
