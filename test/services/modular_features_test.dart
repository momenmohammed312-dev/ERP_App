import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/hardware_id_service.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'license_lease_test.dart';

void main() {
  late Directory tmp;
  final manager = LicenseManager();

  late RSAPrivateKey privKey;

  setUpAll(() {
    privKey = RSAPrivateKey(File('test/fixtures/license/test_private.pem').readAsStringSync());
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('modular_test_');
    SecureLicenseStorage.useDirectory(tmp);
    SharedPreferences.setMockInitialValues({});
    LicenseConfig.publicKeyOverride = File('test/fixtures/license/test_public.pem').readAsStringSync();
    HardwareIdService.debugMachineGuid = 'MACHINE-MODULAR';
    HardwareIdService.debugInstallUuid = 'INSTALL-MODULAR';
  });

  tearDown(() async {
    LicenseConfig.publicKeyOverride = null;
    HardwareIdService.debugMachineGuid = null;
    HardwareIdService.debugInstallUuid = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('Modular Feature Gating', () {
    test('Client with only basic modules cannot access manufacturing, custody, or staff', () async {
      // License with only POS, inventory, customers
      final token = makeLease(
        machine: 'MACHINE-MODULAR',
        install: 'INSTALL-MODULAR',
        features: ['pos', 'cash_sales', 'inventory', 'customers', 'reports'],
        key: privKey,
      );
      await manager.saveLease(token);

      expect(await manager.hasFeature('pos'), isTrue);
      expect(await manager.hasFeature('customers'), isTrue);
      expect(await manager.hasFeature('manufacturing'), isFalse);
      expect(await manager.hasFeature('staff_management'), isFalse);
      expect(await manager.hasFeature('custody'), isFalse);
      expect(await manager.hasFeature('damaged_goods'), isFalse);
    });

    test('Client upgraded with manufacturing and custody instantly gets access', () async {
      // Initial lease: no manufacturing
      final initialToken = makeLease(
        machine: 'MACHINE-MODULAR',
        install: 'INSTALL-MODULAR',
        features: ['pos', 'inventory'],
        key: privKey,
      );
      await manager.saveLease(initialToken);
      expect(await manager.hasFeature('manufacturing'), isFalse);

      // Server checkin renews with manufacturing enabled
      final upgradedToken = makeLease(
        machine: 'MACHINE-MODULAR',
        install: 'INSTALL-MODULAR',
        features: ['pos', 'inventory', 'manufacturing', 'custody'],
        key: privKey,
      );
      await manager.saveLease(upgradedToken);

      expect(await manager.hasFeature('manufacturing'), isTrue);
      expect(await manager.hasFeature('custody'), isTrue);
      expect(await manager.hasFeature('staff_management'), isFalse);
    });
  });
}
