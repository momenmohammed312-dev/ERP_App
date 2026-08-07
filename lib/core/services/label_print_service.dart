// label_print_service.dart
// طباعة ملصقات باركود حرارية للمنتجات (شركة + اسم + سعر اختياري + باركود).
// لا يستخدم ZPL/TSPL/serial — فقط `printing` + `pdf` مثل باقي التطبيق.
//
// معالجة العربية: النص العربي بيترسم كصورة (TextPainter) قبل ما يدخل الـPDF
// عشان مكتبة `pdf` ما بتدعـم shaping العربية — الحروف كانت بتطلع متقطعة.
import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/utils/arabic_text_rasterizer.dart';

class LabelPrintService {
  /// مقاسات ملصقات حرارية شائعة (العرض × الارتفاع بالمللي).
  static const Map<String, List<double>> labelPresets = {
    '50×30mm': [50, 30],
    '50×50mm': [50, 50],
    '70×40mm': [70, 40],
    '70×50mm': [70, 50],
  };

  /// اطبع ملصقات باركود لمنتجات مختارة.
  static Future<void> printProductLabels({
    required List<Product> products,
    required Map<int, int> copiesPerProduct,
    String? companyName,
    bool showPrice = true,
    Map<int, String>? barcodeData,
    double? widthMm,
    double? heightMm,
  }) async {
    final labelWidth = widthMm ?? await SettingsService.getLabelWidthMm();
    final labelHeight = heightMm ?? await SettingsService.getLabelHeightMm();
    final currency = await SettingsService.getCurrencySymbol();

    final format = PdfPageFormat(
      labelWidth * PdfPageFormat.mm,
      labelHeight * PdfPageFormat.mm,
    );

    // نولّد كل صور النصوص العربية الأول (الـPDF build مش بيستقبل async)
    final companyBytes = (companyName != null && companyName.trim().isNotEmpty)
        ? await ArabicTextRasterizer.render(
            text: companyName.trim(),
            fontSize: 9,
            fontWeight: FontWeight.w600,
            maxWidth: (labelWidth - 6) * PdfPageFormat.mm,
          )
        : null;

    final Map<int, Uint8List> nameBytes = {};
    final Map<int, Uint8List> priceBytes = {};
    for (final p in products) {
      final usableW = (labelWidth - 6) * PdfPageFormat.mm;
      nameBytes[p.id] = await ArabicTextRasterizer.render(
        text: p.name.trim(),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        maxWidth: usableW,
      );
      if (showPrice) {
        priceBytes[p.id] = await ArabicTextRasterizer.render(
          text: '${p.price.toStringAsFixed(2)} $currency',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          maxWidth: usableW,
        );
      }
    }

    final pdf = pw.Document();
    final bc = Barcode.code128();
    final usableWidthPts = (labelWidth - 4) * PdfPageFormat.mm;
    final usableHeightPts = (labelHeight - 4) * PdfPageFormat.mm;

    for (final product in products) {
      final copies = copiesPerProduct[product.id] ?? 1;
      final code = barcodeData?[product.id] ?? product.barcode?.trim();
      for (var i = 0; i < copies; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(1.5),
            build: (context) => _buildLabel(
              companyBytes: companyBytes,
              nameBytes: nameBytes[product.id]!,
              priceBytes: showPrice ? priceBytes[product.id] : null,
              barcodeValue: code,
              barcode: bc,
              usableWidthPts: usableWidthPts,
              usableHeightPts: usableHeightPts,
            ),
          ),
        );
      }
    }

    try {
      await Printing.layoutPdf(
        onLayout: (fmt) async => pdf.save(),
        name: 'product_labels_${DateTime.now().millisecondsSinceEpoch}',
        format: format,
        usePrinterSettings: false,
      );
    } catch (e) {
      debugPrint('Label print error: $e');
      rethrow;
    }
  }

  static pw.Widget _buildLabel({
    required Uint8List? companyBytes,
    required Uint8List nameBytes,
    required Uint8List? priceBytes,
    required String? barcodeValue,
    required Barcode barcode,
    required double usableWidthPts,
    required double usableHeightPts,
  }) {
    final children = <pw.Widget>[];

    if (companyBytes != null) {
      children.add(
        pw.Image(pw.MemoryImage(companyBytes), width: usableWidthPts),
      );
      children.add(pw.SizedBox(height: 1));
    }

    children.add(
      pw.Image(pw.MemoryImage(nameBytes), width: usableWidthPts),
    );
    children.add(pw.SizedBox(height: 1));

    if (priceBytes != null) {
      children.add(
        pw.Image(pw.MemoryImage(priceBytes), width: usableWidthPts),
      );
      children.add(pw.SizedBox(height: 1));
    }

    if (barcodeValue != null && barcodeValue.isNotEmpty) {
      final bcHeight = (usableHeightPts * 0.32).clamp(10.0, 20.0);
      children.add(
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: barcode,
            data: barcodeValue,
            color: PdfColors.black,
            width: usableWidthPts,
            height: bcHeight,
            drawText: true,
            textStyle: pw.TextStyle(fontSize: 6),
          ),
        ),
      );
    }

    return pw.Container(
      width: usableWidthPts,
      height: usableHeightPts,
      padding: const pw.EdgeInsets.all(1),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}
