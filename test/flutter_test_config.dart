// Muat font asli (Plus Jakarta Sans + Material Icons) supaya ukuran teks di
// pengujian sama dengan di HP, dan screenshot terlihat benar.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final jakarta = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    jakarta.addFont(_load('assets/fonts/PlusJakartaSans-$w.ttf'));
  }
  await jakarta.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(_load(icons.path));
      await loader.load();
    }
  }
  final emoji = Platform.environment['EMOJI_FONT'];
  if (emoji != null && File(emoji).existsSync()) {
    await (FontLoader('NotoEmoji')..addFont(_load(emoji))).load();
  }
  await testMain();
}

Future<ByteData> _load(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.view(bytes.buffer);
}
