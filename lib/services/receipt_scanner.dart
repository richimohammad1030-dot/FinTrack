// Scan struk: ambil foto (kamera/galeri) lalu baca teksnya dengan ML Kit.
// Semua diproses di HP (offline), tidak ada gambar yang dikirim ke server.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/receipt_parser.dart';

enum ScanSource { camera, gallery }

class ScanOutcome {
  final ReceiptResult result;
  final String imagePath;
  const ScanOutcome(this.result, this.imagePath);
}

class ReceiptScanner {
  const ReceiptScanner();

  /// Mengembalikan null kalau pengguna membatalkan.
  Future<ScanOutcome?> scan(ScanSource source) async {
    final file = await ImagePicker().pickImage(
      source: source == ScanSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(file.path));
      final lines = <OcrLine>[
        for (final b in text.blocks)
          for (final l in b.lines)
            OcrLine(
              l.text,
              left: l.boundingBox.left,
              top: l.boundingBox.top,
              right: l.boundingBox.right,
              bottom: l.boundingBox.bottom,
            ),
      ];
      // Urutkan dari atas ke bawah supaya "baris berikutnya" masuk akal.
      lines.sort((a, b) => a.top!.compareTo(b.top!));
      return ScanOutcome(parseReceipt(lines), file.path);
    } finally {
      await recognizer.close();
    }
  }

  /// Hapus foto sementara setelah dipakai (privasi).
  static Future<void> discard(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('Gagal menghapus foto sementara: $e');
    }
  }
}
