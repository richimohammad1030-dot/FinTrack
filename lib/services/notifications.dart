// Notifikasi lokal: peringatan anggaran & pengingat harian mencatat.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../logic/budget.dart';

abstract class Notifier {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> showAlert(BudgetAlert alert);
  Future<void> scheduleDailyReminder(TimeOfDay time);
  Future<void> cancelDailyReminder();
}

/// Dipakai di pengujian / platform tanpa notifikasi.
class NoopNotifier implements Notifier {
  final shown = <BudgetAlert>[];
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> showAlert(BudgetAlert alert) async => shown.add(alert);
  @override
  Future<void> scheduleDailyReminder(TimeOfDay time) async {}
  @override
  Future<void> cancelDailyReminder() async {}
}

class LocalNotifier implements Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const _reminderId = 1000;
  static const _icon = 'ic_stat_notify';

  static const _alertChannel = AndroidNotificationDetails(
    'budget_alerts',
    'Peringatan anggaran',
    channelDescription: 'Muncul saat batas harian atau batas pos hampir/sudah terlewati',
    importance: Importance.high,
    priority: Priority.high,
    icon: _icon,
  );
  static const _reminderChannel = AndroidNotificationDetails(
    'daily_reminder',
    'Pengingat harian',
    channelDescription: 'Pengingat untuk mencatat pengeluaran hari ini',
    importance: Importance.defaultImportance,
    icon: _icon,
  );

  @override
  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_icon),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifikasi tidak tersedia: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> showAlert(BudgetAlert alert) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: alert.scope == AlertScope.daily ? 1 : 100 + (alert.categoryId ?? 0),
        title: alert.title,
        body: alert.message,
        notificationDetails: const NotificationDetails(android: _alertChannel),
      );
    } catch (e) {
      debugPrint('Gagal menampilkan notifikasi: $e');
    }
  }

  @override
  Future<void> scheduleDailyReminder(TimeOfDay time) async {
    if (!_ready) return;
    try {
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.cancel(id: _reminderId);
      await _plugin.zonedSchedule(
        id: _reminderId,
        scheduledDate: at,
        title: 'Sudah catat pengeluaran hari ini? ✍️',
        body: 'Luangkan 10 detik supaya tahu ke mana uangmu pergi.',
        notificationDetails: const NotificationDetails(android: _reminderChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Gagal menjadwalkan pengingat: $e');
    }
  }

  @override
  Future<void> cancelDailyReminder() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _reminderId);
    } catch (_) {}
  }
}
