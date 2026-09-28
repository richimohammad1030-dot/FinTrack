import 'package:fintrack/data/database.dart';
import 'package:fintrack/services/notifications.dart';
import 'package:fintrack/state/finance_store.dart';
import 'package:fintrack/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiReady = false;

void setUpFfi() {
  if (_ffiReady) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  _ffiReady = true;
}

Future<(FinanceStore, Settings, NoopNotifier)> makeStore({
  DateTime? now,
  Map<String, Object> prefs = const {},
}) async {
  setUpFfi();
  SharedPreferences.setMockInitialValues(prefs);
  final settings = Settings(await SharedPreferences.getInstance());
  final db = await AppDatabase.open(path: inMemoryDatabasePath);
  final notifier = NoopNotifier();
  final store = FinanceStore(
    db: db,
    settings: settings,
    notifier: notifier,
    clock: now == null ? null : () => now,
  );
  await store.load();
  return (store, settings, notifier);
}
