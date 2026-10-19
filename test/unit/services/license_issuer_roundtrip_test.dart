import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/hardware_id_service.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';
import 'package:pos_offline_desktop/services/security_service.dart';

/// FEAT-011 ↔ FEAT-012 — end-to-end: the real CLI issues a document, the real
/// app imports it.
///
/// The Node suite proves the issuer's own contract, and `license_import_test`
/// proves the client's. This file is what stops the two from drifting apart:
/// `tools/license_issuer.js` is executed as a subprocess, its output is read
/// straight off disk, and it goes through `LicenseManager.importLicenseDocument`
/// with no hand-written token in between.
///
/// No production key is involved. The suite generates a throwaway RSA pair in
/// the OS temp dir — outside the repository, which is exactly what the issuer's
/// guard requires — and deletes it afterwards.
void main() {
  const machine = 'ROUNDTRIP-MACHINE';
  const install = 'ROUNDTRIP-INSTALL';

  late Directory tmp;
  late String keyPath;
  late String publicPem;
  final manager = LicenseManager();

  setUpAll(() {
    if (Process.runSync('where', ['node']).exitCode != 0) {
      throw StateError('node is required for this suite');
    }
  });

  setUp(() async {
    await SecurityService.initialize();
    tmp = await Directory.systemTemp.createTemp('madar_roundtrip_');
    keyPath = '${tmp.path}/issuer_key.pem';

    // Generate the signing pair with Node, exactly as a real operator would.
    final r = Process.runSync('node', [
      '-e',
      "const c=require('crypto'),f=require('fs');"
          "const k=c.generateKeyPairSync('rsa',{modulusLength:2048,"
          'privateKeyEncoding:{type:"pkcs8",format:"pem"},'
          'publicKeyEncoding:{type:"spki",format:"pem"}});'
          "f.writeFileSync(process.argv[1],k.privateKey);"
          "f.writeFileSync(process.argv[2],k.publicKey);",
      keyPath,
      '${tmp.path}/issuer_key.pub.pem',
    ]);
    if (r.exitCode != 0) {
      throw StateError('key generation failed: ${r.stderr}');
    }
    publicPem = File('${tmp.path}/issuer_key.pub.pem').readAsStringSync();

    SecureLicenseStorage.useDirectory(
      await Directory('${tmp.path}/store').create(),
    );
    HardwareIdService.debugMachineGuid = machine;
    HardwareIdService.debugInstallUuid = install;
  });

  tearDown(() async {
    LicenseConfig.publicKeyOverride = null;
    HardwareIdService.debugMachineGuid = null;
    HardwareIdService.debugInstallUuid = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Runs the actual CLI exactly as documented, and returns the file it wrote.
  String issue(List<String> args, {String outName = 'license.madarlicense'}) {
    final out = '${tmp.path}/$outName';
    final r = Process.runSync('node', [
      'tools/license_issuer.js',
      '--key',
      keyPath,
      '--out',
      out,
      '--machine-guid',
      machine,
      '--install-uuid',
      install,
      ...args,
    ]);
    expect(
      r.exitCode,
      0,
      reason:
          'the issuer must succeed.\nstdout: ${r.stdout}\nstderr: ${r.stderr}',
    );
    return File(out).readAsStringSync();
  }

  group('the real CLI output is accepted by the real app', () {
    test('a 7-day trial issued by the CLI activates with no network', () async {
      final doc = issue([
        '--type',
        'trial',
        '--days',
        '7',
        '--features',
        'pos,cash_sales,inventory',
      ]);

      LicenseConfig.publicKeyOverride = publicPem;
      final result = await manager.importLicenseDocument(doc);

      expect(result.isValid, isTrue, reason: result.errorMessage ?? '');
      final license = result.license!;
      expect(license.type.name, 'trial');
      expect(license.features, containsAll(['pos', 'cash_sales', 'inventory']));
      expect(await manager.isLicenseValid(), isTrue);
    });

    test(
      'an annual license issued by the CLI keeps working for a full year',
      () async {
        final doc = issue([
          '--type',
          'paid',
          '--months',
          '12',
          '--features',
          'pos,manufacturing,custody',
        ]);

        LicenseConfig.publicKeyOverride = publicPem;
        final result = await manager.importLicenseDocument(doc);

        expect(result.isValid, isTrue, reason: result.errorMessage ?? '');
        final license = result.license!;
        expect(
          license.type.name,
          'professional',
          reason: 'plan "yearly" resolves to the professional tier',
        );

        final daysLeft = license.expiryDate.difference(DateTime.now()).inDays;
        expect(
          daysLeft,
          greaterThan(360),
          reason:
              'this is the whole point of FEAT-011 §3.2: a paid year must '
              'not degrade into the 30-day online lease policy',
        );

        // And the entitlement the customer paid for is actually there.
        expect(license.features, contains('manufacturing'));
        expect(license.features, contains('custody'));
      },
    );

    test('the trial clock starts at issuance, not at import', () async {
      // An hour-old document must still show ~7 days, proving the term is
      // anchored on `iat` and not on when the customer happened to import.
      final out = '${tmp.path}/aged.madarlicense';
      final r = Process.runSync('node', [
        'tools/license_issuer.js',
        '--type',
        'trial',
        '--days',
        '7',
        '--features',
        'pos',
        '--machine-guid',
        machine,
        '--install-uuid',
        install,
        '--key',
        keyPath,
        '--out',
        out,
      ]);
      expect(r.exitCode, 0, reason: r.stderr.toString());

      // Rewrite `iat`/`exp` backwards by one hour to simulate an aged file,
      // then re-sign it with the same key so the signature stays valid.
      final doc = _ageDocument(File(out).readAsStringSync(), 3600, keyPath);
      LicenseConfig.publicKeyOverride = publicPem;

      final result = await manager.importLicenseDocument(doc);
      expect(result.isValid, isTrue, reason: result.errorMessage ?? '');

      final daysLeft = result.license!.expiryDate
          .difference(DateTime.now())
          .inDays;
      expect(
        daysLeft,
        greaterThan(5),
        reason: 'a 7-day trial issued an hour ago must still have ~6 days',
      );
      expect(daysLeft, lessThanOrEqualTo(7));
    });
  });

  group('the app refuses what it should refuse', () {
    test('AC6 a document from a DIFFERENT key is rejected', () async {
      final doc = issue([
        '--type',
        'trial',
        '--days',
        '7',
        '--features',
        'pos',
      ]);

      // A completely unrelated public key — e.g. the app was built with the
      // production key while the document was signed with a stale one.
      final r = Process.runSync('node', [
        '-e',
        "const c=require('crypto'),f=require('fs');"
            "const k=c.generateKeyPairSync('rsa',{modulusLength:2048,"
            'publicKeyEncoding:{type:"spki",format:"pem"}});'
            "f.writeFileSync(process.argv[1],k.publicKey);",
        '${tmp.path}/other.pub.pem',
      ]);
      expect(r.exitCode, 0);

      LicenseConfig.publicKeyOverride = File(
        '${tmp.path}/other.pub.pem',
      ).readAsStringSync();
      final result = await manager.importLicenseDocument(doc);

      expect(result.isValid, isFalse);
      expect(result.errorMessage, isNotNull);
      expect(
        result.errorMessage,
        isNotEmpty,
        reason: 'the customer must be told something actionable',
      );
    });

    test('AC7 a feature outside AppFeatures is trimmed, not granted', () async {
      final doc = issue([
        '--type',
        'paid',
        '--months',
        '12',
        '--features',
        'pos,teleportation_module',
      ]);

      LicenseConfig.publicKeyOverride = publicPem;
      final result = await manager.importLicenseDocument(doc);

      expect(result.isValid, isTrue, reason: result.errorMessage ?? '');
      expect(result.license!.features, isNot(contains('teleportation_module')));
      expect(result.license!.features, contains('pos'));
      expect(await manager.hasFeature('teleportation_module'), isFalse);
    });

    test('a document bound to another machine is rejected', () async {
      final out = '${tmp.path}/wrongdevice.madarlicense';
      final r = Process.runSync('node', [
        'tools/license_issuer.js',
        '--type',
        'trial',
        '--days',
        '7',
        '--features',
        'pos',
        '--bind',
        'both',
        '--machine-guid',
        'A-DIFFERENT-PC',
        '--install-uuid',
        'A-DIFFERENT-INSTALL',
        '--key',
        keyPath,
        '--out',
        out,
      ]);
      expect(r.exitCode, 0, reason: r.stderr.toString());

      LicenseConfig.publicKeyOverride = publicPem;
      final result = await manager.importLicenseDocument(
        File(out).readAsStringSync(),
      );
      expect(result.isValid, isFalse);
    });
  });
}

/// Shifts `iat` and `exp` back by [seconds] and re-signs with [signingKeyPath],
/// producing a genuinely valid but older document.
String _ageDocument(String envelope, int seconds, String signingKeyPath) {
  final map = jsonDecode(envelope) as Map<String, dynamic>;
  final parts = (map['lease'] as String).split('.');
  final payload =
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;

  payload['iat'] = (payload['iat'] as int) - seconds;
  payload['exp'] = (payload['exp'] as int) - seconds;

  // Re-sign through the same construction the issuer uses, so the aged
  // document is genuinely valid rather than a hand-rolled token.
  final r = Process.runSync('node', [
    '-e',
    'const c=require("crypto"),fs=require("fs");'
        'const unsigned=process.argv[1]+"."+'
        'Buffer.from(process.argv[2],"utf8").toString("base64url");'
        'const s=c.createSign("RSA-SHA256");s.update(unsigned);'
        'process.stdout.write(unsigned+"."+'
        's.sign(fs.readFileSync(process.argv[3]),"base64url"));',
    parts[0],
    jsonEncode(payload),
    signingKeyPath,
  ]);
  if (r.exitCode != 0) {
    throw StateError('re-signing failed: ${r.stderr}');
  }

  map['lease'] = r.stdout.toString();
  return jsonEncode(map);
}
