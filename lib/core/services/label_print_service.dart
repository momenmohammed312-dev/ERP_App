// label_print_service.dart
// طباعة ملصقات باركود حرارية للمنتجات (شركة + اسم + سعر اختياري + باركود).
// لا يستخدم ZPL/TSPL/serial — فقط `printing` + `pdf` مثل باقي التطبيق.
//
// معالجة العربية: النص العربي بيترسم كصورة (TextPainter) قبل ما يدخل الـPDF
// عشان مكتبة `pdf` ما بتدعـم shaping العربية — الحروف كانت بتطلع متقطعة.
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
    '1.5×1.0in (38×25mm)': [38.1, 25.4],
    '50×30mm': [50, 30],
    '50×50mm': [50, 50],
    '58×30mm': [58, 30],
    '58×40mm': [58, 40],
    '58×50mm': [58, 50],
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

    // حساب الهوامش — 0.05 بوصة = 1.27 مم لمقاس 1.5×1.0 بوصة
    // وإلا 1.5 مم من كل جانب
    final double leftMarginMm = (labelWidth - 38.1).abs() < 0.5 ? 1.27 : 1.5;
    final double rightMarginMm = leftMarginMm;
    final double topMarginMm = 1.5;
    final double bottomMarginMm = 1.5;

    final format = PdfPageFormat(
      labelWidth * PdfPageFormat.mm,
      labelHeight * PdfPageFormat.mm,
    );

    // الحد الأقصى للعرض المتاح للنص بالنقاط
    final usableWidthPts = (labelWidth - leftMarginMm - rightMarginMm) * PdfPageFormat.mm;
    final usableHeightPts = (labelHeight - topMarginMm - bottomMarginMm) * PdfPageFormat.mm;

    // الأحجام الأساسية للنصوص (بالنقطة) — كل نص بيتكيف مع المساحة المتاحة
    // فيكبر أو يقل تلقائياً حسب حجم الملصق، ومش بيتثبّت على رقم واحد.
    final bcHeightPts = (usableHeightPts * 0.35).clamp(14.0, 22.0);
    const double gapPts = 0.5;

    // نولّد كل صور النصوص العربية الأول (الـPDF build مش بيستقبل async)
    final companyRaster = (companyName != null && companyName.trim().isNotEmpty)
        ? await _renderFitted(
            text: companyName.trim(),
            fontSize: 8,
            minSize: 6,
            maxSize: 8,
            fontWeight: FontWeight.w600,
            maxWidth: usableWidthPts,
            maxHeightPts: (usableHeightPts - bcHeightPts) * 0.35,
          )
        : null;

    final Map<int, RasterizedText> nameRasters = {};
    final Map<int, RasterizedText> priceRasters = {};
    for (final p in products) {
      // المساحة الرأسية المتبقية للعناصر النصية بعد خصم الباركود والفراغات
      final int presentCount =
          (companyRaster != null ? 1 : 0) + 1 + (showPrice ? 1 : 0) + 1;
      var remainingPts =
          usableHeightPts - bcHeightPts - (presentCount - 1) * gapPts;
      if (companyRaster != null) {
        remainingPts -= companyRaster.heightPts;
      }

      if (showPrice) {
        priceRasters[p.id] = await _renderFitted(
          text: '${p.price.toStringAsFixed(2)} $currency',
          fontSize: 10,
          minSize: 6,
          maxSize: 10,
          fontWeight: FontWeight.w600,
          maxWidth: usableWidthPts,
          maxHeightPts: (remainingPts * 0.5).clamp(12.0, remainingPts),
        );
        remainingPts -= priceRasters[p.id]!.heightPts;
      }

      // اسم المنتج ياخد الباقي — لو السعر مخفي يتمدد وياخد مكانه أوتوماتيك
      nameRasters[p.id] = await _renderFitted(
        text: p.name.trim(),
        fontSize: 9,
        minSize: 6,
        maxSize: 15,
        fontWeight: FontWeight.bold,
        maxWidth: usableWidthPts,
        maxHeightPts: remainingPts > 0 ? remainingPts : 12,
      );
    }

    final pdf = pw.Document();
    final bc = Barcode.code128();

    for (final product in products) {
      final copies = copiesPerProduct[product.id] ?? 1;
      final code = barcodeData?[product.id] ?? product.barcode?.trim();
      for (var i = 0; i < copies; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.only(
              left: leftMarginMm * PdfPageFormat.mm,
              right: rightMarginMm * PdfPageFormat.mm,
              top: topMarginMm * PdfPageFormat.mm,
              bottom: bottomMarginMm * PdfPageFormat.mm,
            ),
            build: (context) => _buildLabel(
              companyRaster: companyRaster,
              nameRaster: nameRasters[product.id]!,
              priceRaster: showPrice ? priceRasters[product.id] : null,
              barcodeValue: code,
              barcode: bc,
              bcHeightPts: bcHeightPts,
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
        usePrinterSettings: true,
      );
    } catch (e) {
      debugPrint('Label print error: $e');
      rethrow;
    }
  }

  static pw.Widget _buildLabel({
    required RasterizedText? companyRaster,
    required RasterizedText nameRaster,
    required RasterizedText? priceRaster,
    required String? barcodeValue,
    required Barcode barcode,
    required double bcHeightPts,
    required double usableWidthPts,
    required double usableHeightPts,
  }) {
    final children = <pw.Widget>[];

    if (companyRaster != null) {
      // نعرض الصورة بعرضها الطبيعي مش ممدودة على كل عرض الملصق
      children.add(
        pw.Center(
          child: pw.Image(
            pw.MemoryImage(companyRaster.bytes),
            width: companyRaster.widthPts.clamp(0, usableWidthPts),
            height: companyRaster.heightPts,
          ),
        ),
      );
      children.add(pw.SizedBox(height: 0.5));
    }

    children.add(
      pw.Center(
        child: pw.Image(
          pw.MemoryImage(nameRaster.bytes),
          width: nameRaster.widthPts.clamp(0, usableWidthPts),
          height: nameRaster.heightPts,
        ),
      ),
    );
    children.add(pw.SizedBox(height: 0.5));

    if (priceRaster != null) {
      children.add(
        pw.Center(
          child: pw.Image(
            pw.MemoryImage(priceRaster.bytes),
            width: priceRaster.widthPts.clamp(0, usableWidthPts),
            height: priceRaster.heightPts,
          ),
        ),
      );
      children.add(pw.SizedBox(height: 0.5));
    }

    if (barcodeValue != null && barcodeValue.isNotEmpty) {
      children.add(
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: barcode,
            data: barcodeValue,
            color: PdfColors.black,
            width: usableWidthPts,
            height: bcHeightPts,
            drawText: true,
            // النص تحت الباركود أكبر (7pt) عشان يبقى مقروء ويتم التأكد من
            // الكود المرتبط بالمنتج.
            textStyle: pw.TextStyle(fontSize: 7),
          ),
        ),
      );
    }

    return pw.Container(
      width: usableWidthPts,
      height: usableHeightPts,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: children,
      ),
    );
  }

  /// يرسم نص عربي بحجم يتكيف مع المساحة المتاحة:
  /// - لو المساحة أقل من حجم النص → يقلّ تلقائياً لحد [minSize].
  /// - لو في مساحة زيادة (زي حالة إخفاء السعر) → يكبر لحد [maxSize].
  /// الاستخدام: تقليل التعبئة (padding) ولو صغر نص مش هيتقطع بشكل غريب.
  static Future<RasterizedText> _renderFitted({
    required String text,
    required double fontSize,
    required double minSize,
    required double maxSize,
    required double maxWidth,
    required double maxHeightPts,
    FontWeight fontWeight = FontWeight.normal,
  }) async {
    Future<RasterizedText> rasterize(double size) => ArabicTextRasterizer.render(
          text: text,
          fontSize: size,
          fontWeight: fontWeight,
          maxWidth: maxWidth,
          padding: 1,
        );

    var size = fontSize;
    var raster = await rasterize(size);

    if (raster.heightPts > maxHeightPts && size > minSize) {
      // المساحة أقل من حجم النص — نقلل بنفس النسبة عشان النص يكمل كامل
      size = (size * (maxHeightPts / raster.heightPts)).clamp(minSize, size);
      raster = await rasterize(size);
    } else if (size < maxSize && raster.heightPts < maxHeightPts * 0.8) {
      // مساحة زيادة (السعر مخفي مثلًا) — نكبر لحد maxSize أو لملء المساحة
      final target = (size * (maxHeightPts / raster.heightPts)).clamp(
        size,
        maxSize,
      );
      final bigger = await rasterize(target);
      if (bigger.heightPts <= maxHeightPts) {
        raster = bigger;
      }
    }

    return raster;
  }
}

