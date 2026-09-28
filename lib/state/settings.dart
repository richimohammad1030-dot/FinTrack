// Pengaturan aplikasi (disimpan di SharedPreferences).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends ChangeNotifier {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  bool get onboarded => _prefs.getBool('onboarded') ?? false;
  set onboarded(bool v) => _set('onboarded', v);

  /// Tanggal gajian (1–31).
  int get payday => _prefs.getInt('payday') ?? 25;
  set payday(int v) => _set('payday', v.clamp(1, 31));

  /// Perkiraan gaji/pemasukan per periode (untuk layar "Bagi Gaji").
  int get estimatedIncome => _prefs.getInt('estimated_income') ?? 0;
  set estimatedIncome(int v) => _set('estimated_income', v);

  /// Batas harian manual. 0 = dihitung otomatis dari anggaran.
  int get manualDailyLimit => _prefs.getInt('manual_daily_limit') ?? 0;
  set manualDailyLimit(int v) => _set('manual_daily_limit', v);

  ThemeMode get themeMode => ThemeMode.values[_prefs.getInt('theme_mode') ?? 0];
  set themeMode(ThemeMode v) => _set('theme_mode', v.index);

  /// Sembunyikan nominal di beranda (mode privasi).
  bool get hideAmounts => _prefs.getBool('hide_amounts') ?? false;
  set hideAmounts(bool v) => _set('hide_amounts', v);

  bool get alertsEnabled => _prefs.getBool('alerts_enabled') ?? true;
  set alertsEnabled(bool v) => _set('alerts_enabled', v);

  bool get dailyReminder => _prefs.getBool('daily_reminder') ?? true;
  set dailyReminder(bool v) => _set('daily_reminder', v);

  TimeOfDay get reminderTime => TimeOfDay(
        hour: _prefs.getInt('reminder_hour') ?? 20,
        minute: _prefs.getInt('reminder_minute') ?? 0,
      );
  set reminderTime(TimeOfDay t) {
    _prefs.setInt('reminder_hour', t.hour);
    _set('reminder_minute', t.minute);
  }

  bool get biometricEnabled => _prefs.getBool('biometric_enabled') ?? false;
  set biometricEnabled(bool v) => _set('biometric_enabled', v);

  /// FLAG_SECURE: sembunyikan isi aplikasi di Recent Apps & blokir screenshot.
  bool get secureScreen => _prefs.getBool('secure_screen') ?? false;
  set secureScreen(bool v) => _set('secure_screen', v);

  /// Kunci ulang setelah aplikasi di latar belakang selama N detik.
  int get lockDelaySeconds => _prefs.getInt('lock_delay') ?? 30;
  set lockDelaySeconds(int v) => _set('lock_delay', v);

  /// ID dompet yang terakhir dipakai (jadi default di form transaksi).
  int? get lastWalletId => _prefs.getInt('last_wallet');
  set lastWalletId(int? v) => v == null ? _prefs.remove('last_wallet') : _prefs.setInt('last_wallet', v);

  /// Dipakai saat "Hapus semua data": kembali ke onboarding, tapi tema,
  /// kunci, dan notifikasi tidak diubah.
  void resetBudgetSettings() {
    for (final k in ['payday', 'estimated_income', 'manual_daily_limit', 'last_wallet', 'onboarded']) {
      _prefs.remove(k);
    }
    notifyListeners();
  }

  Future<void> clear() async {
    await _prefs.clear();
    notifyListeners();
  }

  void _set(String key, Object v) {
    switch (v) {
      case bool b:
        _prefs.setBool(key, b);
      case int i:
        _prefs.setInt(key, i);
      case String s:
        _prefs.setString(key, s);
    }
    notifyListeners();
  }
}
