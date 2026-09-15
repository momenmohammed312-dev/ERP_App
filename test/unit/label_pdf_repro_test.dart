import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/label_print_service.dart';

/// إعادة إنتاج headless لبلاغ: "الباركود/QR لا يظهران في الملصق المطبوع"
/// و"ملصق الصنف يطبع بيانات الأب".
///
/// يبني مستند PDF حقيقي بنفس كود الإنتاج (buildLabelDocument) ويحفظه —
/// أي استثناء في توليد الباركود/QR أو الـ layout سيظهر هنا.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  Product parent() => const Product(
        id: 1,
        name: 'تيشيرت',
        quantity: 15,
        price: 100,
        minStockLevel: 0,
        barneka: false,
      );

  ProductVariant red() => const ProductVariant(
        id: 7,
        productId: 1,
        name: 'أحمر',
        quantity: 10,
        price: 120,
      );

  test('ملصق أب + QR: يُبنى ويُحفظ دون استثناء', () async {
    final doc = await LabelPrintService.buildLabelDocument(
      jobs: [
        ProductLabelJob(
          product: parent(),
          copies: 1,
          barcode: '10000001',
        ),
      ],
      companyName: 'المحل التجاري',
      widthMm: 38.1,
      heightMm: 25.4,
      qrData: 'https://example.com/shop',
    );
    final bytes = await doc.save();
    // ignore: avoid_print
    print('parent+QR bytes: ${bytes.length}');
    expect(bytes.isNotEmpty, isTrue);
  });

  test('ملصق صنف + QR: يُبنى ويُحفظ دون استثناء', () async {
    final doc = await LabelPrintService.buildLabelDocument(
      jobs: [
        ProductLabelJob(
          product: parent(),
          variant: red(),
          copies: 1,
          barcode: '20000007',
        ),
      ],
      companyName: 'المحل التجاري',
      widthMm: 50,
      heightMm: 30,
      qrData: 'https://example.com/shop',
    );
    final bytes = await doc.save();
    // ignore: avoid_print
    print('variant+QR bytes: ${bytes.length}');
    expect(bytes.isNotEmpty, isTrue);
  });

  test('مقاس العميل 55.88×25.4 + شركة + سعر + QR: يُبنى دون استثناء', () async {
    expect(LabelPrintService.labelPresets['2.2×1.0in (56×25mm)'], [55.88, 25.4]);
    final doc = await LabelPrintService.buildLabelDocument(
      jobs: [
        ProductLabelJob(
          product: parent(),
          variant: red(),
          copies: 1,
          barcode: '20000007',
        ),
      ],
      companyName: 'المحل التجاري',
      widthMm: 55.88,
      heightMm: 25.4,
      qrData: 'https://example.com/shop',
    );
    final bytes = await doc.save();
    // ignore: avoid_print
    print('client 55.88x25.4 bytes: ${bytes.length}');
    expect(bytes.isNotEmpty, isTrue);
  });

  test('عدد النسخ يضاعف حجم المستند', () async {    final one = await (await LabelPrintService.buildLabelDocument(
      jobs: [ProductLabelJob(product: parent(), copies: 1, barcode: '10000001')],
      widthMm: 50,
      heightMm: 30,
    ))
        .save();
    final three = await (await LabelPrintService.buildLabelDocument(
      jobs: [ProductLabelJob(product: parent(), copies: 3, barcode: '10000001')],
      widthMm: 50,
      heightMm: 30,
    ))
        .save();
    // ignore: avoid_print
    print('1 copy: ${one.length}, 3 copies: ${three.length}');
    expect(three.length, greaterThan(one.length));
  });

  test('ملصق الصنف يختلف عن ملصق الأب (لا يطبع بيانات الأب)', () async {
    final parentDoc = await LabelPrintService.buildLabelDocument(
      jobs: [ProductLabelJob(product: parent(), copies: 1, barcode: '10000001')],
      widthMm: 50,
      heightMm: 30,
    );
    final variantDoc = await LabelPrintService.buildLabelDocument(
      jobs: [
        ProductLabelJob(
          product: parent(),
          variant: red(),
          copies: 1,
          barcode: '20000007',
        ),
      ],
      widthMm: 50,
      heightMm: 30,
    );
    final parentBytes = await parentDoc.save();
    final variantBytes = await variantDoc.save();
    // ignore: avoid_print
    print('parent: ${parentBytes.length}, variant: ${variantBytes.length}');
    expect(
      variantBytes,
      isNot(equals(parentBytes)),
      reason: 'ملصق الصنف يجب أن يحمل اسم/باركود الصنف لا الأب',
    );
  });

  group('LabelLayoutMetrics', () {
    // انحدار لعلّة "الأكواد تُقصّ بصمت": ميزانية الارتفاع يجب أن تحجز
    // الارتفاع الفعلي لصف الأكواد (QR أطول من الباركود) على كل المقاسات.
    const presets = [
      [38.1, 25.4],
      [55.88, 25.4], // مقاس العميل (Xprinter 2.2×1.0in)
      [50.0, 30.0],
      [50.0, 50.0],
      [58.0, 30.0],
      [58.0, 40.0],
      [58.0, 50.0],
      [70.0, 40.0],
      [70.0, 50.0],
    ];

    for (final preset in presets) {
      final w = (preset[0] as double), h = (preset[1] as double);
      test('مقاس ${w}×${h}: صف الأكواد = الأطول، والميزانية تكفي', () {
        final leftMargin = (w - 38.1).abs() < 0.5 ? 1.27 : 1.5;
        final usableW = (w - leftMargin * 2) * PdfPageFormat.mm;
        final usableH = (h - 3.0) * PdfPageFormat.mm;
        final bcH = (usableH * 0.35).clamp(14.0, 22.0);

        final withQr = LabelLayoutMetrics.resolve(
          usableWidthPts: usableW,
          usableHeightPts: usableH,
          barcodeHeightPts: bcH,
          hasQr: true,
        );
        final withoutQr = LabelLayoutMetrics.resolve(
          usableWidthPts: usableW,
          usableHeightPts: usableH,
          barcodeHeightPts: bcH,
          hasQr: false,
        );

        // بدون QR: الصف = الباركود بالظبط (السلوك القديم السليم).
        expect(withoutQr.codesRowPts, bcH);
        // مع QR: الصف = الأطول (هذا ما كان ناقصًا وسبّب القصّ).
        expect(withQr.codesRowPts, greaterThanOrEqualTo(bcH));
        expect(withQr.codesRowPts, greaterThanOrEqualTo(withQr.qrSizePts));
        // الـ QR داخل الحدود العملية.
        expect(withQr.qrSizePts, greaterThanOrEqualTo(28.0));
        expect(withQr.qrSizePts, lessThanOrEqualTo(72.0));
        // لا يتجاوز العرض ناقص مساحة الباركود الدنيا (بهامش التقريب).
        expect(withQr.qrSizePts, lessThanOrEqualTo(usableW - 44.0 + 0.01));
        // الميزانية الكلية (أكواد + 3 فواصل + حدود ضيقة + اسم 4pt) تكفي.
        const gaps = 3 * 0.5;
        final tightFixed = withQr.codesRowPts + gaps + 6.0 + 6.0 + 4.0;
        expect(
          tightFixed,
          lessThan(usableH),
          reason: 'حتى أضيق توزيع يجب أن يتسع لملصق ${w}×${h}',
        );
      });
    }
  });
}
