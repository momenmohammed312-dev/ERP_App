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
    '2.2×1.0in (56×25mm)': [55.88, 25.4],
    '50×30mm': [50, 30],
    '50×50mm': [50, 50],
    '58×30mm': [58, 30],
    '58×40mm': [58, 40],
    '58×50mm': [58, 50],
    '70×40mm': [70, 40],
    '70×50mm': [70, 50],
  };

  /// اطبع ملصقات باركود لمنتجات مختارة.
  ///
  /// [qrData]: لينك/نص اختياري يُطبع كـ QR code جنب الباركود (layout أفقي).
  /// فارغ أو null = المسار القديم (باركود فقط بعرض الملصق).
  /// ملاحظة المساحة: الـ QR يحتاج ~15مم على الأقل للمسح الموثوق — المقاسات
  /// الأصغر من 50مم عرضًا تُطبع لكن بجودة مسح أقل (واجهة الملصقات تحذر).
  static Future<void> printProductLabels({
    required List<Product> products,
    required Map<int, int> copiesPerProduct,
    String? companyName,
    bool showPrice = true,
    Map<int, String>? barcodeData,
    double? widthMm,
    double? heightMm,
    String? qrData,
  }) async {
    // مسار الأب فقط (بدون أصناف) — يُبنى كـ jobs وتُفوض للنواة الموحدة.
    final jobs = [
      for (final p in products)
        ProductLabelJob(
          product: p,
          copies: copiesPerProduct[p.id] ?? 1,
          barcode: barcodeData?[p.id] ?? p.barcode?.trim() ?? '',
        ),
    ];
    return printLabelJobs(
      jobs: jobs,
      companyName: companyName,
      showPrice: showPrice,
      widthMm: widthMm,
      heightMm: heightMm,
      qrData: qrData,
    );
  }

  /// النواة الموحدة: طباعة ملصقات لمنتجات و/أو أصناف (كل صنف بباركوده واسمه).
  static Future<void> printLabelJobs({
    required List<ProductLabelJob> jobs,
    String? companyName,
    bool showPrice = true,
    double? widthMm,
    double? heightMm,
    String? qrData,
  }) async {
    final doc = await buildLabelDocument(
      jobs: jobs,
      companyName: companyName,
      showPrice: showPrice,
      widthMm: widthMm,
      heightMm: heightMm,
      qrData: qrData,
    );
    try {
      await Printing.layoutPdf(
        onLayout: (fmt) async => doc.save(),
        name: 'product_labels_${DateTime.now().millisecondsSinceEpoch}',
        format: PdfPageFormat(
          (widthMm ?? await SettingsService.getLabelWidthMm()) *
              PdfPageFormat.mm,
          (heightMm ?? await SettingsService.getLabelHeightMm()) *
              PdfPageFormat.mm,
        ),
        usePrinterSettings: true,
      );
    } catch (e) {
      debugPrint('Label print error: $e');
      rethrow;
    }
  }

  /// بناء مستند الـ PDF للملصقات بدون طباعة — خطاف اختبار (test hook)
  /// يسمح بالتحقق headless من أن الباركود/QR يتولدان دون استثناء.
  static Future<pw.Document> buildLabelDocument({
    required List<ProductLabelJob> jobs,
    String? companyName,
    bool showPrice = true,
    double? widthMm,
    double? heightMm,
    String? qrData,
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

    final qrValue = (qrData != null && qrData.trim().isNotEmpty)
        ? qrData.trim()
        : null;

    // مقاسات صف الأكواد الفعلية (الـ QR أطول من الباركود) — تُحجز مسبقًا من
    // الارتفاع قبل توزيع النصوص، وإلا تجاوز المحتوى الارتفاع المتاح وقُصّت
    // الأكواد بصمت من أسفل الملصق (كانت تُحسب ب.bcHeight فقط).
    final metrics = LabelLayoutMetrics.resolve(
      usableWidthPts: usableWidthPts,
      usableHeightPts: usableHeightPts,
      barcodeHeightPts: bcHeightPts,
      hasQr: qrValue != null,
    );
    final codesRowPts = metrics.codesRowPts;

    final hasCompany =
        companyName != null && companyName.trim().isNotEmpty;
    var childCount = 2; // الاسم + صف الأكواد
    if (hasCompany) childCount++;
    if (showPrice) childCount++;
    final poolPts =
        usableHeightPts - codesRowPts - (childCount - 1) * gapPts;

    // دفعة عادية أو ضيقة (تُحسم مرة واحدة لتوحيد شكل كل الملصقات):
    // الحدود القصوى للشركة/السعر، والاسم يأخذ الباقي بدقة.
    var companyMaxH = (poolPts * 0.3).clamp(8.0, 16.0);
    var priceMaxH = (poolPts * 0.3).clamp(8.0, 18.0);
    final needCompany = hasCompany ? companyMaxH : 0.0;
    final needPrice = showPrice ? priceMaxH : 0.0;
    if (needCompany + needPrice + 8.0 > poolPts) {
      // ضيقة: الاسم أولًا (8pt مقروءة حد أدنى)، والزخرفة تُضغط.
      companyMaxH = (poolPts * 0.22).clamp(6.0, 10.0);
      priceMaxH = (poolPts * 0.22).clamp(6.0, 12.0);
    }

    // نولّد كل صور النصوص العربية الأول (الـPDF build مش بيستقبل async)
    final companyRaster = hasCompany
        ? await _renderFitted(
            text: companyName.trim(),
            fontSize: 8,
            minSize: 5,
            maxSize: 8,
            fontWeight: FontWeight.w600,
            maxWidth: usableWidthPts,
            maxHeightPts: companyMaxH,
          )
        : null;

    final Map<int, RasterizedText> nameRasters = {};
    final Map<int, RasterizedText> priceRasters = {};
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      RasterizedText? priceRaster;
      if (showPrice) {
        priceRaster = await _renderFitted(
          text: '${job.price.toStringAsFixed(2)} $currency',
          fontSize: 10,
          minSize: 5,
          maxSize: 10,
          fontWeight: FontWeight.w600,
          maxWidth: usableWidthPts,
          maxHeightPts: priceMaxH,
        );
        priceRasters[i] = priceRaster;
      }

      // اسم الملصق يأخذ الباقي بدقة — لو السعر مخفي يتمدد وياخد مكانه أوتوماتيك.
      // حد أدنى 4pt كشبكة أمان للملصقات المتناهية الصغر (الـ presets كلها أوسع).
      final nameMax = poolPts -
          (companyRaster?.heightPts ?? 0) -
          (priceRaster?.heightPts ?? 0);
      nameRasters[i] = await _renderFitted(
        text: job.displayName.trim(),
        fontSize: 9,
        minSize: 5,
        maxSize: 15,
        fontWeight: FontWeight.bold,
        maxWidth: usableWidthPts,
        maxHeightPts: nameMax < 4 ? 4 : nameMax,
      );
    }

    final pdf = pw.Document();
    final bc = Barcode.code128();
    // QR بمستوى تصحيح M (يتحمل 15% تلف — مناسب للملصقات المتداولة).
    final qr = Barcode.qrCode(
      errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
    );

    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      for (var c = 0; c < job.copies; c++) {
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
              nameRaster: nameRasters[i]!,
              priceRaster: showPrice ? priceRasters[i] : null,
              barcodeValue: job.barcode.isEmpty ? null : job.barcode,
              barcode: bc,
              bcHeightPts: bcHeightPts,
              usableWidthPts: usableWidthPts,
              usableHeightPts: usableHeightPts,
              qrValue: qrValue,
              qr: qr,
            ),
          ),
        );
      }
    }

    return pdf;
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
    required String? qrValue,
    required Barcode qr,
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
      if (qrValue != null) {
        // Layout أفقي: الباركود شمال + QR مربع يمين — نفس المقاسات المحجوزة
        // في حساب الارتفاع (LabelLayoutMetrics) عشان مفيش قصّ صامت.
        final metrics = LabelLayoutMetrics.resolve(
          usableWidthPts: usableWidthPts,
          usableHeightPts: usableHeightPts,
          barcodeHeightPts: bcHeightPts,
          hasQr: true,
        );
        final qrSizePts = metrics.qrSizePts;
        final barcodeWidthPts = (usableWidthPts - qrSizePts - 4.0).clamp(
          40.0,
          usableWidthPts,
        );
        children.add(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.BarcodeWidget(
                barcode: barcode,
                data: barcodeValue,
                color: PdfColors.black,
                width: barcodeWidthPts,
                height: bcHeightPts,
                drawText: true,
                textStyle: pw.TextStyle(fontSize: 6),
              ),
              pw.SizedBox(width: 4),
              pw.BarcodeWidget(
                barcode: qr,
                data: qrValue,
                color: PdfColors.black,
                width: qrSizePts,
                height: qrSizePts,
                drawText: false,
              ),
            ],
          ),
        );
      } else {
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

/// مقاسات صف الأكواد (باركود + QR) — مصدر واحد للحساب في البناء والمعاينة.
///
/// القاعدة: ارتفاع الصف = الأطول بين الباركود والـ QR، وحجم الـ QR يتكيف
/// مع الورقة طولًا وعرضًا (لا يتجاوز العرض ناقص مساحة الباركود الدنيا).
class LabelLayoutMetrics {
  /// حجم ضلع الـ QR بالنقاط (0 = لا يوجد QR).
  final double qrSizePts;

  /// الارتفاع الفعلي المحجوز لصف الأكواد — يُخصم من ميزانية الارتفاع
  /// قبل توزيع النصوص حتى لا يُقصّت الأكواد بصمت.
  final double codesRowPts;

  const LabelLayoutMetrics({
    required this.qrSizePts,
    required this.codesRowPts,
  });

  static LabelLayoutMetrics resolve({
    required double usableWidthPts,
    required double usableHeightPts,
    required double barcodeHeightPts,
    required bool hasQr,
  }) {
    if (!hasQr) {
      return LabelLayoutMetrics(
        qrSizePts: 0,
        codesRowPts: barcodeHeightPts,
      );
    }
    var qr = usableHeightPts * 0.5;
    // سقف العرض: نسيب 40pt للباركود + 4pt فاصل.
    final maxByWidth = usableWidthPts - 44.0;
    if (qr > maxByWidth) qr = maxByWidth;
    qr = qr.clamp(28.0, 72.0);
    final codes = qr > barcodeHeightPts ? qr : barcodeHeightPts;
    return LabelLayoutMetrics(qrSizePts: qr, codesRowPts: codes);
  }
}

/// مهمة ملصق واحدة: منتج أب أو صنف (لون/فئة) بباركوده الخاص.
///
/// - الاسم المعروض: "قماش X — أحمر" للصنف، واسم المنتج للأب.
/// - السعر المعروض: سعر الصنف لو متحدد وله سعر، وإلا سعر الأب.
class ProductLabelJob {
  final Product product;
  final ProductVariant? variant;
  final int copies;
  final String barcode;

  ProductLabelJob({
    required this.product,
    this.variant,
    required this.copies,
    required this.barcode,
  });

  String get displayName {
    final v = variant;
    if (v == null) return product.name;
    return '${product.name} — ${v.name}';
  }

  double get price => variant?.price ?? product.price;
}

