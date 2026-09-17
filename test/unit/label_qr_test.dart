import 'package:barcode/barcode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/label_print_service.dart';

/// تحقق من توليد QR لملصقات الباركود (نفس الـ API المستخدم في
/// LabelPrintService: Barcode.qrCode بمستوى تصحيح medium).
void main() {
  group('Label QR generation', () {
    test('لينك صفحة صالح يتولد منه QR', () {
      const url = 'https://facebook.com/myshop';
      final qr = Barcode.qrCode(
        errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
      );
      expect(qr.isValid(url), isTrue);
      final data = qr.make(url, width: 100, height: 100);
      expect(data, isNotNull);
    });

    test('لينك طويل (UTM) ما زال صالحًا — مع توصية بالتقصير', () {
      final url =
          'https://example.com/shop?utm_source=label&utm_medium=qr&utm_campaign=2026';
      final qr = Barcode.qrCode(
        errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
      );
      expect(qr.isValid(url), isTrue);
      expect(url.length, greaterThan(50));
    });

    test('نص فارغ غير صالح — الخدمة تتجاهله للمسار القديم', () {
      final qr = Barcode.qrCode(
        errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
      );
      expect(qr.isValid(''), isFalse);
    });
  });

  group('ProductLabelJob', () {
    Product parent() => Product(
          id: 1,
          name: 'قماش X',
          quantity: 15,
          price: 100,
          minStockLevel: 0,
          barneka: false,
        );

    test('ملصق الأب: الاسم والسعر من المنتج', () {
      final job = ProductLabelJob(product: parent(), copies: 2, barcode: '10000001');
      expect(job.displayName, 'قماش X');
      expect(job.price, 100);
    });

    test('ملصق الصنف: الاسم مركب والسعر من الصنف لو موجود', () {
      final job = ProductLabelJob(
        product: parent(),
        variant: ProductVariant(id: 7, productId: 1, name: 'أحمر', quantity: 10, price: 120),
        copies: 1,
        barcode: '20000007',
      );
      expect(job.displayName, 'قماش X — أحمر');
      expect(job.price, 120);
    });

    test('ملصق الصنف بلا سعر: يرث سعر الأب', () {
      final job = ProductLabelJob(
        product: parent(),
        variant: ProductVariant(id: 8, productId: 1, name: 'أزرق', quantity: 5),
        copies: 3,
        barcode: '20000008',
      );
      expect(job.displayName, 'قماش X — أزرق');
      expect(job.price, 100);
    });
  });
}
