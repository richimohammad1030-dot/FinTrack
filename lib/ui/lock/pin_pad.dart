// Keypad PIN 6 digit + layar kunci + alur membuat PIN.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/security.dart';
import '../../state/settings.dart';

class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    this.subtitle,
    required this.onCompleted,
    this.onBiometric,
    this.error,
  });

  final String title;
  final String? subtitle;
  final String? error;

  /// Dipanggil saat 6 digit terisi. Kembalikan false untuk mengosongkan & getar.
  final Future<bool> Function(String pin) onCompleted;
  final VoidCallback? onBiometric;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _busy = false;
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _tap(String d) async {
    if (_busy || _pin.length >= SecurityService.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == SecurityService.pinLength) {
      setState(() => _busy = true);
      var ok = false;
      try {
        ok = await widget.onCompleted(_pin);
      } catch (_) {
        ok = false;
      }
      if (!mounted) return;
      if (!ok) {
        HapticFeedback.heavyImpact();
        _shake.forward(from: 0);
      }
      setState(() {
        _pin = '';
        _busy = false;
      });
    }
  }

  void _back() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget key(String d) => _Key(onTap: () => _tap(d), child: Text(d, style: context.text.headlineSmall));
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxHeight < 560;
      return Column(
        children: [
          const Spacer(),
          Icon(Icons.lock_rounded, size: 40, color: c.primary),
          const SizedBox(height: 16),
          Text(widget.title, style: context.text.titleLarge, textAlign: TextAlign.center),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(widget.subtitle!, style: context.text.bodyMedium?.copyWith(color: context.palette.muted),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _shake,
            builder: (_, child) {
              final t = _shake.value;
              final dx = t == 0 ? 0.0 : 12 * (1 - t) * (t * 20).remainder(2) * ((t * 10).floor().isEven ? 1 : -1);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < SecurityService.pinLength; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? c.primary : Colors.transparent,
                      border: Border.all(color: i < _pin.length ? c.primary : context.palette.muted, width: 1.6),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: Center(
              child: widget.error == null
                  ? null
                  : Text(widget.error!, style: TextStyle(color: context.palette.expense)),
            ),
          ),
          SizedBox(height: compact ? 0 : 12),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d)]),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Key(
                onTap: widget.onBiometric,
                child: widget.onBiometric == null
                    ? const SizedBox.shrink()
                    : Icon(Icons.fingerprint_rounded, size: 30, color: c.primary),
              ),
              key('0'),
              _Key(onTap: _back, child: const Icon(Icons.backspace_outlined)),
            ],
          ),
          SizedBox(height: compact ? 12 : 40),
        ],
      );
    });
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 72,
          height: 64,
          child: Material(
            color: Colors.transparent,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: Center(child: child)),
          ),
        ),
      );
}

// ── Kunci aplikasi ─────────────────────────────────────────────────────────

class LockController extends ChangeNotifier {
  LockController({required bool locked}) : _locked = locked;
  bool _locked;
  bool get locked => _locked;
  DateTime? _pausedAt;

  void unlock() {
    _locked = false;
    notifyListeners();
  }

  void lock() {
    _locked = true;
    notifyListeners();
  }

  void onPaused() => _pausedAt = DateTime.now();

  void onResumed({required bool hasPin, required int delaySeconds}) {
    final p = _pausedAt;
    _pausedAt = null;
    if (!hasPin || p == null || _locked) return;
    if (DateTime.now().difference(p).inSeconds >= delaySeconds) lock();
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _error;
  bool _bioAvailable = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBio());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initBio() async {
    final settings = context.read<Settings>();
    final sec = context.read<SecurityService>();
    if (!settings.biometricEnabled) return;
    final ok = await sec.biometricAvailable();
    if (!mounted) return;
    setState(() => _bioAvailable = ok);
    if (ok) _biometric();
  }

  Future<void> _biometric() async {
    final lock = context.read<LockController>();
    final ok = await context.read<SecurityService>().authenticateBiometric();
    if (ok) lock.unlock();
  }

  Future<bool> _check(String pin) async {
    final sec = context.read<SecurityService>();
    final lock = context.read<LockController>();
    if (sec.cooldown > Duration.zero) {
      _startCooldownTicker();
      return false;
    }
    final ok = await sec.verify(pin);
    if (ok) {
      lock.unlock();
      return true;
    }
    if (sec.cooldown > Duration.zero) {
      _startCooldownTicker();
    } else {
      setState(() => _error = 'PIN salah');
    }
    return false;
  }

  void _startCooldownTicker() {
    _timer?.cancel();
    void tick() {
      final left = context.read<SecurityService>().cooldown;
      setState(() => _error = left > Duration.zero ? 'Terlalu banyak percobaan. Coba lagi dalam ${left.inSeconds + 1} detik' : null);
      if (left <= Duration.zero) _timer?.cancel();
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PinPad(
          title: 'Masukkan PIN',
          subtitle: 'FinTrack terkunci untuk melindungi datamu',
          error: _error,
          onCompleted: _check,
          onBiometric: _bioAvailable ? _biometric : null,
        ),
      ),
    );
  }
}

/// Alur membuat PIN baru (isi dua kali). Mengembalikan true kalau berhasil.
Future<bool> createPinFlow(BuildContext context) async {
  final r = await Navigator.push<bool>(
    context,
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _CreatePinScreen()),
  );
  return r ?? false;
}

class _CreatePinScreen extends StatefulWidget {
  const _CreatePinScreen();

  @override
  State<_CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<_CreatePinScreen> {
  String? _first;
  String? _error;

  Future<bool> _onPin(String pin) async {
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return true;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = 'PIN tidak sama, ulangi dari awal';
      });
      return false;
    }
    await context.read<SecurityService>().setPin(pin);
    if (mounted) Navigator.pop(context, true);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: PinPad(
          key: ValueKey(_first == null),
          title: _first == null ? 'Buat PIN 6 digit' : 'Ulangi PIN',
          subtitle: _first == null ? 'PIN dipakai untuk membuka FinTrack' : 'Masukkan PIN yang sama sekali lagi',
          error: _error,
          onCompleted: _onPin,
        ),
      ),
    );
  }
}

/// Minta PIN saat ini (sebelum mematikan/mengubah PIN).
Future<bool> verifyPinFlow(BuildContext context) async {
  final sec = context.read<SecurityService>();
  if (!sec.hasPin) return true;
  final r = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: _VerifyPin(onOk: () => Navigator.pop(ctx, true)),
        ),
      ),
    ),
  );
  return r ?? false;
}

class _VerifyPin extends StatefulWidget {
  const _VerifyPin({required this.onOk});
  final VoidCallback onOk;

  @override
  State<_VerifyPin> createState() => _VerifyPinState();
}

class _VerifyPinState extends State<_VerifyPin> {
  String? _error;

  @override
  Widget build(BuildContext context) => PinPad(
        title: 'Masukkan PIN saat ini',
        error: _error,
        onCompleted: (pin) async {
          final sec = context.read<SecurityService>();
          final ok = await sec.verify(pin);
          if (ok) {
            widget.onOk();
          } else {
            setState(() => _error = sec.cooldown > Duration.zero
                ? 'Terlalu banyak percobaan, tunggu ${sec.cooldown.inSeconds + 1} detik'
                : 'PIN salah');
          }
          return ok;
        },
      );
}
