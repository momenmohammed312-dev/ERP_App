import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';

/// Regression guard for BUG-009 — a license plan name that does not match
/// `LicenseType` silently downgraded the customer to a ONE-USER license.
///
/// The failure chain was:
///
///   `plan: "yearly"`  (admin_dashboard/src/config/modules.js LICENSE_PLANS)
///     → `LicenseType.values.firstWhere((t) => t.name == plan)`
///     → no match  →  `orElse: () => LicenseType.basic`
///     → `_getMaxUsersForType(basic)` == 1
///     → `UserSessionService.canAddUser()` / `canUserLogin()` block every
///        employee beyond the first
///
/// The list below is copied from the two real producers of `plan` values so
/// this test fails the moment either of them adds a new identifier without a
/// matching entry in `LicensePlans`.
void main() {
  License licenseWithPlan(String plan, {int? maxUsers}) => License.fromJson({
        'license_key': 'POS-TEST-0001',
        'device': 'UNBOUND',
        'type': plan,
        'issue_date': '2026-01-01T00:00:00.000',
        'expiry': '2027-01-01T00:00:00.000',
        'features': ['pos', 'inventory'],
        'max_users': maxUsers ?? 5,
        'company_name': 'عميل تجريبي',
        'contact_email': 'test@example.invalid',
        'signature': null,
        'hardware_id': null,
      });

  /// Mirrors `LicenseManager._getMaxUsersForType`, which is what actually
  /// drives `canAddUser` / `canUserLogin` / `getMaxUsers`.
  int maxUsersFor(LicenseType type) => switch (type) {
        LicenseType.free => 999,
        LicenseType.trial => 1,
        LicenseType.basic => 1,
        LicenseType.standard => 3,
        LicenseType.professional => 5,
        LicenseType.enterprise => 10,
      };

  group('BUG-009 — plan names emitted by the admin dashboard', () {
    // Source: admin_dashboard/src/config/modules.js → LICENSE_PLANS
    const dashboardPlans = ['trial', 'monthly', 'yearly', 'lifetime'];

    dashboardPlans.forEach((plan) {
      test('"$plan" resolves to a real LicenseType instead of throwing', () {
        expect(
          () => licenseWithPlan(plan),
          returnsNormally,
          reason: 'License.fromJson used to throw a StateError on "$plan", '
              'which surfaced to the customer as "no license"',
        );
      });
    });

    test('"yearly" is NOT downgraded to a single-user basic license', () {
      final license = licenseWithPlan('yearly');

      expect(
        license.type,
        LicenseType.professional,
        reason: 'a yearly subscriber must not resolve to basic',
      );
      expect(
        maxUsersFor(license.type),
        greaterThan(1),
        reason: 'THE BUG: a yearly customer was capped at maxUsers == 1, '
            'blocking every extra employee at login',
      );
    });

    test('"lifetime" is NOT downgraded to a single-user basic license', () {
      final license = licenseWithPlan('lifetime');
      expect(maxUsersFor(license.type), greaterThan(1));
    });

    test('"monthly" resolves to a multi-user plan', () {
      final license = licenseWithPlan('monthly');
      expect(license.type, LicenseType.standard);
      expect(maxUsersFor(license.type), 3);
    });
  });

  group('BUG-009 — plan names emitted by the license simulator', () {
    // Source: tools/simulator_db.json
    const simulatorPlans = ['standard', 'basic', 'professional', 'custom'];

    simulatorPlans.forEach((plan) {
      test('"$plan" resolves to a real LicenseType', () {
        expect(() => licenseWithPlan(plan), returnsNormally);
      });
    });

    test('"custom" is NOT downgraded to basic', () {
      final license = licenseWithPlan('custom');
      expect(license.type, LicenseType.professional);
      expect(maxUsersFor(license.type), greaterThan(1));
    });

    test('canonical tier names still map to themselves', () {
      expect(licenseWithPlan('basic').type, LicenseType.basic);
      expect(licenseWithPlan('standard').type, LicenseType.standard);
      expect(licenseWithPlan('professional').type, LicenseType.professional);
    });
  });

  group('BUG-009 — unknown and malformed plans degrade safely', () {
    test('an unknown plan never throws and never reaches 1 user silently', () {
      expect(() => licenseWithPlan('enterprise-plus'), returnsNormally);
      expect(
        licenseWithPlan('enterprise-plus').type,
        LicenseType.standard,
        reason: 'unknown plans degrade to the fallback, which is logged at '
            'runtime — a customer is never silently reduced to basic',
      );
    });

    test('a null plan degrades instead of throwing', () {
      expect(() => licenseWithPlan('null'), returnsNormally);
      expect(LicensePlans.resolve(null), isNull);
      expect(LicensePlans.resolveOrFallback(null), LicensePlans.fallbackName);
    });

    test('plan matching is case and whitespace tolerant', () {
      expect(LicensePlans.resolve('YEARLY'), 'professional');
      expect(LicensePlans.resolve('  Yearly  '), 'professional');
      expect(LicensePlans.resolve('LIFETIME'), 'professional');
      expect(LicensePlans.resolve(''), isNull);
      expect(LicensePlans.resolve('   '), isNull);
    });

    test('isUnknown flags exactly the unusable identifiers', () {
      expect(LicensePlans.isUnknown('yearly'), isFalse);
      expect(LicensePlans.isUnknown('lifetime'), isFalse);
      expect(LicensePlans.isUnknown('teleporting'), isTrue);
      expect(LicensePlans.isUnknown(null), isTrue);
    });
  });

  group('BUG-009 — features survive regardless of the plan name', () {
    test('the granted feature list is never touched by plan resolution', () {
      for (final plan in ['trial', 'monthly', 'yearly', 'lifetime', 'custom']) {
        final license = licenseWithPlan(plan);
        expect(
          license.features,
          ['pos', 'inventory'],
          reason: 'plan resolution must not alter entitlements for "$plan"',
        );
      }
    });
  });
}