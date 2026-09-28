import 'package:kait/app.dart';
import 'package:kait/services/security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'demo_data.dart';
import 'test_utils.dart';

final now = DateTime(2026, 9, 28, 19);

Future<Widget> buildApp(WidgetTester tester, {bool demo = true}) async {
  late Widget app;
  await tester.runAsync(() async {
    final (store, settings, notifier) = await makeStore(now: now);
    if (demo) await seedDemo(store);
    final security = SecurityService(store: MemorySecretStore());
    await security.init();
    app = KaitApp(settings: settings, store: store, security: security, notifier: notifier);
  });
  return app;
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'id_ID';
    await initializeDateFormatting('id_ID');
  });

  testWidgets('onboarding tampil untuk pengguna baru', (tester) async {
    await tester.pumpWidget(await buildApp(tester, demo: false));
    await tester.pumpAndSettle();
    expect(find.text('KAIT'), findsWidgets);
    await tester.tap(find.text('Mulai'));
    await tester.pumpAndSettle();
    expect(find.text('Kapan kamu gajian?'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(find.text('Bagi gajimu ke pos-pos'), findsOneWidget);
  });

  testWidgets('beranda menampilkan jatah harian & semua tab bisa dibuka', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.pumpAndSettle();
    expect(find.text('Aman dipakai hari ini'), findsOneWidget);
    expect(find.text('Tagihan jatuh tempo'), findsOneWidget);

    for (final tab in ['Riwayat', 'Pos', 'Laporan', 'Lainnya', 'Beranda']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('form catat transaksi bisa dibuka dan divalidasi', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catat'));
    await tester.pumpAndSettle();
    expect(find.text('Catat Transaksi'), findsOneWidget);
    // Simpan tanpa nominal → pesan validasi
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Isi nominal'), findsOneWidget);
    // Ganti tipe ke pemasukan: pilihan pos berubah jadi sumber pemasukan
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();
    expect(find.text('Sumber pemasukan'), findsOneWidget);
    expect(find.text('Freelance'), findsOneWidget);
  });
}
