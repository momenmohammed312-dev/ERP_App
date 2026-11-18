import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/core/router/go_router.dart';
import 'package:pos_offline_desktop/services/hardware_id_service.dart';
import 'package:pos_offline_desktop/services/license_entitlement.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';
import 'package:pos_offline_desktop/services/security_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression suite for BUG-037 (BUG-TRIAL-7DAYS):
/// - Differentiating Permanent Free builds vs Time-Limited Trial builds
/// - Hard expiry enforcement + visible expired status (never returns null)
/// - In-place upgrade from active or expired trial to a paid signed lease
/// - Non-disruptive clock handling (no lockout on accidental clock shift)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const machine = 'TRIAL-TEST-MACHINE';
  const install = 'TRIAL-TEST-INSTALL';

  late Directory tmp;
  late RSAPrivateKey serverKey;
  final manager = LicenseManager();

  setUpAll(() {
    serverKey = RSAPrivateKey(
      File('test/fixtures/license/test_private.pem').readAsStringSync(),
    );
  });

  setUp(() async {
    await SecurityService.initialize();
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('trial_enforcement_test_');
    SecureLicenseStorage.useDirectory(tmp);
    HardwareIdService.resetForTesting();
    HardwareIdService.debugMachineGuid = machine;
    HardwareIdService.debugInstallUuid = install;
    LicenseConfig.publicKeyOverride =
        File('test/fixtures/license/test_public.pem').readAsStringSync();
    LicenseConfig.isFreeVersionOverride = null;
    LicenseConfig.freeTrialDaysOverride = null;
    LicenseConfig.freeTrialMinutesOverride = null;
    LicenseManager.nowProvider = DateTime.now;
    LicenseEntitlement.instance.reset();
  });

  tearDown(() async {
    LicenseConfig.isFreeVersionOverride = null;
    LicenseConfig.freeTrialDaysOverride = null;
    LicenseConfig.freeTrialMinutesOverride = null;
    LicenseConfig.publicKeyOverride = null;
    LicenseManager.nowProvider = DateTime.now;
    HardwareIdService.resetForTesting();
    LicenseEntitlement.instance.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String makePaidDocument({
    String key = 'MO2-UPGRADE-001',
    String plan = 'professional',
    List<String> features = const ['pos', 'cash_sales', 'customers'],
    Duration validFor = const Duration(days: 365),
  }) {
    final now = LicenseManager.nowProvider();
    int secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    final token = JWT({
      'license_key': key,
      'machine_guid': machine,
      'install_uuid': install,
      'hardware_id': '',
      'plan': plan,
      'features': features,
      'license_expires_at': now.add(validFor).toIso8601String(),
      'status': 'active',
      'iat': secs(now.subtract(const Duration(minutes: 1))),
      'exp': secs(now.add(validFor)),
    }).sign(
      serverKey,
      algorithm: JWTAlgorithm.RS256,
      noIssueAt: true,
    );
    return jsonEncode({
      'madar_license_envelope': 'v1',
      'lease': token,
    });
  }

  group('1. Build-mode classification (LicenseConfig)', () {
    test('FREE_VERSION=false -> standard licensed mode', () {
      LicenseConfig.isFreeVersionOverride = false;
      LicenseConfig.freeTrialDaysOverride = 36500;

      expect(LicenseConfig.isFreeVersion, isFalse);
      expect(LicenseConfig.isTimeLimitedTrial, isFalse);
      expect(LicenseConfig.isPermanentFreeVersion, isFalse);
    });

    test('FREE_VERSION=true, FREE_TRIAL_DAYS=36500 -> permanent free mode', () {
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 36500;

      expect(LicenseConfig.isFreeVersion, isTrue);
      expect(LicenseConfig.isPermanentFreeVersion, isTrue);
      expect(LicenseConfig.isTimeLimitedTrial, isFalse);
    });

    test('FREE_VERSION=true, FREE_TRIAL_DAYS=7 -> time-limited trial mode', () {
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 7;

      expect(LicenseConfig.isFreeVersion, isTrue);
      expect(LicenseConfig.isTimeLimitedTrial, isTrue);
      expect(LicenseConfig.isPermanentFreeVersion, isFalse);
    });
  });

  group('2. Active 7-day trial (Day 0..6)', () {
    test('first launch starts 7-day trial and grants features', () async {
      final t0 = DateTime(2026, 11, 1, 10, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 7;

      final license = await manager.getCurrentLicense();
      expect(license, isNotNull);
      expect(license!.type, LicenseType.trial);
      expect(license.isExpired, isFalse);
      expect(license.isValid, isTrue);
      expect(license.daysRemaining, greaterThanOrEqualTo(6));

      expect(await manager.isLicenseActive(), isTrue);
      expect(await manager.hasFeature('manufacturing'), isTrue);
      expect(LicenseEntitlement.instance.grants('manufacturing'), isTrue);

      final stored = await SecureLicenseStorage.read();
      expect(stored, isNotNull);
      expect(stored!.firstRunDate, t0);
    });

    test('Day 6 + 23h (1 hour left) stays active with 0 whole days', () async {
      final t0 = DateTime(2026, 11, 1, 10, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 7;

      await manager.getCurrentLicense();

      LicenseManager.nowProvider =
          () => t0.add(const Duration(days: 6, hours: 23));
      final license = await manager.getCurrentLicense();

      expect(license, isNotNull);
      expect(license!.isExpired, isFalse);
      expect(license.isValid, isTrue);
      expect(license.daysRemaining, 0);
      expect(await manager.isLicenseActive(), isTrue);
    });
  });

  group('3. Expired 7-day trial (Day 7+)', () {
    for (final entry in <String, Duration>{
      'Day 7 + 1 second': const Duration(days: 7, seconds: 1),
      'Day 8': const Duration(days: 8),
      'Day 30': const Duration(days: 30),
    }.entries) {
      test('${entry.key}: returns expired License (not null) & blocks access',
          () async {
        final t0 = DateTime(2026, 11, 1, 10, 0, 0);
        LicenseManager.nowProvider = () => t0;
        LicenseConfig.isFreeVersionOverride = true;
        LicenseConfig.freeTrialDaysOverride = 7;

        await manager.getCurrentLicense();

        LicenseManager.nowProvider = () => t0.add(entry.value);

        final license = await manager.getCurrentLicense();
        expect(
          license,
          isNotNull,
          reason: 'Badge must remain visible as expired instead of returning null',
        );
        expect(license!.type, LicenseType.trial);
        expect(license.isExpired, isTrue);
        expect(license.isValid, isFalse);
        expect(license.daysRemaining, 0);

        expect(await manager.isLicenseActive(), isFalse);
        expect(await manager.isLicenseValid(), isFalse);
        expect(await manager.hasFeature('manufacturing'), isFalse);
        expect(await manager.canAddUser(0), isFalse);
        expect(LicenseEntitlement.instance.grants('manufacturing'), isFalse);
      });
    }
  });

  group('4. Permanent Free version remains unaffected', () {
    test('FREE_VERSION=true, FREE_TRIAL_DAYS=36500 stays unlocked', () async {
      final t0 = DateTime(2026, 11, 1, 10, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 36500;

      final first = await manager.getCurrentLicense();
      expect(first, isNotNull);
      expect(first!.type, LicenseType.free);

      LicenseManager.nowProvider = () => t0.add(const Duration(days: 400));
      expect(await manager.isLicenseActive(), isTrue);
      expect(await manager.hasFeature('manufacturing'), isTrue);
      expect(LicenseEntitlement.instance.grants('manufacturing'), isTrue);
    });
  });

  group('5. In-place upgrade from 7-day trial to Paid .madarlicense', () {
    test('expired trial can import paid .madarlicense and keep data/firstRunDate',
        () async {
      final t0 = DateTime(2026, 11, 1, 10, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 7;

      // Start trial, then expire it on Day 10.
      await manager.getCurrentLicense();
      LicenseManager.nowProvider = () => t0.add(const Duration(days: 10));
      expect(await manager.isLicenseActive(), isFalse);

      // Upgrade in-place with a signed document granting only pos/cash_sales/customers.
      final importRes = await manager.importLicenseDocument(
        makePaidDocument(
          key: 'MO2-UPGRADE-001',
          plan: 'professional',
          features: const ['pos', 'cash_sales', 'customers'],
        ),
      );
      expect(importRes.isValid, isTrue, reason: importRes.errorMessage ?? '');

      final upgraded = await manager.getCurrentLicense();
      expect(upgraded, isNotNull);
      expect(upgraded!.licenseKey, 'MO2-UPGRADE-001');
      expect(upgraded.type, LicenseType.professional);
      expect(upgraded.isExpired, isFalse);
      expect(upgraded.isValid, isTrue);

      expect(await manager.isLicenseActive(), isTrue);
      // Paid license entitlements must be enforced strictly (no trial wildcard leak).
      expect(LicenseEntitlement.instance.grants('customers'), isTrue);
      expect(LicenseEntitlement.instance.grants('manufacturing'), isFalse);

      final stored = await SecureLicenseStorage.read();
      expect(stored!.firstRunDate, t0);
    });

    test('active trial can also upgrade in-place via Settings path', () async {
      final t0 = DateTime(2026, 11, 1, 10, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 7;

      await manager.getCurrentLicense();
      LicenseManager.nowProvider = () => t0.add(const Duration(days: 2));

      final importRes = await manager.importLicenseDocument(
        makePaidDocument(
          key: 'MO2-UPGRADE-002',
          plan: 'standard',
          features: const ['pos', 'cash_sales', 'credit_sales'],
        ),
      );
      expect(importRes.isValid, isTrue);

      final upgraded = await manager.getCurrentLicense();
      expect(upgraded!.licenseKey, 'MO2-UPGRADE-002');
      expect(upgraded.type, LicenseType.standard);
      expect(await manager.isLicenseActive(), isTrue);
    });
  });

  group('6. Non-disruptive clock handling on 7-day trial', () {
    test('small backward shift (-12h / DST) keeps trial active', () async {
      final t0 = DateTime(2026, 11, 1, 10, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 7;

      await manager.getCurrentLicense();

      LicenseManager.nowProvider = () => t0.subtract(const Duration(hours: 12));
      final license = await manager.getCurrentLicense();

      expect(license, isNotNull);
      expect(license!.isExpired, isFalse);
      expect(await manager.isLicenseActive(), isTrue);
      expect(license.daysRemaining, lessThanOrEqualTo(7));
    });

    test('accidental CMOS reset far in past does NOT lock user and clamps daysRemaining',
        () async {
      final t0 = DateTime(2026, 11, 1, 10, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 7;

      await manager.getCurrentLicense();

      // Clock accidentally resets 3 years into the past.
      LicenseManager.nowProvider = () => DateTime(2023, 1, 1, 8, 0, 0);
      final license = await manager.getCurrentLicense();

      expect(license, isNotNull);
      expect(license!.isExpired, isFalse);
      expect(await manager.isLicenseActive(), isTrue);
      expect(
        license.daysRemaining,
        lessThanOrEqualTo(7),
        reason: 'daysRemaining must never explode to 1000+ days on backward reset',
      );
    });

    test('accidental future jump then fixed back self-heals cleanly', () async {
      final t0 = DateTime(2026, 11, 1, 10, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 7;

      await manager.getCurrentLicense();

      // Accidental jump 30 days ahead.
      LicenseManager.nowProvider = () => t0.add(const Duration(days: 30));
      expect(await manager.isLicenseActive(), isFalse);
      final afterJump = await SecureLicenseStorage.read();
      expect(
        afterJump!.sessionElapsedMs,
        0,
        reason: 'a single >24h jump must not inflate sessionElapsedMs',
      );

      // User fixes system clock back to Day 3.
      LicenseManager.nowProvider = () => t0.add(const Duration(days: 3));
      expect(await manager.isLicenseActive(), isTrue);

      final healed = await SecureLicenseStorage.read();
      expect(healed!.lastCheckTime, t0.add(const Duration(days: 3)));
      expect(healed.sessionElapsedMs, 0);
    });

    test('cumulative active usage >= 7 days expires trial even if clock is set back',
        () async {
      final t0 = DateTime(2026, 11, 1, 10, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 7;

      await manager.getCurrentLicense();

      // Seed 7 days of legitimately accumulated active session time.
      final existing = (await SecureLicenseStorage.read())!;
      await SecureLicenseStorage.write(
        existing.copyWith(
          sessionElapsedMs: const Duration(days: 7).inMilliseconds,
          lastCheckTime: t0.add(const Duration(days: 2)),
        ),
      );

      // User sets clock back to Day 2.
      LicenseManager.nowProvider = () => t0.add(const Duration(days: 2));
      final license = await manager.getCurrentLicense();

      expect(license, isNotNull);
      expect(license!.isExpired, isTrue);
      expect(license.isValid, isFalse);
      expect(await manager.isLicenseActive(), isFalse);
    });
  });

  group('7. Router gate pure function (licenseGateRedirect)', () {
    test('permanent free build never redirects', () {
      expect(
        licenseGateRedirect(
          location: '/',
          isPermanentFreeVersion: true,
          isLicenseLoaded: true,
          hasValidLicense: false,
        ),
        isNull,
      );
    });

    test('while license snapshot is not loaded yet, stays lenient', () {
      expect(
        licenseGateRedirect(
          location: '/',
          isPermanentFreeVersion: false,
          isLicenseLoaded: false,
          hasValidLicense: false,
        ),
        isNull,
      );
      expect(
        licenseGateRedirect(
          location: '/splash',
          isPermanentFreeVersion: false,
          isLicenseLoaded: false,
          hasValidLicense: false,
        ),
        isNull,
      );
    });

    test('valid license allows normal navigation', () {
      for (final path in ['/', '/login', '/backup', '/manufacturing/orders']) {
        expect(
          licenseGateRedirect(
            location: path,
            isPermanentFreeVersion: false,
            isLicenseLoaded: true,
            hasValidLicense: true,
          ),
          isNull,
          reason: path,
        );
      }
    });

    test('expired/missing license redirects protected routes to /activation',
        () {
      for (final path in ['/', '/login', '/setup', '/manufacturing/orders']) {
        expect(
          licenseGateRedirect(
            location: path,
            isPermanentFreeVersion: false,
            isLicenseLoaded: true,
            hasValidLicense: false,
          ),
          '/activation',
          reason: path,
        );
      }
    });

    test('/activation and /splash never redirect-loop when expired', () {
      for (final path in ['/activation', '/splash']) {
        expect(
          licenseGateRedirect(
            location: path,
            isPermanentFreeVersion: false,
            isLicenseLoaded: true,
            hasValidLicense: false,
          ),
          isNull,
          reason: path,
        );
      }
    });
  });

  group('8. Minute-based trial mode (FREE_TRIAL_MINUTES=1)', () {
    test('classification marks FREE_TRIAL_MINUTES=1 as time-limited trial', () {
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialDaysOverride = 36500;
      LicenseConfig.freeTrialMinutesOverride = 1;

      expect(LicenseConfig.isTimeLimitedTrial, isTrue);
      expect(LicenseConfig.isPermanentFreeVersion, isFalse);
      expect(LicenseConfig.freeTrialDuration, const Duration(minutes: 1));
    });

    test('stays active at 30s and expires cleanly at 61s', () async {
      final t0 = DateTime(2026, 11, 18, 23, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialMinutesOverride = 1;

      final initial = await manager.getCurrentLicense();
      expect(initial, isNotNull);
      expect(initial!.type, LicenseType.trial);
      expect(initial.licenseKey, 'TRIAL_1_MIN');
      expect(initial.daysRemaining, 0);
      expect(initial.isExpired, isFalse);
      expect(await manager.isLicenseActive(), isTrue);

      // At 30 seconds: still active.
      LicenseManager.nowProvider = () => t0.add(const Duration(seconds: 30));
      final at30s = await manager.getCurrentLicense();
      expect(at30s, isNotNull);
      expect(at30s!.isExpired, isFalse);
      expect(at30s.daysRemaining, 0);
      expect(await manager.isLicenseActive(), isTrue);

      // At 61 seconds: expired, non-null License, access blocked.
      LicenseManager.nowProvider = () => t0.add(const Duration(seconds: 61));
      final at61s = await manager.getCurrentLicense();
      expect(at61s, isNotNull);
      expect(at61s!.type, LicenseType.trial);
      expect(at61s.isExpired, isTrue);
      expect(at61s.isValid, isFalse);
      expect(await manager.isLicenseActive(), isFalse);
      expect(await manager.hasFeature('manufacturing'), isFalse);
      expect(LicenseEntitlement.instance.grants('manufacturing'), isFalse);
    });

    test('1-minute expired trial can upgrade in-place to paid .madarlicense',
        () async {
      final t0 = DateTime(2026, 11, 18, 23, 0, 0);
      LicenseManager.nowProvider = () => t0;
      LicenseConfig.isFreeVersionOverride = true;
      LicenseConfig.freeTrialMinutesOverride = 1;

      await manager.getCurrentLicense();
      LicenseManager.nowProvider = () => t0.add(const Duration(seconds: 65));
      expect(await manager.isLicenseActive(), isFalse);

      final res = await manager.importLicenseDocument(
        makePaidDocument(
          key: 'MO2-MIN-UPGRADE',
          plan: 'professional',
          features: const ['pos', 'cash_sales', 'manufacturing'],
        ),
      );
      expect(res.isValid, isTrue, reason: res.errorMessage ?? '');
      expect(await manager.isLicenseActive(), isTrue);
      expect((await manager.getCurrentLicense())!.licenseKey, 'MO2-MIN-UPGRADE');
      expect(LicenseEntitlement.instance.grants('manufacturing'), isTrue);
    });
  });
}
