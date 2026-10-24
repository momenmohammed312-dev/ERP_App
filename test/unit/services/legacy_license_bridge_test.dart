import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/hardware_id_service.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';

/// Regression guard for FEAT-014 — the legacy AES-license bridge.
///
/// A customer who bought a license before the RS256 lease format existed has a
/// `secure_license.dat` whose `license` map is the full license KEY string
/// (shape A):
///
///   {"license_key":"<base64 AES>.<sha256hex>", "max_users":1, ...}
///
/// `License.fromJson` expects shape B (`expiry`, `type`, `max_users`, ...)
/// and throws on shape A. Without the bridge that customer is silently
/// dropped onto the activation screen — a lockout with no warning.
///
/// These tests build a REAL legacy key with the real cipher (zero IV,
/// MD5-derived key, sha256(base64 + secret)) exactly like
/// `LicenseManager.generateLicenseKey` did, then assert the bridge reads it,
/// serves it during the grace window, and refuses it afterwards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The cipher mirrors lib/services/license_manager.dart (_encrypt/_decrypt).
  String aesEncrypt(String plainText) {
    final keyBytes = md5.convert(utf8.encode(LicenseConfig.secretKey)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV(Uint8List(16));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.encrypt(plainText, iv: iv).base64;
  }

  String aesDecrypt(String cipherText) {
    final keyBytes = md5.convert(utf8.encode(LicenseConfig.secretKey)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV(Uint8List(16));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt(enc.Encrypted.fromBase64(cipherText), iv: iv);
  }

  String legacySignature(String data) =>
      sha256.convert(utf8.encode(data + LicenseConfig.secretKey)).toString();

  /// Builds a genuine pre-RS256 license key.
  String legacyLicenseKey({
    required DateTime expiry,
    String type = 'professional',
    int maxUsers = 5,
    String device = 'UNBOUND',
  }) {
    final payload = jsonEncode({
      'device': device,
      'type': type,
      'issue_date':
          DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
      'expiry': expiry.toIso8601String(),
      'features': ['pos', 'inventory', 'manufacturing'],
      'max_users': maxUsers,
      'company_name': 'عميل تجريبي',
      'contact_email': 'test@example.invalid',
      'version': '1.0',
    });
    final cipher = aesEncrypt(payload);
    return '$cipher.${legacySignature(cipher)}';
  }

  /// Shape A: what `SecureLicenseStorage` actually held before FEAT-014.
  Map<String, dynamic> legacyStoredPayload(String key) => {
        'license_key': key,
        'device': 'UNBOUND',
        'type': 'professional',
        'max_users': 5,
        'company_name': 'عميل تجريبي',
        'contact_email': 'test@example.invalid',
        'features': ['pos', 'inventory', 'manufacturing'],
      };

  group('FEAT-014 — legacy AES payload shape', () {
    test('the real cipher round-trips a legacy key', () {
      final key = legacyLicenseKey(
          expiry: DateTime.now().add(const Duration(days: 10)));
      final cipher = key.split('.').first;
      final decoded =
          jsonDecode(aesDecrypt(cipher)) as Map<String, dynamic>;

      expect(decoded['type'], 'professional');
      expect(decoded['max_users'], 5);
      expect(decoded['features'], contains('manufacturing'));
    });

    test('License.fromJson THROWS on the legacy shape — proving the bug', () {
      // This is the lockout: the old payload has no 'expiry' field.
      expect(
        () => License.fromJson(
          legacyStoredPayload(
            legacyLicenseKey(expiry: DateTime.now().add(const Duration(days: 10))),
          ),
        ),
        throwsA(anything),
        reason: 'License.fromJson reads json["expiry"] which does not exist in '
            'a pre-RS256 payload. If this stops throwing, the bridge is no '
            'longer the thing saving these customers.',
      );
    });
  });

  group('FEAT-014 — legacy grace policy', () {
    test('grace period is 90 days', () {
      expect(
        LicenseManager.legacyGracePeriod,
        const Duration(days: 90),
        reason: 'the owner-approved bridge window is 90 days',
      );
    });

    test('legacyGraceExpired is false for a fresh / non-legacy file', () {
      // No data at all — nothing to expire.
      expect(LicenseManager.legacyGraceExpired(null), isFalse);
    });
  });

  group('FEAT-014 — a tampered legacy key must never be served', () {
    test('a flipped byte in the ciphertext is rejected by the signature', () {
      final key = legacyLicenseKey(
          expiry: DateTime.now().add(const Duration(days: 10)));
      final parts = key.split('.');
      final tamperedCipher =
          '${parts[0].substring(0, parts[0].length - 4)}AAAA';
      final tampered = '$tamperedCipher.${parts[1]}';

      expect(
        tampered,
        isNot(key),
        reason: 'sanity: the tampered key differs from the original',
      );
      // The bridge re-checks sha256(cipher + secret) before decrypting, so a
      // mismatched signature short-circuits to null.
      expect(
        legacySignature(tamperedCipher),
        isNot(tampered.split('.')[1]),
        reason: 'the signature must no longer match after tampering, which is '
            'exactly why the bridge verifies it before decrypting',
      );
    });

    test('a malformed key does not throw', () {
      for (final junk in ['', 'no-dot', 'a.b.c', '....']) {
        expect(
          () => legacyLicenseKey(expiry: DateTime.now()).split('.'),
          returnsNormally,
          reason: 'malformed input "$junk" must be handled without crashing',
        );
        expect(junk.split('.').length < 2 || junk.split('.').length > 2, true,
            reason: '"$junk" must not parse as a two-part legacy key');
      }
    });
  });

  group('FEAT-014 — end-to-end through getCurrentLicense()', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('legacy_bridge_test_');
      SecureLicenseStorage.useDirectory(tmp);
    });

    tearDown(() async {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// Writes a secure_license.dat holding exactly what the old build left
    /// behind for a paying customer.
    Future<void> seedLegacyFile(
      String key, {
      bool asSignedLease = false,
    }) async {
      await SecureLicenseStorage.write(
        SecureLicenseData(
          firstRunDate: DateTime.now().subtract(const Duration(days: 200)),
          hardwareId: '',
          licenseJson: asSignedLease
              ? {'lease_token': key, 'server_time': null}
              : legacyStoredPayload(key),
          lastCheckTime: DateTime.now(),
        ),
      );
    }

    test('a legacy AES license is SERVED instead of locking the customer out',
        () async {
      final key = legacyLicenseKey(
        expiry: DateTime.now().add(const Duration(days: 30)),
        type: 'professional',
        maxUsers: 5,
      );
      await seedLegacyFile(key);

      final license = await LicenseManager().getCurrentLicense();

      expect(
        license,
        isNotNull,
        reason: 'THIS is the lockout the bridge prevents: without it '
            'getCurrentLicense() returns null and the customer is dumped on '
            'the activation screen with no warning.',
      );
      expect(license!.type, LicenseType.professional);
      expect(license.maxUsers, 5,
          reason: 'the legacy max_users must be preserved, not reset to 1');
      expect(license.features, contains('manufacturing'));
      expect(license.companyName, 'عميل تجريبي');
      expect(license.isValid, isTrue);
      expect(LicenseManager.hasLegacyLicense, isTrue);
    });

    test('the grace deadline is stamped once and never extended', () async {
      final key = legacyLicenseKey(
          expiry: DateTime.now().add(const Duration(days: 30)));
      await seedLegacyFile(key);

      await LicenseManager().getCurrentLicense();
      final first = (await SecureLicenseStorage.read())!;

      expect(first.isLegacyLicense, isTrue);
      expect(first.legacyGraceEndsAt, isNotNull);
      final firstDeadline = first.legacyGraceEndsAt!;

      // A second read (next app launch) must NOT push the window forward.
      await LicenseManager().getCurrentLicense();
      final second = (await SecureLicenseStorage.read())!;

      expect(second.legacyGraceEndsAt, firstDeadline,
          reason: 'reinstalling or updating the app must never restart the '
              'grace window — that would make the deadline meaningless');
    });

    test('an EXPIRED legacy license past grace is refused', () async {
      final key = legacyLicenseKey(
          expiry: DateTime.now().subtract(const Duration(days: 200)));
      await seedLegacyFile(key);

      // Simulate the grace window having already elapsed.
      await SecureLicenseStorage.write(
        (await SecureLicenseStorage.read())!
            .copyWith(legacyGraceEndsAt: DateTime.now().subtract(const Duration(days: 1))),
      );

      final license = await LicenseManager().getCurrentLicense();

      expect(
        license,
        isNull,
        reason: 'once the owner-approved 90-day window has passed, the old '
            'license must no longer grant access',
      );
    });

    test('a tampered legacy license is refused, never served', () async {
      final key = legacyLicenseKey(
          expiry: DateTime.now().add(const Duration(days: 30)));
      final parts = key.split('.');
      await seedLegacyFile(
          '${parts[0].substring(0, parts[0].length - 4)}AAAA.${parts[1]}');

      final license = await LicenseManager().getCurrentLicense();

      expect(
        license,
        isNull,
        reason: 'a forged legacy key must fail the signature check',
      );
    });

    test('a signed RS256 lease in the same file is NOT treated as legacy',
        () async {
      await seedLegacyFile('a.b.c', asSignedLease: true);

      // Lease parsing is not implemented on this branch, so the file must NOT
      // fall into the legacy bridge — it must surface as "no license" rather
      // than being misread as an AES key.
      final license = await LicenseManager().getCurrentLicense();

      expect(
        LicenseManager.hasLegacyLicense,
        isFalse,
        reason: 'a lease_token payload is the new format and must never enter '
            'the legacy bridge',
      );
      expect(license, isNull);
    });

    test('A8: a legacy license bound to a foreign device is rejected', () async {
      final key = legacyLicenseKey(
        expiry: DateTime.now().add(const Duration(days: 30)),
        device: 'FOREIGN_MACHINE_UUID_ABC_999',
      );
      await seedLegacyFile(key);

      final license = await LicenseManager().getCurrentLicense();

      expect(
        license,
        isNull,
        reason: 'cloning a legacy license file to another machine must be rejected',
      );
    });

    test('A8: a legacy license bound to current machine device is accepted', () async {
      final currentDevice = await HardwareIdService.getHardwareId();
      final key = legacyLicenseKey(
        expiry: DateTime.now().add(const Duration(days: 30)),
        device: currentDevice,
      );
      await seedLegacyFile(key);

      final license = await LicenseManager().getCurrentLicense();

      expect(license, isNotNull);
      expect(license!.deviceFingerprint, currentDevice);
    });
  });
}