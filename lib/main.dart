// KAIT — Kelola Arus Keuangan: pencatat keuangan pribadi berbasis pos anggaran & siklus gajian.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'data/database.dart';
import 'services/notifications.dart';
import 'services/secure_screen.dart';
import 'services/security.dart';
import 'state/finance_store.dart';
import 'state/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'id_ID';
  await initializeDateFormatting('id_ID');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final settings = await Settings.load();
  final security = SecurityService();
  final notifier = LocalNotifier();
  final db = await AppDatabase.open();
  final store = FinanceStore(db: db, settings: settings, notifier: notifier);

  // Notifikasi disiapkan dulu supaya pengingat hutang bisa dijadwalkan saat load.
  await notifier.init();
  await Future.wait([security.init(), store.load()]);
  if (settings.onboarded && settings.dailyReminder) {
    notifier.scheduleDailyReminder(settings.reminderTime);
  }

  if (settings.secureScreen) applySecureScreen(true);

  runApp(KaitApp(settings: settings, store: store, security: security, notifier: notifier));
}
