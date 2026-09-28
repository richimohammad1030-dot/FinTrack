// Pengaturan: anggaran, tampilan, notifikasi, keamanan, backup.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/notifications.dart';
import '../../services/security.dart';
import '../../services/secure_screen.dart';
import '../../state/finance_store.dart';
import '../../state/settings.dart';
import '../lock/pin_pad.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.scrollToSecurity = false});
  final bool scrollToSecurity;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _securityKey = GlobalKey();
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    context.read<SecurityService>().biometricAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
    if (widget.scrollToSecurity) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _securityKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    final sec = context.read<SecurityService>();
    final notifier = context.read<Notifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          const _Group('Anggaran'),
          _Card([
            ListTile(
              leading: const Icon(Icons.event_available_rounded),
              title: const Text('Tanggal gajian'),
              subtitle: Text('Periode dimulai setiap tanggal ${s.payday}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final d = await pickPayday(context, s.payday);
                if (d != null) s.payday = d;
              },
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: const Text('Batas pengeluaran harian'),
              subtitle: Text(s.manualDailyLimit > 0
                  ? 'Manual: ${rupiah(s.manualDailyLimit)} per hari'
                  : 'Otomatis: sisa anggaran ÷ sisa hari sampai gajian'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _editDailyLimit(context, s),
            ),
          ]),
          const _Group('Tampilan'),
          _Card([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tema'),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('Otomatis')),
                        ButtonSegment(value: ThemeMode.light, label: Text('Terang')),
                        ButtonSegment(value: ThemeMode.dark, label: Text('Gelap')),
                      ],
                      selected: {s.themeMode},
                      onSelectionChanged: (v) => s.themeMode = v.first,
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_rounded),
              title: const Text('Sembunyikan nominal'),
              subtitle: const Text('Berguna saat membuka aplikasi di tempat umum'),
              value: s.hideAmounts,
              onChanged: (v) => s.hideAmounts = v,
            ),
          ]),
          const _Group('Notifikasi'),
          _Card([
            SwitchListTile(
              secondary: const Icon(Icons.warning_amber_rounded),
              title: const Text('Peringatan anggaran'),
              subtitle: const Text('Saat batas harian / pos mencapai 80% dan 100%'),
              value: s.alertsEnabled,
              onChanged: (v) async {
                if (v) await notifier.requestPermission();
                s.alertsEnabled = v;
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.edit_calendar_rounded),
              title: const Text('Pengingat mencatat'),
              subtitle: Text('Setiap hari pukul ${s.reminderTime.format(context)}'),
              value: s.dailyReminder,
              onChanged: (v) async {
                s.dailyReminder = v;
                if (v) {
                  await notifier.requestPermission();
                  await notifier.scheduleDailyReminder(s.reminderTime);
                } else {
                  await notifier.cancelDailyReminder();
                }
              },
            ),
            if (s.dailyReminder)
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Jam pengingat'),
                trailing: Text(s.reminderTime.format(context)),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: s.reminderTime);
                  if (t == null) return;
                  s.reminderTime = t;
                  await notifier.scheduleDailyReminder(t);
                },
              ),
          ]),
          _Group('Keamanan', key: _securityKey),
          _Card([
            SwitchListTile(
              secondary: const Icon(Icons.pin_rounded),
              title: const Text('Kunci dengan PIN'),
              subtitle: const Text('Minta PIN setiap membuka aplikasi'),
              value: sec.hasPin,
              onChanged: (v) async {
                if (v) {
                  await createPinFlow(context);
                } else if (await verifyPinFlow(context)) {
                  await sec.removePin();
                  s.biometricEnabled = false;
                }
                if (mounted) setState(() {});
              },
            ),
            if (sec.hasPin) ...[
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('Ganti PIN'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  if (await verifyPinFlow(context) && context.mounted) {
                    if (await createPinFlow(context) && context.mounted) toast(context, 'PIN diganti ✓');
                  }
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint_rounded),
                title: const Text('Buka dengan sidik jari / wajah'),
                subtitle: Text(_bioAvailable ? 'PIN tetap bisa dipakai sebagai cadangan' : 'Tidak tersedia di perangkat ini'),
                value: s.biometricEnabled && _bioAvailable,
                onChanged: _bioAvailable
                    ? (v) async {
                        if (v && !await sec.authenticateBiometric()) return;
                        s.biometricEnabled = v;
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Kunci otomatis'),
                subtitle: Text(_lockLabel(s.lockDelaySeconds)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _pickLockDelay(context, s),
              ),
            ],
          ]),
          _Card([
            SwitchListTile(
              secondary: const Icon(Icons.screenshot_monitor_rounded),
              title: const Text('Sembunyikan layar di Recent Apps'),
              subtitle: const Text('Isi aplikasi tidak terlihat di daftar aplikasi terbaru; screenshot juga diblokir'),
              value: s.secureScreen,
              onChanged: (v) {
                s.secureScreen = v;
                applySecureScreen(v);
              },
            ),
          ]),
          const _Group('Data'),
          _Card([
            ListTile(
              leading: const Icon(Icons.cloud_upload_rounded),
              title: const Text('Cadangkan data'),
              subtitle: const Text('Simpan file backup (.json) ke HP / Google Drive'),
              onTap: () => _backup(context),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore_rounded),
              title: const Text('Pulihkan dari backup'),
              subtitle: const Text('Mengganti semua data dengan isi file backup'),
              onTap: () => _restore(context),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_rounded, color: context.palette.expense),
              title: Text('Hapus semua data', style: TextStyle(color: context.palette.expense)),
              onTap: () => _reset(context),
            ),
          ]),
          const SizedBox(height: 20),
          Center(
            child: Text('FinTrack 2.0 · data tersimpan hanya di HP ini',
                style: context.text.bodySmall),
          ),
        ],
      ),
    );
  }

  static String _lockLabel(int s) => s == 0 ? 'Langsung saat aplikasi ditinggal' : 'Setelah ${s >= 60 ? '${s ~/ 60} menit' : '$s detik'} ditinggal';

  Future<void> _pickLockDelay(BuildContext context, Settings s) async {
    final v = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: RadioGroup<int>(
          groupValue: s.lockDelaySeconds,
          onChanged: (v) => Navigator.pop(ctx, v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final sec in const [0, 30, 60, 300])
                RadioListTile<int>(value: sec, title: Text(_lockLabel(sec))),
            ],
          ),
        ),
      ),
    );
    if (v != null) s.lockDelaySeconds = v;
  }

  Future<void> _editDailyLimit(BuildContext context, Settings s) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _DailyLimitDialog(initial: s.manualDailyLimit),
    );
    if (result != null) s.manualDailyLimit = result;
  }

  Future<void> _backup(BuildContext context) async {
    final store = context.read<FinanceStore>();
    try {
      final json = await store.exportJson();
      final n = store.now;
      final name = 'fintrack-backup-${n.year}${_pad2(n.month)}${_pad2(n.day)}.json';
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Simpan backup',
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
      );
      if (uri != null && context.mounted) {
        toast(context, 'Backup tersimpan ✓ Simpan juga salinannya di Google Drive.');
      }
    } catch (e) {
      if (context.mounted) toast(context, 'Gagal membuat backup: $e');
    }
  }

  Future<void> _restore(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final ok = await confirm(context,
        title: 'Pulihkan dari backup?',
        message: 'Semua data di HP ini akan diganti dengan isi file backup.',
        ok: 'Pilih file');
    if (!ok) return;
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final text = utf8.decode(await files.first.readAsBytes());
      await store.importJson(text);
      if (context.mounted) toast(context, 'Data berhasil dipulihkan ✓');
    } on FormatException catch (e) {
      if (context.mounted) toast(context, e.message);
    } catch (e) {
      if (context.mounted) toast(context, 'Gagal memulihkan: $e');
    }
  }

  Future<void> _reset(BuildContext context) async {
    final store = context.read<FinanceStore>();
    final ok = await confirm(context,
        title: 'Hapus semua data?',
        message: 'Semua transaksi, dompet, target, dan transaksi rutin akan dihapus permanen. '
            'Buat backup dulu kalau ragu.',
        ok: 'Hapus semua',
        destructive: true);
    if (!ok || !context.mounted) return;
    if (!await verifyPinFlow(context)) return;
    await store.resetAll();
    if (context.mounted) toast(context, 'Semua data dihapus');
  }

  static String _pad2(int v) => v.toString().padLeft(2, '0');
}

