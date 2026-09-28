// Keamanan: PIN (disimpan sebagai hash + salt di Keystore) dan biometrik.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Penyimpanan rahasia (bisa diganti versi memori untuk pengujian).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeystoreSecretStore implements SecretStore {
  const KeystoreSecretStore();
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

class SecurityService {
  SecurityService({SecretStore? store, LocalAuthentication? auth})
      : _store = store ?? const KeystoreSecretStore(),
        _auth = auth;

  final SecretStore _store;
  final LocalAuthentication? _auth;
  static const _key = 'pin_hash_v1';
  static const pinLength = 6;

  bool _hasPin = false;
  bool get hasPin => _hasPin;

  int _failed = 0;
  DateTime? _lockedUntil;

  /// Sisa waktu tunggu setelah terlalu banyak salah PIN.
  Duration get cooldown {
    final u = _lockedUntil;
    if (u == null) return Duration.zero;
    final d = u.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  static const _attemptsKey = 'pin_attempts_v1';

  Future<void> init() async {
    try {
      _hasPin = (await _store.read(_key)) != null;
      // Jumlah salah PIN & waktu tunggu disimpan, jadi tidak ter-reset
      // hanya dengan menutup paksa aplikasi.
      final a = await _store.read(_attemptsKey);
      if (a != null) {
        final parts = a.split('|');
        _failed = int.tryParse(parts[0]) ?? 0;
        if (parts.length > 1 && parts[1].isNotEmpty) {
          _lockedUntil = DateTime.tryParse(parts[1]);
        }
      }
    } catch (_) {
      _hasPin = false;
    }
  }

  Future<void> _saveAttempts() async {
    try {
      if (_failed == 0) {
        await _store.delete(_attemptsKey);
      } else {
        await _store.write(_attemptsKey, '$_failed|${_lockedUntil?.toIso8601String() ?? ''}');
      }
    } catch (_) {}
  }

  static String _hash(String salt, String pin) {
    // Hash berulang supaya tebakan brute-force jauh lebih lambat.
    var bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < 20000; i++) {
      bytes = Uint8List.fromList(sha256.convert(bytes).bytes);
    }
    return base64Encode(bytes);
  }

  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt = base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    await _store.write(_key, '$salt\$${_hash(salt, pin)}');
    _hasPin = true;
    _failed = 0;
    _lockedUntil = null;
    await _saveAttempts();
  }

  Future<void> removePin() async {
    await _store.delete(_key);
    _hasPin = false;
  }

  /// Cek PIN. Setelah 5x salah berturut-turut, tunggu 30 detik (lalu makin lama).
  Future<bool> verify(String pin) async {
    if (cooldown > Duration.zero) return false;
    final String? stored;
    try {
      stored = await _store.read(_key);
    } catch (_) {
      return false;
    }
    // Tidak ada PIN tersimpan = kunci tidak aktif.
    if (stored == null) return true;
    final parts = stored.split(r'$');
    final ok = parts.length == 2 && _hash(parts[0], pin) == parts[1];
    if (ok) {
      _failed = 0;
      _lockedUntil = null;
    } else {
      _failed++;
      if (_failed >= 5) {
        _lockedUntil = DateTime.now().add(Duration(seconds: 30 * (_failed - 4)));
      }
    }
    await _saveAttempts();
    return ok;
  }

  LocalAuthentication get _la => _auth ?? LocalAuthentication();

  Future<bool> biometricAvailable() async {
    try {
      return await _la.canCheckBiometrics && await _la.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _la.authenticate(
        localizedReason: 'Buka FinTrack',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
