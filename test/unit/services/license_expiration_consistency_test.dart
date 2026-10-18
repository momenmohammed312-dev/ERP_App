import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';

/// Regression guard for BUG-007 — trial expiration reported as "0 days"
/// (and negative days) while the license is still treated as valid.
///
/// The defect was three inconsistent expiry definitions living in one file:
///
///   1. `License.isExpired` (:48)     → `now > expiry + 7 days`  (GRACE)
///   2. `License.daysRemaining` (:69) → `expiry - now` in days  (NO grace,
///                                       truncated toward zero)
///   3. `LicenseManager.validateLicense` (:228) → `now > expiry` (NO grace)
///
/// Because (2) had no grace while (1) did, a license that ran out of time
/// still reported `isValid == true` for a full week while the UI showed
/// "0 يوم" and then negative day counts such as "-3 يوم".
///
/// ── APPROVED POLICY (owner decision, BUG-007 §5 option أ) ─────────────
/// HARD EXPIRY, NO GRACE. The instant `now` passes `expiryDate` the license
/// is expired. `daysRemaining` is clamped at zero and may never be negative.
/// A reported 0 therefore means "less than 24 hours left, or already expired"
/// and MUST be read together with `isExpired` — never on its own.
/// ───────────────────────────────────────────────────────────────────────
void main() {
  /// A license that is [pastExpiry] away from its expiry instant.
  ///
  /// `signature: null` short-circuits `isSignatureValid` to `true`, so these
  /// tests isolate the EXPIRY logic and cannot be masked by signing problems.
  License licenseEndingIn(Duration pastExpiry, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    return License(
      licenseKey: 'TEST-KEY',
      deviceFingerprint: 'free',
      type: LicenseType.trial,
      issueDate: reference.subtract(const Duration(days: 30)),
      expiryDate: reference.subtract(pastExpiry),
      features: const ['pos', 'cash_sales'],
      maxUsers: 1,
      companyName: 'Test',
      contactEmail: '',
      signature: null,
    );
  }

  group('BUG-007 — hard expiry, no grace period', () {
    // THE CUSTOMER-REPORTED CASE: after day 7 the counter went negative and
    // the app kept working. With the approved policy the license must be
    // dead the instant `now` passes expiryDate.
    const pastExpiry = <String, Duration>{
      '1 second past expiry': Duration(seconds: 1),
      '23 hours past expiry': Duration(hours: 23),
      '25 hours past expiry': Duration(hours: 25),
      '3 days past expiry': Duration(days: 3),
      '7 days past expiry': Duration(days: 7),
      '30 days past expiry': Duration(days: 30),
    };

    pastExpiry.forEach((label, offset) {
      test('isExpired immediately — $label', () {
        final license = licenseEndingIn(offset);
        expect(
          license.isExpired,
          isTrue,
          reason: '$label must read as expired under the hard-expiry policy. '
              'A grace period here is what let the customer keep working for '
              'a week past expiry while the badge showed a negative count.',
        );
        expect(
          license.isValid,
          isFalse,
          reason: '$label must not retain paid access',
        );
        expect(
          license.daysRemaining,
          0,
          reason: '$label must report 0 days, never a negative number',
        );
      });
    });

    test('isValid immediately BEFORE expiry — 1 hour left', () {
      final license = licenseEndingIn(const Duration(hours: -1));

      expect(
        license.isExpired,
        isFalse,
        reason: 'a customer with one hour of paid time left must keep working',
      );
      expect(
        license.isValid,
        isTrue,
        reason: 'hard expiry means hard expiry, not an early shutdown',
      );
      expect(
        license.daysRemaining,
        0,
        reason: 'less than 24 hours left truncates to 0 whole days',
      );
    });

    test('there is NO grace window: 1 second past expiry is already dead', () {
      final oneSecondAgo = licenseEndingIn(const Duration(seconds: 1));
      final oneHourAgo = licenseEndingIn(const Duration(hours: 1));

      expect(
        oneSecondAgo.isExpired,
        oneHourAgo.isExpired,
        reason: 'expiry must be a hard boundary — the historical 7-day grace '
            'must not reappear in any form',
      );
    });
  });

  group('BUG-007 — daysRemaining must never be negative', () {
    // Every one of these instants is INSIDE the current 7-day grace window,
    // so `isExpired` is false today — yet `daysRemaining` reports a negative
    // number, which the badge renders in green.
    const insideGrace = <String, Duration>{
      '1 hour past expiry': Duration(hours: 1),
      '25 hours past expiry': Duration(hours: 25),
      '3 days past expiry': Duration(days: 3),
      '6 days past expiry': Duration(days: 6),
    };

    insideGrace.forEach((label, offset) {
      test('daysRemaining is not negative — $label', () {
        final license = licenseEndingIn(offset);
        expect(
          license.daysRemaining,
          greaterThanOrEqualTo(0),
          reason: 'the badge renders "$label" as a negative day count in '
              'GREEN while the license is still usable. A negative day count '
              'is never a meaningful number to show a user.',
        );
      });
    });
  });

  group('BUG-007 — daysRemaining and isExpired must agree', () {
    test('an expired license reports 0 days and is not valid', () {
      final license = licenseEndingIn(const Duration(hours: 25));

      expect(license.isExpired, isTrue);
      expect(
        license.daysRemaining,
        0,
        reason: '3 days past expiry previously reported -3, which the badge '
            'rendered in green while the license still worked',
      );
      expect(
        license.isValid,
        isFalse,
        reason: 'isValid must follow isExpired — a customer past expiry must '
            'not retain full paid access',
      );
    });

    test('a license that ended 3 days ago is not reported as still valid', () {
      final license = licenseEndingIn(const Duration(days: 3));

      expect(
        license.isValid,
        isFalse,
        reason: 'the expiry date has passed; the UI must not imply otherwise',
      );
    });

    test('daysRemaining of 0 always pairs with a readable expiry state', () {
      // 0 is ambiguous by itself (under 24h left OR expired) — the two states
      // must be distinguishable through isExpired, and both must be legal.
      final expiringSoon = licenseEndingIn(const Duration(hours: -2));
      final alreadyGone = licenseEndingIn(const Duration(hours: 2));

      expect(expiringSoon.daysRemaining, 0);
      expect(expiringSoon.isExpired, isFalse);
      expect(alreadyGone.daysRemaining, 0);
      expect(alreadyGone.isExpired, isTrue);
      expect(
        expiringSoon.isValid,
        isNot(alreadyGone.isValid),
        reason: 'the two 0-day states must never resolve to the same access',
      );
    });
  });

  group('BUG-007 — monotonic countdown sanity', () {
    test('daysRemaining decreases as the expiry instant approaches', () {
      final week = licenseEndingIn(const Duration(days: -7));
      final day = licenseEndingIn(const Duration(days: -1));
      final hour = licenseEndingIn(const Duration(hours: -1));

      expect(
        week.daysRemaining,
        greaterThan(day.daysRemaining),
        reason: 'a license expiring next week must report more days than '
            'one expiring tomorrow',
      );
      expect(
        day.daysRemaining,
        greaterThanOrEqualTo(hour.daysRemaining),
        reason: 'a license expiring tomorrow must not report fewer days than '
            'one expiring in an hour',
      );
    });

    test('a license with 5 whole days left reports 5, not 4', () {
      final license = licenseEndingIn(const Duration(hours: -120)); // 5 days

      expect(
        license.daysRemaining,
        5,
        reason: '120 hours is exactly 5 whole days; truncation must not '
            'report a day less than the customer actually has',
      );
    });
  });

  group('BUG-007 — the countdown never contradicts itself', () {
    final boundaries = <String, Duration>{
      '30 days before expiry': Duration(days: -30),
      '7 days before expiry': Duration(days: -7),
      '25 hours before expiry': Duration(hours: -25),
      '2 hours before expiry': Duration(hours: -2),
      '1 hour before expiry': Duration(hours: -1),
      'exactly at expiry': Duration.zero,
      '1 second after expiry': Duration(seconds: 1),
      '23 hours after expiry': Duration(hours: 23),
      '25 hours after expiry': Duration(hours: 25),
      '3 days after expiry': Duration(days: 3),
      '7 days after expiry': Duration(days: 7),
      '8 days after expiry': Duration(days: 8),
    };

    boundaries.forEach((label, offset) {
      test('invariant holds — $label', () {
        final license = licenseEndingIn(offset);

        expect(
          license.daysRemaining,
          greaterThanOrEqualTo(0),
          reason: '$label must never produce a negative day count',
        );

        // Hard expiry: isExpired is exactly "now is past expiryDate".
        final expectedExpired =
            DateTime.now().isAfter(license.expiryDate);
        expect(
          license.isExpired,
          expectedExpired,
          reason: '$label: isExpired must be the plain expiry comparison with '
              'no added grace period',
        );

        // An expired license always reports exactly zero and is never valid.
        if (license.isExpired) {
          expect(license.daysRemaining, 0,
              reason: '$label: an expired license reports 0 days');
          expect(license.isValid, isFalse,
              reason: '$label must not be treated as a valid paid license');
        }
      });
    });
  });
}