import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/services/license_entitlement.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';
import 'package:pos_offline_desktop/services/security_service.dart';

/// BUG-018 — entitlement enforcement.
///
/// Before this, "may this install use manufacturing?" had three answers that
/// disagreed, and the router and the DAOs never asked at all. These tests pin
/// the single answer and pin the two deliberate policy differences:
/// navigation fails OPEN while the snapshot is cold, writes fail CLOSED.
void main() {
  final entitlement = LicenseEntitlement.instance;

  tearDown(() => entitlement.reset());

  License licenseWith(List<String> features) => License(
    licenseKey: 'TEST',
    deviceFingerprint: 'x',
    type: LicenseType.professional,
    issueDate: DateTime.now().subtract(const Duration(days: 1)),
    expiryDate: DateTime.now().add(const Duration(days: 365)),
    features: features,
    maxUsers: 10,
    companyName: '',
    contactEmail: '',
    hardwareId: 'x',
  );

  group('the snapshot decides, and only the snapshot', () {
    test('a granted feature is allowed', () {
      entitlement.update(licenseWith(['pos', 'manufacturing']));
      expect(entitlement.grants('manufacturing'), isTrue);
    });

    test('a feature the license does not carry is refused', () {
      entitlement.update(licenseWith(['pos', 'cash_sales']));
      expect(entitlement.grants('manufacturing'), isFalse);
      expect(entitlement.grants('custody'), isFalse);
      expect(entitlement.grants('damaged_goods'), isFalse);
    });

    test('core features are always granted, even with an empty license', () {
      entitlement.update(licenseWith([]));
      for (final f in LicenseEntitlement.coreFeatures) {
        expect(entitlement.grants(f), isTrue, reason: f);
      }
    });

    test('a null or expired license grants nothing sellable', () {
      entitlement.update(null);
      expect(entitlement.isLoaded, isTrue);
      expect(entitlement.grants('manufacturing'), isFalse);
    });

    test('an expired license is not treated as a grant', () {
      entitlement.update(
        License(
          licenseKey: 'TEST',
          deviceFingerprint: 'x',
          type: LicenseType.professional,
          issueDate: DateTime.now().subtract(const Duration(days: 400)),
          expiryDate: DateTime.now().subtract(const Duration(days: 1)),
          features: const ['manufacturing', 'custody'],
          maxUsers: 10,
          companyName: '',
          contactEmail: '',
          hardwareId: 'x',
        ),
      );
      expect(
        entitlement.grants('manufacturing'),
        isFalse,
        reason: 'an expired license must not keep a module open',
      );
    });
  });

  group('the wildcard markers both work — the bug this replaced', () {
    // isFeatureEnabledProvider accepted '*' and 'all'; FeatureGateService
    // accepted only '*'. A legacy license carrying 'all' was therefore open on
    // one screen and locked on another at the same moment.
    test("a legacy 'all' marker grants everything", () {
      entitlement.update(licenseWith(['all']));
      expect(entitlement.grants('manufacturing'), isTrue);
      expect(entitlement.grants('custody'), isTrue);
      expect(entitlement.grants('damaged_goods'), isTrue);
      expect(entitlement.grants('payroll'), isTrue);
    });

    test("a modern '*' marker grants everything", () {
      entitlement.update(licenseWith(['*']));
      expect(entitlement.grants('manufacturing'), isTrue);
      expect(entitlement.grants('custody'), isTrue);
    });
  });

  group('route → feature mapping', () {
    test('a gated route resolves to its feature', () {
      expect(
        LicenseEntitlement.featureForRoute('/manufacturing/orders'),
        'manufacturing',
      );
      expect(
        LicenseEntitlement.featureForRoute('/manufacturing/orders/17'),
        'manufacturing',
        reason: 'nested paths must inherit the module gate',
      );
      expect(
        LicenseEntitlement.featureForRoute('/manufacturing/bom'),
        'manufacturing',
      );
      expect(LicenseEntitlement.featureForRoute('/custody'), 'custody');
      expect(
        LicenseEntitlement.featureForRoute('/damaged-items'),
        'damaged_goods',
      );
    });

    test('ungated routes resolve to nothing', () {
      expect(LicenseEntitlement.featureForRoute('/'), isNull);
      expect(LicenseEntitlement.featureForRoute('/login'), isNull);
      expect(LicenseEntitlement.featureForRoute('/backup'), isNull);
    });

    test('a similar prefix is not mistaken for a gated route', () {
      // Guards against a prefix match on '/custodyXYZ' or '/damaged-items-extra'.
      expect(LicenseEntitlement.featureForRoute('/custodyx'), isNull);
      expect(LicenseEntitlement.featureForRoute('/damaged-items-list'), isNull);
    });
  });

  group('the two policies differ on purpose', () {
    test('a write fails CLOSED while the snapshot is cold', () {
      entitlement.reset();
      expect(entitlement.isLoaded, isFalse);
      expect(
        entitlement.grants('manufacturing'),
        isFalse,
        reason: 'a licence must be proven before a write, not assumed',
      );
      expect(
        () => entitlement.require('manufacturing'),
        throwsA(isA<FeatureNotLicensedException>()),
      );
    });

    test('navigation fails OPEN while the snapshot is cold', () {
      entitlement.reset();
      expect(
        entitlement.allowsNavigation('/manufacturing/orders'),
        isTrue,
        reason:
            'a transient read failure must not lock the cashier out of '
            'the register',
      );
      expect(entitlement.allowsNavigation('/custody'), isTrue);
    });

    test('navigation blocks once the snapshot says no', () {
      entitlement.update(licenseWith(['pos']));
      expect(entitlement.allowsNavigation('/manufacturing/orders'), isFalse);
      expect(entitlement.allowsNavigation('/custody'), isFalse);
      expect(entitlement.allowsNavigation('/damaged-items'), isFalse);
      expect(
        entitlement.allowsNavigation('/'),
        isTrue,
        reason: 'ungated routes are never affected',
      );
    });

    test('navigation allows what the license grants', () {
      entitlement.update(licenseWith(['manufacturing', 'custody']));
      expect(entitlement.allowsNavigation('/manufacturing/orders'), isTrue);
      expect(entitlement.allowsNavigation('/custody'), isTrue);
      expect(entitlement.allowsNavigation('/damaged-items'), isFalse);
    });
  });

  group('require() refuses the write and names the reason', () {
    test('a granted feature passes silently', () {
      entitlement.update(licenseWith(['manufacturing']));
      expect(() => entitlement.require('manufacturing'), returnsNormally);
    });

    test('a refused feature throws with a usable Arabic message', () {
      entitlement.update(licenseWith(['pos']));
      try {
        entitlement.require('manufacturing', operation: 'إنشاء أمر تصنيع');
        fail('should have thrown');
      } on FeatureNotLicensedException catch (e) {
        expect(e.feature, 'manufacturing');
        expect(
          e.toString(),
          contains('التصنيع'),
          reason:
              'the operator must see an Arabic module name, not the '
              'internal key "manufacturing"',
        );
        expect(e.toString(), isNot(contains('manufacturing')));
        expect(
          e.toString(),
          contains('إنشاء أمر تصنيع'),
          reason: 'the operator must be told WHICH action was refused',
        );
      }
    });
  });

  group('LicenseManager keeps the snapshot current', () {
    test('reading the license refreshes the snapshot', () async {
      await SecurityService.initialize();
      final dir = await Directory.systemTemp.createTemp('entitlement_test_');
      SecureLicenseStorage.useDirectory(dir);
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      entitlement.reset();
      expect(entitlement.isLoaded, isFalse);

      // No license file in this temp store, so the read yields null — the point
      // is that an ordinary read settles the snapshot, which is what makes the
      // synchronous router and DAO guards safe to rely on.
      await LicenseManager().getCurrentLicense();
      expect(entitlement.isLoaded, isTrue);
      expect(entitlement.grants('manufacturing'), isFalse);
    });
  });
}
