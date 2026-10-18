import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Cipher mirroring LicenseManager
  String aesEncrypt(String plainText) {
    final keyBytes = md5.convert(utf8.encode(LicenseConfig.secretKey)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV(Uint8List(16));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.encrypt(plainText, iv: iv).base64;
  }

  String legacySignature(String data) =>
      sha256.convert(utf8.encode(data + LicenseConfig.secretKey)).toString();

  String legacyLicenseKey({
    required DateTime expiry,
    String type = 'professional',
    int maxUsers = 5,
    List<String> features = const ['pos', 'inventory', 'manufacturing'],
  }) {
    final payload = jsonEncode({
      'device': 'UNBOUND',
      'type': type,
      'issue_date':
          DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
      'expiry': expiry.toIso8601String(),
      'features': features,
      'max_users': maxUsers,
      'company_name': 'عميل تجريبي',
      'contact_email': 'test@example.invalid',
      'version': '1.0',
    });
    final cipher = aesEncrypt(payload);
    return '$cipher.${legacySignature(cipher)}';
  }

  Map<String, dynamic> legacyStoredPayload(String key) => {
        'license_key': key,
        'device': 'UNBOUND',
        'type': 'professional',
        'max_users': 5,
        'company_name': 'عميل تجريبي',
        'contact_email': 'test@example.invalid',
        'features': ['pos', 'inventory', 'manufacturing'],
      };

  group('Suite 1: Licensing, Bridge, Module Gates & Expiry', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('suite_01_license_test_');
      SecureLicenseStorage.useDirectory(tmpDir);
    });

    tearDown(() async {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('1. Legacy AES License Bridge serves valid pre-RS256 licenses', () async {
      final key = legacyLicenseKey(
        expiry: DateTime.now().add(const Duration(days: 30)),
        type: 'professional',
        maxUsers: 5,
      );

      await SecureLicenseStorage.write(
        SecureLicenseData(
          firstRunDate: DateTime.now().subtract(const Duration(days: 200)),
          hardwareId: '',
          licenseJson: legacyStoredPayload(key),
          lastCheckTime: DateTime.now(),
        ),
      );

      final license = await LicenseManager().getCurrentLicense();

      expect(license, isNotNull);
      expect(license!.type, LicenseType.professional);
      expect(license.maxUsers, 5);
      expect(license.features, contains('manufacturing'));
      expect(license.companyName, 'عميل تجريبي');
      expect(license.isExpired, isFalse);
      expect(LicenseManager.hasLegacyLicense, isTrue);
    });

    test('2. Tampered legacy ciphertext is strictly rejected', () async {
      final key = legacyLicenseKey(
        expiry: DateTime.now().add(const Duration(days: 10)),
      );
      final parts = key.split('.');
      final tamperedCipher =
          '${parts[0].substring(0, parts[0].length - 4)}AAAA';
      final tamperedKey = '$tamperedCipher.${parts[1]}';

      await SecureLicenseStorage.write(
        SecureLicenseData(
          firstRunDate: DateTime.now().subtract(const Duration(days: 200)),
          hardwareId: '',
          licenseJson: legacyStoredPayload(tamperedKey),
          lastCheckTime: DateTime.now(),
        ),
      );

      final license = await LicenseManager().getCurrentLicense();
      expect(license, isNull);
    });

    test('3. License plan mapping resolves dashboard plans without fallback downgrade', () {
      final testCases = {
        'trial': LicenseType.trial,
        'monthly': LicenseType.standard,
        'yearly': LicenseType.professional,
        'lifetime': LicenseType.professional,
        'professional': LicenseType.professional,
        'enterprise': LicenseType.enterprise,
      };

      testCases.forEach((planName, expectedType) {
        final lic = License.fromJson({
          'license_key': 'KEY-123',
          'device': 'UNBOUND',
          'type': planName,
          'issue_date': DateTime.now().toIso8601String(),
          'expiry': DateTime.now().add(const Duration(days: 365)).toIso8601String(),
          'features': ['all'],
          'max_users': 5,
          'company_name': 'شركة اختبار',
          'contact_email': 'test@example.com',
        });
        expect(lic.type, expectedType);
      });
    });

    test('4. Installer scripts static scan: No installer deletes customer license', () {
      const installerFiles = [
        'installer/update_factory_setup.iss',
        'installer/Simple_Setup.bat',
        'installer/factory_setup.iss',
        'installer/Install_Update.bat',
      ];

      for (final relPath in installerFiles) {
        final file = File(relPath);
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          final lines = content.split('\n');
          for (final line in lines) {
            final l = line.trim();
            if (l.startsWith('//') || l.startsWith('REM') || l.startsWith('#')) continue;
            final touchesLicense = l.contains('secure_license') || l.contains('app_license');
            if (touchesLicense) {
              final isDelete = l.contains('del ') ||
                  l.contains('Remove-Item') ||
                  l.contains('DeleteFile') ||
                  l.contains('rm ');
              expect(isDelete, isFalse, reason: 'Installer $relPath must not delete license in: $l');
            }
          }
        }
      }
    });

    test('5. Module gating & feature permission logic', () async {
      final keyMfg = legacyLicenseKey(
        expiry: DateTime.now().add(const Duration(days: 30)),
        type: 'professional',
        maxUsers: 5,
        features: ['pos', 'inventory', 'manufacturing'],
      );

      await SecureLicenseStorage.write(
        SecureLicenseData(
          firstRunDate: DateTime.now().subtract(const Duration(days: 20)),
          hardwareId: '',
          licenseJson: {
            'license_key': keyMfg,
            'device': 'UNBOUND',
            'type': 'professional',
            'max_users': 5,
            'features': ['pos', 'inventory', 'manufacturing'],
          },
          lastCheckTime: DateTime.now(),
        ),
      );

      final manager = LicenseManager();
      expect(await manager.hasFeature('manufacturing'), isTrue);
      expect(await manager.hasFeature('pos'), isTrue);
      expect(await manager.hasFeature('unknown_module'), isFalse);

      final keyAll = legacyLicenseKey(
        expiry: DateTime.now().add(const Duration(days: 30)),
        type: 'enterprise',
        maxUsers: 10,
        features: ['all'],
      );

      await SecureLicenseStorage.write(
        SecureLicenseData(
          firstRunDate: DateTime.now().subtract(const Duration(days: 20)),
          hardwareId: '',
          licenseJson: {
            'license_key': keyAll,
            'device': 'UNBOUND',
            'type': 'enterprise',
            'max_users': 10,
            'features': ['all'],
          },
          lastCheckTime: DateTime.now(),
        ),
      );

      expect(await manager.hasFeature('manufacturing'), isTrue);
      expect(await manager.hasFeature('reports'), isTrue);
      expect(await manager.hasFeature('any_custom_feature'), isTrue);
    });

    test('6. Expired license state is detected accurately', () {
      final expiredLic = License(
        licenseKey: 'KEY-EXP',
        deviceFingerprint: 'DEV1',
        type: LicenseType.standard,
        issueDate: DateTime.now().subtract(const Duration(days: 60)),
        expiryDate: DateTime.now().subtract(const Duration(days: 1)),
        features: ['pos'],
        maxUsers: 3,
        companyName: 'منتهي الصلاحية',
        contactEmail: 'expired@test.com',
      );
      expect(expiredLic.isExpired, isTrue);
      expect(expiredLic.daysRemaining, equals(0));
    });
  });
}
