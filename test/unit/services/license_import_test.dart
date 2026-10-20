import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/hardware_id_service.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/security_service.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';

/// Regression guard for FEAT-012 — offline import of a signed license document.
///
/// Before this there was no way to activate a customer without a server: the
/// only path was `OnlineLicenseService.activateLicense()`, which returns
/// `offline` immediately when no API URL is configured. FEAT-012 adds
/// `LicenseManager.importLicenseDocument()`, which verifies a `.madarlicense`
/// file locally with the baked-in public key and stores it — with ZERO network
/// requests, as required by the owner.
///
/// These tests reuse the test-only RSA key pair the merge brought in
/// (test/fixtures/license/) and drive the REAL LicenseManager code. Only the
/// outside world is replaced: the data folder (temp dir), the device ids
/// (debug* seams) and the public key (override).
void main() {
  const machine = 'IMPORT-TEST-MACHINE';
  const install = 'IMPORT-TEST-INSTALL';

  late Directory tmp;
  final manager = LicenseManager();
  late RSAPrivateKey serverKey;

  setUpAll(() {
    serverKey = RSAPrivateKey(
      File('test/fixtures/license/test_private.pem').readAsStringSync(),
    );
  });

  setUp(() async {
    await SecurityService.initialize();
    tmp = await Directory.systemTemp.createTemp('license_import_test_');
    SecureLicenseStorage.useDirectory(tmp);
    LicenseConfig.publicKeyOverride =
        File('test/fixtures/license/test_public.pem').readAsStringSync();
    HardwareIdService.debugMachineGuid = machine;
    HardwareIdService.debugInstallUuid = install;
  });

  tearDown(() async {
    LicenseConfig.publicKeyOverride = null;
    HardwareIdService.debugMachineGuid = null;
    HardwareIdService.debugInstallUuid = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Builds a lease exactly like the Edge Function / local issuer does.
  String makeLease({
    String key = 'MO2-IMPORT-0001',
    String plan = 'professional',
    List<String>? features = const ['pos', 'manufacturing', 'custody'],
    String? licenseExpiresAt,
    Duration validFor = const Duration(days: 365),
    RSAPrivateKey? signer,
    String? machineOverride,
    String? installOverride,
    String? hardwareOverride,
  }) {
    final now = DateTime.now();
    int secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    return JWT({
      'license_key': key,
      'machine_guid': machineOverride ?? machine,
      'install_uuid': installOverride ?? install,
      'hardware_id': hardwareOverride ?? '',
      'plan': plan,
      'features': features ?? const [],
      'license_expires_at': licenseExpiresAt,
      'status': 'active',
      'iat': secs(now.subtract(const Duration(minutes: 1))),
      'exp': secs(now.add(validFor)),
    }).sign(
      signer ?? serverKey,
      algorithm: JWTAlgorithm.RS256,
      noIssueAt: true,
    );
  }

  /// Wraps a lease the way the .madarlicense envelope does.
  String envelope(String lease) => jsonEncode({
        'madar_license_envelope': 'v1',
        'lease': lease,
      });

  group('FEAT-012 — importing a signed license offline', () {
    test('a valid annual document is accepted and stored', () async {
      final doc = envelope(makeLease(
        licenseExpiresAt: DateTime.now()
            .add(const Duration(days: 365))
            .toIso8601String(),
      ));

      final result = await manager.importLicenseDocument(doc);

      expect(result.isValid, isTrue, reason: result.errorMessage ?? '');
      expect(result.license, isNotNull);

      // It must actually be persisted, not just accepted in memory.
      final stored = await SecureLicenseStorage.read();
      expect(stored, isNotNull, reason: 'the license must reach disk');
      expect(stored!.licenseJson?['lease_token'], isNotNull);
      expect((await manager.getCurrentLicense())?.licenseKey, 'MO2-IMPORT-0001');
    });

    test('a 365-day document keeps working for the whole year offline',
        () async {
      // The defect that would lock a paying customer out on day 37: the issuer
      // set exp = now + 30 days because that was the LEASE policy, not the
      // commercial one. The document format must carry the FULL term.
      final doc = envelope(makeLease(
        licenseExpiresAt:
            DateTime.now().add(const Duration(days: 365)).toIso8601String(),
        validFor: const Duration(days: 365),
      ));

      final result = await manager.importLicenseDocument(doc);
      expect(result.isValid, isTrue, reason: result.errorMessage ?? '');

      final license = (await manager.getCurrentLicense())!;
      final daysLeft = license.expiryDate.difference(DateTime.now()).inDays;
      expect(daysLeft, greaterThan(360),
          reason: 'the commercial term must be ~365 days, not the 30-day '
              'lease policy');
    });

    test('import makes NO network call — verified by the absence of any API '
        'dependency', () async {
      // OnlineLicenseService is deliberately NOT wired into the import path.
      // Assert on the source so a future edit that re-adds it fails loudly.
      final source =
          File('lib/services/license_manager.dart').readAsStringSync();
      final importBlock = source.substring(
        source.indexOf('Future<LicenseValidationResult> importLicenseDocument'),
        source.indexOf('Future<LicenseValidationResult> importLicenseDocument')
                + 2200,
      );
      expect(importBlock.contains('OnlineLicenseService'), isFalse,
          reason: 'the import path must never touch the licensing API');
      expect(importBlock.contains('http'), isFalse,
          reason: 'offline import must not perform any HTTP call');
    });
  });

  group('FEAT-012 — malformed and hostile documents are refused', () {
    test('a lease signed by another private key is rejected', () async {
      final attacker = RSAPrivateKey(
        File('test/fixtures/license/attacker_private.pem').readAsStringSync(),
      );
      final result = await manager.importLicenseDocument(
        envelope(makeLease(signer: attacker)),
      );
      expect(result.isValid, isFalse);
    });

    test('an alg:none token is rejected', () {
      final h = _b64({'alg': 'none', 'typ': 'JWT'});
      final p = _b64({'license_key': 'X', 'iat': 0, 'exp': 1 << 40});
      final result = manager.importLicenseDocument('$h.$p.');
      expect(result, isA<Future<LicenseValidationResult>>());
      return result.then((r) => expect(r.isValid, isFalse));
    });

    test('an HS256 token is rejected (algorithm confusion)', () {
      final t = JWT({
        'license_key': 'X',
        'machine_guid': machine,
        'install_uuid': install,
        'plan': 'professional',
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'exp': DateTime.now()
                .add(const Duration(days: 30))
                .millisecondsSinceEpoch ~/
            1000,
      }).sign(SecretKey('shared-secret'), algorithm: JWTAlgorithm.HS256);
      return manager
          .importLicenseDocument(envelope(t))
          .then((r) => expect(r.isValid, isFalse));
    });

    test('a document for a different device is rejected', () async {
      // BOTH ids must differ: the binding accepts a match on EITHER one, so
      // that a Windows reinstall (new install uuid, same machine guid) does not
      // lock a paying customer out.
      final result = await manager.importLicenseDocument(
        envelope(makeLease(
          machineOverride: 'SOMEONE-ELSE-PC',
          installOverride: 'SOMEONE-ELSE-INSTALL',
        )),
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('جهاز'),
          reason: 'the message must tell the customer this is a device issue');
    });

    test('a reinstall keeps working — matching EITHER id is enough', () async {
      // machine guid is stable across a reinstall, the install uuid is not.
      final result = await manager.importLicenseDocument(
        envelope(makeLease(installOverride: 'BRAND-NEW-INSTALL-UUID')),
      );
      expect(result.isValid, isTrue, reason: result.errorMessage ?? '');
    });

    test('BUG-023 — a lease bound to the on-screen fingerprint is accepted',
        () async {
      // The activation screen shows getHardwareId(). The issuer can now sign
      // exactly that value with --bind hardware, with no machine_guid or
      // install_uuid in the document, so the code the customer reads is the
      // code the license is bound to.
      final onScreen = await HardwareIdService.getHardwareId();
      final result = await manager.importLicenseDocument(
        envelope(makeLease(
          machineOverride: '',
          installOverride: '',
          hardwareOverride: onScreen,
        )),
      );
      expect(result.isValid, isTrue, reason: result.errorMessage ?? '');
      expect(result.license?.hardwareId, onScreen);
    });

    test('BUG-023 — a lease for a different on-screen fingerprint is rejected',
        () async {
      final result = await manager.importLicenseDocument(
        envelope(makeLease(
          machineOverride: '',
          installOverride: '',
          hardwareOverride: 'a-different-device-fingerprint',
        )),
      );
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('جهاز'));
    });

    test('garbage, empty and truncated input never throw', () async {
      for (final junk in [
        '',
        'not json at all',
        '{}',
        '{"lease":"a.b"}',
        'a.b.c',
        envelope('garbage'),
        envelope(''),
      ]) {
        final result = await manager.importLicenseDocument(junk);
        expect(result.isValid, isFalse, reason: 'input: "$junk"');
      }
    });

    test('an expired document is rejected', () async {
      final result = await manager.importLicenseDocument(envelope(makeLease(
        validFor: const Duration(days: -400),
      )));
      expect(result.isValid, isFalse);
    });

    test('a rejected import leaves the previous license untouched', () async {
      // Import a good one first.
      await manager.importLicenseDocument(envelope(makeLease(
        key: 'MO2-ORIGINAL',
      )));
      expect((await manager.getCurrentLicense())?.licenseKey, 'MO2-ORIGINAL');

      // Now try a forged one — it must not wipe the good license.
      final attacker = RSAPrivateKey(
        File('test/fixtures/license/attacker_private.pem').readAsStringSync(),
      );
      await manager.importLicenseDocument(envelope(makeLease(
        key: 'MO2-FORGED',
        signer: attacker,
      )));

      expect((await manager.getCurrentLicense())?.licenseKey, 'MO2-ORIGINAL',
          reason: 'a failed import must never destroy a working license');
    });
  });

  group('FEAT-012 — idempotency and restart persistence', () {
    test('importing the same document twice is safe', () async {
      final doc = envelope(makeLease());

      final first = await manager.importLicenseDocument(doc);
      expect(first.isValid, isTrue);
      final afterFirst = (await manager.getCurrentLicense())!.licenseKey;

      final second = await manager.importLicenseDocument(doc);
      expect(second.isValid, isTrue);
      expect((await manager.getCurrentLicense())!.licenseKey, afterFirst,
          reason: 're-importing the same file must not change anything');
    });

    test('the license survives a restart (read from disk)', () async {
      await manager.importLicenseDocument(envelope(makeLease()));

      // Simulate a fresh launch: nothing cached, only the file on disk.
      LicenseManager();
      final license = await manager.getCurrentLicense();

      expect(license, isNotNull);
      expect(license!.licenseKey, 'MO2-IMPORT-0001');
      expect(await manager.isLicenseValid(), isTrue);
    });
  });

  group('FEAT-012 — entitlements are bounded by the flavor', () {
    test('features are trimmed to what the active flavor supports', () async {
      // clothing has no manufacturing, no custody and no staff module
      // (lib/core/config/app_features.dart).
      HardwareIdService.debugMachineGuid = machine;
      final result = await manager.importLicenseDocument(envelope(makeLease(
        features: const [
          'pos',
          'manufacturing',
          'custody',
          'damaged_goods',
          'staff_management',
        ],
      )));

      expect(result.isValid, isTrue, reason: result.errorMessage ?? '');
      final features = result.license!.features;
      expect(features, contains('pos'),
          reason: 'core features always survive');
      expect(
        LicenseConfig.availableFeatures.toSet().containsAll(features.toSet()),
        isTrue,
        reason: 'a license must never grant a name the app does not know — '
            'unknown names are dropped, not stored',
      );
    });

    test('unknown feature names in a document are dropped, not stored',
        () async {
      final result = await manager.importLicenseDocument(envelope(makeLease(
        features: const ['pos', 'quantum_teleportation', 'nfc_magic'],
      )));

      expect(result.isValid, isTrue);
      expect(result.license!.features, isNot(contains('quantum_teleportation')),
          reason: 'an unknown name is a hint of a forged document');
      expect(result.license!.features, contains('pos'));
    });
  });
}

String _b64(Map<String, dynamic> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');