import 'package:barcode/barcode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/label_print_service.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Suite 2: Barcode & Persistent QR Code Page URL (FEAT-017)', () {
    test('1. Default settings return correct initial unconfigured states', () async {
      expect(await SettingsService.getLabelShowQr(), isNull);
      expect(await SettingsService.getLabelShowPrice(), isTrue);
      expect(await SettingsService.getBusinessPageUrl(), isEmpty);
    });

    test('2. Business Page URL persistence with trimming and getBusinessInfo sync', () async {
      const sampleUrl = 'https://facebook.com/my_clothing_store';
      await SettingsService.setBusinessPageUrl('   $sampleUrl   ');

      expect(await SettingsService.getBusinessPageUrl(), equals(sampleUrl));

      final businessInfo = await SettingsService.getBusinessInfo();
      expect(businessInfo['pageUrl'], equals(sampleUrl));
    });

    test('3. Label QR and Price toggle persistence across multiple writes/reads', () async {
      await SettingsService.setLabelShowQr(true);
      await SettingsService.setLabelShowPrice(false);

      expect(await SettingsService.getLabelShowQr(), isTrue);
      expect(await SettingsService.getLabelShowPrice(), isFalse);

      await SettingsService.setLabelShowQr(false);
      await SettingsService.setLabelShowPrice(true);

      expect(await SettingsService.getLabelShowQr(), isFalse);
      expect(await SettingsService.getLabelShowPrice(), isTrue);
    });

    test('4. Barcode.qrCode generates valid QR matrix for normal and UTM URLs', () {
      final qr = Barcode.qrCode(
        errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
      );

      const standardUrl = 'https://facebook.com/store';
      expect(qr.isValid(standardUrl), isTrue);
      final standardMatrix = qr.make(standardUrl, width: 80, height: 80);
      expect(standardMatrix, isNotEmpty);

      const longUtmUrl =
          'https://example.com/store?utm_source=thermal_label&utm_medium=qr&utm_campaign=summer_promo_2026';
      expect(qr.isValid(longUtmUrl), isTrue);
      final utmMatrix = qr.make(longUtmUrl, width: 100, height: 100);
      expect(utmMatrix, isNotEmpty);

      expect(qr.isValid(''), isFalse);
    });

    test('5. ProductLabelJob correctly formats Parent and Variant labels', () {
      final parentProduct = Product(
        id: 10,
        name: 'تيشيرت قطن',
        quantity: 25,
        price: 250,
        minStockLevel: 2,
        barneka: false,
      );

      final parentJob = ProductLabelJob(
        product: parentProduct,
        copies: 2,
        barcode: '10000010',
      );
      expect(parentJob.displayName, equals('تيشيرت قطن'));
      expect(parentJob.price, equals(250));
      expect(parentJob.barcode, equals('10000010'));

      final variantProduct = ProductVariant(
        id: 101,
        productId: 10,
        name: 'أسود L',
        quantity: 10,
        price: 270,
        barcode: '20000101',
      );

      final variantJob = ProductLabelJob(
        product: parentProduct,
        variant: variantProduct,
        copies: 1,
        barcode: '20000101',
      );
      expect(variantJob.displayName, equals('تيشيرت قطن — أسود L'));
      expect(variantJob.price, equals(270));
      expect(variantJob.barcode, equals('20000101'));

      final variantInheritPrice = ProductVariant(
        id: 102,
        productId: 10,
        name: 'أبيض M',
        quantity: 15,
        price: null,
      );
      final inheritJob = ProductLabelJob(
        product: parentProduct,
        variant: variantInheritPrice,
        copies: 1,
        barcode: '20000102',
      );
      expect(inheritJob.price, equals(250));
    });

    test('6. PDF Document Builder produces valid document with QR code and Barcode side-by-side', () async {
      final product = Product(
        id: 5,
        name: 'بنطلون جينز',
        quantity: 20,
        price: 350,
        minStockLevel: 1,
        barneka: false,
      );

      final job = ProductLabelJob(
        product: product,
        copies: 1,
        barcode: '10000005',
      );

      final docWithQr = await LabelPrintService.buildLabelDocument(
        jobs: [job],
        companyName: 'بوتيك الأناقة',
        showPrice: true,
        widthMm: 58,
        heightMm: 40,
        qrData: 'https://facebook.com/boutique',
      );

      final bytesWithQr = await docWithQr.save();
      expect(bytesWithQr, isNotEmpty);
      expect(bytesWithQr.length, greaterThan(500));

      // Also verify build without QR data (backward compatible barcode only)
      final docWithoutQr = await LabelPrintService.buildLabelDocument(
        jobs: [job],
        companyName: 'بوتيك الأناقة',
        showPrice: true,
        widthMm: 50,
        heightMm: 30,
        qrData: null,
      );

      final bytesWithoutQr = await docWithoutQr.save();
      expect(bytesWithoutQr, isNotEmpty);
      expect(bytesWithoutQr.length, greaterThan(500));
    });
  });
}
