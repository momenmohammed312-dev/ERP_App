import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/security_service.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';

/// Regression guard for FEAT-013 — an application update must not destroy a
/// customer's license.
///
/// `getCurrentLicense()` used to do this inside its FREE_VERSION branch:
///
/// ```dart
/// if (data != null && data.appVersion != _currentAppVersion) {
///   await SecureLicenseStorage.clear();   // deletes secure_license.dat
/// }
/// ```
///
/// `clear()` removes the entire file, so it destroyed whatever license was
/// stored inside it. A FREE_VERSION build opening the same AppData folder could
/// therefore wipe a paid license, and `firstRunDate` was reset — handing out a
/// fresh 100-year window on every update.
///
/// The stamp is now written in place and is never a deletion trigger.
///
/// ── SCOPE NOTE (honest) ───────────────────────────────────────────────────
/// The `appVersion` branch lives ONLY under `if (LicenseConfig.isFreeVersion)`.
/// `isFreeVersion` is a compile-time `bool.fromEnvironment`, so a unit test
/// running without `--dart-define=FREE_VERSION=true` can never enter it.
/// Therefore:
///   * the PAID path is covered by real behavioural tests below;
///   * the FREE_VERSION path is covered by a source scan, because entering it
///     would require building with a different dart-define.
/// ───────────────────────────────────────────────────────────────────────────
void main() {
  late Directory tmp;

  setUp(() async {
    // Mirrors app_bootstrap.dart:36 — SecureLicenseStorage cannot encrypt
    // without it, and `flutter_secure_storage` has no platform in a unit
    // test, so this exercises the fallback-key path on purpose.
    await SecurityService.initialize();
    tmp = await Directory.systemTemp.createTemp('update_safety_test_');
    SecureLicenseStorage.useDirectory(tmp);
  });

  tearDown(() async {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A real paid license stored the way `_saveLicenseSecure` writes it.
  Future<void> seedPaidLicense({required String appVersion}) async {
    await SecureLicenseStorage.write(
      SecureLicenseData(
        firstRunDate: DateTime(2025, 1, 15),
        hardwareId: '',
        licenseJson: const {
          'license_key': 'POS-PAID-KEY',
          // License.fromJson assigns `device` to a NON-nullable String, so a
          // payload without it throws "type 'Null' is not a subtype of
          // type 'String'". Every real payload carries it.
          'device': 'HW-123',
          'type': 'professional',
          'issue_date': '2025-01-15T00:00:00.000',
          'expiry': '2027-01-15T00:00:00.000',
          'features': ['pos', 'manufacturing'],
          'max_users': 5,
          'company_name': 'عميل مدفوع',
          'contact_email': 'paid@example.invalid',
          'signature': null,
          'hardware_id': 'HW-123',
        },
        lastCheckTime: DateTime(2025, 1, 15),
        appVersion: appVersion,
      ),
    );
  }

  group('FEAT-013 — a paid license survives being read after an update', () {
    test('the license file is never deleted', () async {
      await seedPaidLicense(appVersion: '2.0.0');
      expect(
        File('${tmp.path}/secure_license.dat').existsSync(),
        isTrue,
        reason: 'sanity: the license file was written',
      );

      await LicenseManager().getCurrentLicense();

      expect(
        File('${tmp.path}/secure_license.dat').existsSync(),
        isTrue,
        reason: 'THE BUG: the license file was deleted during an update',
      );
    });

    test('the license key, company, features and maxUsers are unchanged',
        () async {
      await seedPaidLicense(appVersion: '2.0.0');

      await LicenseManager().getCurrentLicense();

      final after = await SecureLicenseStorage.read();
      expect(after, isNotNull, reason: 'the file must still be readable');
      expect(after!.licenseJson?['license_key'], 'POS-PAID-KEY');
      expect(after.licenseJson?['company_name'], 'عميل مدفوع');
      expect(after.licenseJson?['max_users'], 5);
      expect(after.licenseJson?['features'], contains('manufacturing'));
    });

    test('firstRunDate is NOT reset — the 100-year window cannot restart',
        () async {
      final original = DateTime(2025, 1, 15);
      await seedPaidLicense(appVersion: '2.0.0');

      await LicenseManager().getCurrentLicense();

      final after = await SecureLicenseStorage.read();
      expect(
        after!.firstRunDate,
        original,
        reason: 'clearing the file reset firstRunDate to "now", restarting the '
            '100-year window on every update',
      );
    });

    test('the stored license data is byte-identical after an update cycle',
        () async {
      await seedPaidLicense(appVersion: '2.0.0');

      // Two read cycles, as two consecutive app launches would do.
      await LicenseManager().getCurrentLicense();
      final first = (await SecureLicenseStorage.read())!.licenseJson;
      await LicenseManager().getCurrentLicense();
      final second = (await SecureLicenseStorage.read())!.licenseJson;

      expect(second, equals(first),
          reason: 'an update must not alter the stored license in any way');

      // End-to-end serving of the CURRENT (lease) format is covered by
      // test/services/license_lease_test.dart; the pre-RS256 AES format is
      // covered by legacy_license_bridge_test.dart. What FEAT-013 owns is
      // only that the update leaves the data intact.
    });

    test('re-reading is stable and idempotent', () async {
      await seedPaidLicense(appVersion: '2.0.0');

      await LicenseManager().getCurrentLicense();
      final first = await SecureLicenseStorage.read();
      await LicenseManager().getCurrentLicense();
      final second = await SecureLicenseStorage.read();

      expect(second!.firstRunDate, first!.firstRunDate);
      expect(second.licenseJson?['license_key'], 'POS-PAID-KEY');
    });
  });

  group('FEAT-013 — the deletion call is gone from the source', () {
    /// Strips comments so the explanatory notes cannot satisfy the guard.
    String executableLines(String source) => source
        .split('\n')
        .where((l) {
          final t = l.trim();
          return !t.startsWith('//') &&
              !t.startsWith('///') &&
              !t.startsWith('*') &&
              !t.startsWith('REM') &&
              !t.startsWith('#');
        })
        .join('\n');

    test('the version-stamp block never deletes license data', () {
      final source =
          File('lib/services/license_manager.dart').readAsStringSync();
      final anchor = source.indexOf('data.appVersion != _currentAppVersion');
      expect(anchor, greaterThan(-1),
          reason: 'the version-stamp block must exist');

      // Anchor on the block itself rather than on a "paid license" comment:
      // merging feat/online-license rewrote that comment, which silently
      // turned this guard into a no-op.
      final block = executableLines(
        source.substring(anchor, anchor + 400),
      );

      expect(
        block.contains('SecureLicenseStorage.clear()'),
        isFalse,
        reason: 'THE BUG: this block used to wipe the whole license file on '
            'every update. It must only re-stamp the version in place.',
      );
      expect(
        block.contains('copyWith(appVersion: _currentAppVersion)'),
        isTrue,
        reason: 'the stamp must be refreshed in place via copyWith',
      );
      expect(
        block.contains('resetting license'),
        isFalse,
        reason: 'the misleading log message must not come back',
      );
    });

    test('deactivate() keeps its clear() — that one is intentional', () {
      // Only the deliberate paths may wipe license state.
      final source =
          File('lib/services/license_manager.dart').readAsStringSync();
      final start = source.indexOf('Future<void> deactivate() async {');
      expect(start, greaterThan(-1), reason: 'deactivate() must exist');
      final deactivate = executableLines(source.substring(start));

      expect(
        deactivate.contains('SecureLicenseStorage.clear()'),
        isTrue,
        reason: 'deactivate() is an explicit customer/support action — wiping '
            'the license there is correct and must not be "fixed"',
      );
    });

    test('the secure-storage fallback key is a valid AES-256 length', () {
      // Found while writing these tests: a 33-byte fallback key made every
      // SecureLicenseStorage.write() fail silently.
      final source =
          File('lib/services/security_service.dart').readAsStringSync();
      final match = RegExp(r"_fallbackKey\s*=\s*'([^']*)'").firstMatch(source);
      expect(match, isNotNull,
          reason: 'a named fallback key constant must exist so its length can '
              'be asserted');

      final key = match!.group(1)!;
      expect(
        key.length,
        32,
        reason: 'AES-256 needs exactly 32 bytes. A wrong length makes '
            'DatabaseEncryptionService throw and every license write fail '
            'silently. Current value has ${key.length} bytes.',
      );
    });
  });
}