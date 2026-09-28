// Mengaktifkan FLAG_SECURE di Android lewat MethodChannel (lihat MainActivity.kt).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('fintrack/secure_screen');

Future<void> applySecureScreen(bool enabled) async {
  try {
    await _channel.invokeMethod('set', enabled);
  } catch (e) {
    debugPrint('secure screen tidak tersedia: $e');
  }
}