class _DailyLimitDialog extends StatefulWidget {
  const _DailyLimitDialog({required this.initial});
  final int initial;

  @override
  State<_DailyLimitDialog> createState() => _DailyLimitDialogState();
}

class _DailyLimitDialogState extends State<_DailyLimitDialog> {
  late final _ctrl = TextEditingController(text: widget.initial > 0 ? groupDigits(widget.initial) : '');
  late bool _manual = widget.initial > 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Batas harian'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioGroup<bool>(
            groupValue: _manual,
            onChanged: (v) => setState(() => _manual = v!),
            child: const Column(
              children: [
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  value: false,
                  title: Text('Otomatis (disarankan)'),
                  subtitle: Text('Menyesuaikan tiap hari: hemat hari ini → jatah besok naik'),
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  value: true,
                  title: Text('Tetap / manual'),
                ),
              ],
            ),
          ),
          if (_manual) MoneyField(controller: _ctrl, label: 'Batas per hari', autofocus: true),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(context, _manual ? parseDigits(_ctrl.text) : 0),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Dialog pilih tanggal gajian (grid 1–31).
Future<int?> pickPayday(BuildContext context, int current) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tanggal gajian'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 31; d++)
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: d == current
                        ? FilledButton(
                            style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(38, 38)),
                            onPressed: () => Navigator.pop(ctx, d),
                            child: Text('$d'),
                          )
                        : TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(38, 38)),
                            onPressed: () => Navigator.pop(ctx, d),
                            child: Text('$d'),
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Kalau bulan itu tidak punya tanggal tersebut (mis. 31), dipakai tanggal terakhir bulan.',
                style: ctx.text.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title, style: context.text.labelLarge?.copyWith(color: context.colors.primary)),
      );
}

class _Card extends StatelessWidget {
  const _Card(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: children),
      );
}
