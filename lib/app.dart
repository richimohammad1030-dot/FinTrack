// Root widget: tema, lokalisasi Indonesia, onboarding, dan kunci PIN.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'services/notifications.dart';
import 'services/security.dart';
import 'state/finance_store.dart';
import 'state/settings.dart';
import 'ui/lock/pin_pad.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/shell.dart';

class FinTrackApp extends StatelessWidget {
  const FinTrackApp({
    super.key,
    required this.settings,
    required this.store,
    required this.security,
    required this.notifier,
  });

  final Settings settings;
  final FinanceStore store;
  final SecurityService security;
  final Notifier notifier;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: store),
        Provider.value(value: security),
        Provider.value(value: notifier),
        ChangeNotifierProvider(create: (_) => LockController(locked: security.hasPin)),
      ],
      child: Consumer<Settings>(
        builder: (context, s, _) => MaterialApp(
          title: 'FinTrack',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: s.themeMode,
          locale: const Locale('id', 'ID'),
          supportedLocales: const [Locale('id', 'ID'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: s.onboarded ? const Shell() : const OnboardingScreen(),
          builder: (context, child) => _LockGate(child: child!),
        ),
      ),
    );
  }
}

/// Menutupi aplikasi dengan layar PIN saat terkunci, dan mengunci ulang saat
/// aplikasi ditinggal lebih lama dari batas waktu.
class _LockGate extends StatefulWidget {
  const _LockGate({required this.child});
  final Widget child;

  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<LockController>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      lock.onPaused();
    } else if (state == AppLifecycleState.resumed) {
      lock.onResumed(
        hasPin: context.read<SecurityService>().hasPin,
        delaySeconds: context.read<Settings>().lockDelaySeconds,
      );
      // Tanggal bisa berganti saat aplikasi di latar belakang → proses tagihan rutin.
      context.read<FinanceStore>().processRecurring();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = context.watch<LockController>().locked;
    return Stack(
      children: [
        // Konten tetap ada di belakang supaya state tidak hilang.
        // Konten di belakang tidak bisa difokus, dibaca pembaca layar, maupun beranimasi.
        ExcludeFocus(
          excluding: locked,
          child: ExcludeSemantics(
            excluding: locked,
            child: TickerMode(enabled: !locked, child: widget.child),
          ),
        ),
        if (locked) const Positioned.fill(child: BlockSemantics(child: LockScreen())),
      ],
    );
  }
}
