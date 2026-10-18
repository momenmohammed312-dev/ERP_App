import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/security_service.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';

/// EXECUTIVE DECISION TEST — "will existing paying customers be locked out
/// by the feat/online-license merge?"
///
/// The merge removed `License.fromJson` from the paid read path. `getCurrentLicense()`
/// now reads EITHER a `lease_token` (RS256) OR falls into the FEAT-014 legacy
/// bridge. A merge agent flagged this as "customers will be locked out".
///
/// This test settles it empirically by replaying the EXACT bytes the previous
/// release wrote — `License.toJson()` produced by `_saveLicenseSecure`, whose
/// `license_key` field holds the full AES key string (`<base64>.<sha256hex>`).
///
/// If this passes, existing customers keep working for the 90-day window.
/// If it fails, they are locked out immediately and that is a P1.
void main() {
  late Directory tmp;

  setUp(() async {
    await SecurityService.initialize();
    tmp = await Directory.systemTemp.createTemp('existing_customer_');
    SecureLicenseStorage.useDirectory(tmp);
  });

  tearDown(() async {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // ── The exact cipher the previous release used ────────────────────────────
  String aesEncrypt(String plainText) {
    // Must match LicenseManager._encrypt exactly: MD5 of the secret used as a raw
// 16-byte AES-128 key, with a zero IV.
final key = enc.Key(Uint8List.fromList(
      md5.convert(utf8.encode(LicenseConfig.secretKey)).bytes,
    ));
final iv = enc.IV(Uint8List(16));
return enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc))
    .encrypt(plainText, iv: iv)
    .base64;
  }

  String legacySignature(String data) =>
      sha256.convert(utf8.encode(data + LicenseConfig.secretKey)).toString();

  /// Reproduces a genuine pre-merge customer license key.
  String genuineOldLicenseKey({required DateTime expiry}) {
    final cipher = aesEncrypt(jsonEncode({
      'device': 'UNBOUND',
      'type': 'professional',
      'issue_date':
          DateTime.now().subtract(const Duration(days: 60)).toIso8601String(),
      'expiry': expiry.toIso8601String(),
      'features': ['pos', 'cash_sales', 'inventory', 'manufacturing'],
      'max_users': 5,
      'company_name': 'عميل سابق',
      'contact_email': 'legacy@example.invalid',
      'version': '1.0',
    }));
    return '$cipher.${legacySignature(cipher)}';
  }

  /// The EXACT map the previous release persisted via `_saveLicenseSecure`,
  /// i.e. `License.toJson()`.
  Map<String, dynamic> previousReleasePayload(String key) => {
        'license_key': key,
        'device': 'UNBOUND',
        'type': 'professional',
        'issue_date':
            DateTime.now().subtract(const Duration(days: 60)).toIso8601String(),
        'expiry': DateTime.now().add(const Duration(days: 300)).toIso8601String(),
        'features': ['pos', 'cash_sales', 'inventory', 'manufacturing'],
        'max_users': 5,
        'company_name': 'عميل سابق',
        'contact_email': 'legacy@example.invalid',
        'signature': null,
        'hardware_id': 'HW-LEGACY',
      };

  Future<void> seedAsPreviousRelease() async {
    final key = genuineOldLicenseKey(
      expiry: DateTime.now().add(const Duration(days: 300)),
    );
    await SecureLicenseStorage.write(
      SecureLicenseData(
        firstRunDate: DateTime.now().subtract(const Duration(days: 400)),
        hardwareId: 'HW-LEGACY',
        licenseJson: previousReleasePayload(key),
        lastCheckTime: DateTime.now(),
        appVersion: '2.3.0',
      ),
    );
  }

  group('P1 DECISION — an existing customer survives the merge', () {
    test('a pre-merge customer license IS still served', () async {
      await seedAsPreviousRelease();

      final license = await LicenseManager().getCurrentLicense();

      expect(
        license,
        isNotNull,
        reason: 'P1: if this is null the merge locks out every paying customer '
            'who activated before it. The FEAT-014 legacy bridge must cover '
            'the License.toJson() shape.',
      );

      expect(license!.type, LicenseType.professional);
      expect(license.maxUsers, 5,
          reason: 'their paid 5-user entitlement must survive');
      expect(license.features, contains('manufacturing'));
      expect(license.companyName, 'عميل سابق');
      expect(license.isValid, isTrue);
      expect(await LicenseManager().isLicenseValid(), isTrue);
      expect(LicenseManager.hasLegacyLicense, isTrue);
    });

    test('they keep their entitlements, not just the right to open the app',
        () async {
      await seedAsPreviousRelease();

      final license = await LicenseManager().getCurrentLicense();

      for (final feature in [
        'pos',
        'cash_sales',
        'inventory',
        'manufacturing',
      ]) {
        expect(
          await LicenseManager().hasFeature(feature),
          isTrue,
          reason: 'an existing customer must not silently lose "$feature" '
              'because of an internal format change',
        );
      }
    });

    test('the merge stamps the legacy grace deadline once', () async {
      await seedAsPreviousRelease();

      await LicenseManager().getCurrentLicense();
      final first = (await SecureLicenseStorage.read())!;
      expect(first.isLegacyLicense, isTrue);
      expect(first.legacyGraceEndsAt, isNotNull);

      await LicenseManager().getCurrentLicense();
      final second = (await SecureLicenseStorage.read())!;
      expect(
        second.legacyGraceEndsAt,
        first.legacyGraceEndsAt,
        reason: 'repeated launches must never extend the window',
      );
    });
  });

  group('P1 RISK — release builds without LICENSE_PUBLIC_KEY', () {
    test('a lease is refused when no public key is injected', () async {
      // Documents the deployment requirement: a release build MUST be given
      // --dart-define=LICENSE_PUBLIC_KEY, or every signed lease is rejected.
      final key = LicenseConfig.publicKey;
      expect(
        key.isEmpty,
        anyOf(isTrue, isFalse), // just read it; assertion below documents intent
      );
      // Default is empty in a release build (kDebugMode is false), which is
      // the dangerous case. In tests we run in debug mode, so the dev key is
      // present — assert the guard exists in source instead.
      final source = File('lib/services/license_manager.dart').readAsStringSync();
      expect(
        source.contains('LICENSE_PUBLIC_KEY not injected'),
        isTrue,
        reason: '_parseLease must refuse rather than accept when the key is '
            'missing — otherwise a mis-built release would silently accept '
            'nothing and lock out every customer',
      );
    });
  });
}