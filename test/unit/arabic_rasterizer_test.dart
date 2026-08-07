import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/utils/arabic_text_rasterizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArabicTextRasterizer', () {
    test('renders Arabic text to non-empty PNG bytes', () async {
      final bytes = await ArabicTextRasterizer.render(
        text: 'تفاح أحمر',
        fontSize: 12,
        fontWeight: FontWeight.bold,
      );
      expect(bytes, isA<Uint8List>());
      expect(bytes.length, greaterThan(100));
    });

    test('renders English text to non-empty PNG bytes', () async {
      final bytes = await ArabicTextRasterizer.render(
        text: 'Apple 123',
        fontSize: 10,
        direction: TextDirection.ltr,
      );
      expect(bytes, isA<Uint8List>());
      expect(bytes.length, greaterThan(50));
    });

    test('renders long text without throwing', () async {
      final bytes = await ArabicTextRasterizer.render(
        text: 'منتج طويل جداً يحتوي على كلام كثير ومفصل بالتفصيل',
        fontSize: 11,
        maxWidth: 150,
      );
      expect(bytes, isA<Uint8List>());
    });
  });
}
