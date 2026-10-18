import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FEAT-017 — Barcode QR and Label Settings Persistence', () {
    test('Default label settings return expected defaults when uninitialized', () async {
      expect(await SettingsService.getLabelShowQr(), isNull);
      expect(await SettingsService.getLabelShowPrice(), isTrue);
      expect(await SettingsService.getBusinessPageUrl(), isEmpty);
    });

    test('Persists and retrieves business page url in SettingsService and getBusinessInfo', () async {
      const url = 'https://facebook.com/my_store_page';
      await SettingsService.setBusinessPageUrl(url);

      expect(await SettingsService.getBusinessPageUrl(), equals(url));

      final info = await SettingsService.getBusinessInfo();
      expect(info['pageUrl'], equals(url));
    });

    test('Persists and retrieves labelShowQr and labelShowPrice flags', () async {
      // Test setting show QR to true and false
      await SettingsService.setLabelShowQr(true);
      expect(await SettingsService.getLabelShowQr(), isTrue);

      await SettingsService.setLabelShowQr(false);
      expect(await SettingsService.getLabelShowQr(), isFalse);

      // Test setting show Price to false and true
      await SettingsService.setLabelShowPrice(false);
      expect(await SettingsService.getLabelShowPrice(), isFalse);

      await SettingsService.setLabelShowPrice(true);
      expect(await SettingsService.getLabelShowPrice(), isTrue);
    });

    test('Page URL and label settings remain stable across multiple calls and reads', () async {
      const url = 'https://instagram.com/fashion_shop_egy';
      await SettingsService.setBusinessPageUrl('  $url  '); // test trimming
      await SettingsService.setLabelShowQr(true);
      await SettingsService.setLabelShowPrice(true);

      // Perform multiple consecutive reads
      for (int i = 0; i < 5; i++) {
        expect(await SettingsService.getBusinessPageUrl(), equals(url));
        expect(await SettingsService.getLabelShowQr(), isTrue);
        expect(await SettingsService.getLabelShowPrice(), isTrue);

        final businessInfo = await SettingsService.getBusinessInfo();
        expect(businessInfo['pageUrl'], equals(url));
      }
    });

    test('Overwriting Page URL updates value immediately and stably', () async {
      await SettingsService.setBusinessPageUrl('https://first-url.com');
      expect(await SettingsService.getBusinessPageUrl(), equals('https://first-url.com'));

      await SettingsService.setBusinessPageUrl('https://second-url.com');
      expect(await SettingsService.getBusinessPageUrl(), equals('https://second-url.com'));

      final info = await SettingsService.getBusinessInfo();
      expect(info['pageUrl'], equals('https://second-url.com'));
    });
  });
}
