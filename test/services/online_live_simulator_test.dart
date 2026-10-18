import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/hardware_id_service.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/online_license_service.dart';
import 'package:pos_offline_desktop/services/feature_gate_service.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory tmpDir;
  final onlineService = OnlineLicenseService();
  final gateService = FeatureGateService();
  final licenseManager = LicenseManager();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = await Directory.systemTemp.createTemp('live_sim_test_');
    SecureLicenseStorage.useDirectory(tmpDir);
    HardwareIdService.debugMachineGuid = 'LIVE-TEST-MACHINE-001';
    HardwareIdService.debugInstallUuid = 'LIVE-TEST-INSTALL-001';
    OnlineLicenseService.apiUrlOverride = 'http://localhost:8000/license_api';
  });

  tearDown(() async {
    HardwareIdService.resetForTesting();
    OnlineLicenseService.apiUrlOverride = null;
    SecureLicenseStorage.useDirectory(Directory.systemTemp);
    try {
      if (tmpDir.existsSync()) {
        tmpDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('E2E: Activate MO2-TEST-BASIC against Live Simulator and verify Feature Gating', () async {
    // 1. Activate basic license
    final result = await onlineService.activateLicense('MO2-TEST-BASIC');
    expect(result.isAllowed, isTrue, reason: 'Basic license should activate successfully: ${result.message}');

    // 2. Verify stored license
    final currentLicense = await licenseManager.getCurrentLicense();
    expect(currentLicense, isNotNull);
    expect(currentLicense!.isValid, isTrue);
    expect(currentLicense.licenseKey, equals('MO2-TEST-BASIC'));

    // 3. Verify Basic feature gating
    // Core features should be available
    expect(await gateService.hasFeature('inventory'), isTrue, reason: 'Inventory must be accessible in Basic');
    expect(await gateService.hasFeature('customers'), isTrue, reason: 'Customers must be accessible in Basic');
    expect(await gateService.hasFeature('reports'), isTrue, reason: 'Reports must be accessible in Basic');

    // Add-on modules MUST BE LOCKED in Basic
    expect(await gateService.hasFeature('staff_management'), isFalse, reason: 'Staff management must be LOCKED in Basic');
    expect(await gateService.hasFeature('custody'), isFalse, reason: 'Custody must be LOCKED in Basic');
    expect(await gateService.hasFeature('damaged_goods'), isFalse, reason: 'Damaged goods must be LOCKED in Basic');
    expect(await gateService.hasFeature('manufacturing'), isFalse, reason: 'Manufacturing must be LOCKED in Basic');
  });

  test('E2E: Upgrade to POS-NUR2-8921-X4K9 and verify Add-on Modules Unlock Dynamically', () async {
    // 1. Activate professional license with add-ons
    final result = await onlineService.activateLicense('POS-NUR2-8921-X4K9');
    expect(result.isAllowed, isTrue, reason: 'Professional license should activate successfully: ${result.message}');

    // 2. Verify add-on modules are now UNLOCKED
    expect(await gateService.hasFeature('staff_management'), isTrue, reason: 'Staff management should UNLOCK');
    expect(await gateService.hasFeature('custody'), isTrue, reason: 'Custody should UNLOCK');
    expect(await gateService.hasFeature('damaged_goods'), isTrue, reason: 'Damaged goods should UNLOCK');
    expect(await gateService.hasFeature('manufacturing'), isTrue, reason: 'Manufacturing should UNLOCK');
  });

  test('E2E: Suspended License POS-BRK9-5501-Q8Z1 is properly rejected', () async {
    final result = await onlineService.activateLicense('POS-BRK9-5501-Q8Z1');
    expect(result.isAllowed, isFalse);
    expect(result.status, equals(OnlineLicenseStatus.suspended));
  });

  test('E2E: Offline Resilience: License works offline without network call', () async {
    // 1. Activate
    await onlineService.activateLicense('POS-NUR2-8921-X4K9');

    // 2. Read offline
    final offlineLicense = await licenseManager.getCurrentLicense();
    expect(offlineLicense, isNotNull);
    expect(offlineLicense!.isValid, isTrue);
    expect(await gateService.hasFeature('staff_management'), isTrue);
  });
}
