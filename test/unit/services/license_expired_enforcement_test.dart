import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/custody_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/damaged_items_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/services/hardware_id_service.dart';
import 'package:pos_offline_desktop/services/license_entitlement.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';
import 'package:pos_offline_desktop/services/security_service.dart';

/// BUG-021 / FEAT-015 — importing an EXPIRED document.
///
/// `importLicenseDocument` documents two promises that were both false:
///
///   1. "expired documents all come back as an invalid result" — an aged
///      document came back `valid: true`, so the activation screen showed
///      "تم تفعيل الرخصة بنجاح" and navigated to the success page for a licence
///      that was already dead.
///   2. "a rejected import never destroys the license already on disk" — the
///      expired document was written over a working licence, because saveLease
///      persists before anything looks at the expiry.
///
/// Guards are asserted here too, to prove the two layers agree: the refusal
/// must be visible to the operator AND the modules must stay shut.
void main() {
  const machine = 'EXPIRED-MACHINE';
  const install = 'EXPIRED-INSTALL';

  late Directory tmp;
  late String keyPath;
  late String publicPem;
  late AppDatabase db;
  late DamagedItemsDao damagedDao;
  late CustodyDao custodyDao;
  late ManufacturingOrderDao moDao;
  late int productId;

  final manager = LicenseManager();

  setUpAll(() {
    if (Process.runSync('where', ['node']).exitCode != 0) {
      throw StateError('node is required for this suite');
    }
  });

  setUp(() async {
    await SecurityService.initialize();
    tmp = await Directory.systemTemp.createTemp('madar_expired_');

    keyPath = '${tmp.path}/issuer_key.pem';
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
    LicenseConfig.publicKeyOverride = publicPem;

    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    damagedDao = DamagedItemsDao(db);
    custodyDao = CustodyDao(db);
    moDao = ManufacturingOrderDao(db);
    productId = await db.productDao.insertProduct(
      ProductsCompanion.insert(name: 'صنف', quantity: 100, price: 50),
    );

    LicenseEntitlement.instance.reset();
  });

  tearDown(() async {
    LicenseConfig.publicKeyOverride = null;
    HardwareIdService.debugMachineGuid = null;
    HardwareIdService.debugInstallUuid = null;
    LicenseEntitlement.instance.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Issues a real license through the operator CLI.
  String issue({required int days}) {
    final out = '${tmp.path}/lic-$days.madarlicense';
    final r = Process.runSync('node', [
      'tools/license_issuer.js',
      '--type',
      'trial',
      '--days',
      '$days',
      '--features',
      'manufacturing,custody,damaged_goods',
      '--bind',
      'both',
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
    return File(out).readAsStringSync();
  }

  /// Rewrites `iat`/`exp`/`license_expires_at` backwards by [seconds] and
  /// re-signs with the same key, so the signature stays valid and only the
  /// clock moves. This is an operator holding a licence they never installed.
  String age(String envelope, int seconds) =>
      ageDocument(envelope, seconds, keyPath);

  group('AC1 — an expired document is refused, not reported as activated', () {
    test('the import does not report a usable license', () async {
      final result = await manager.importLicenseDocument(
        age(issue(days: 1), 3 * 24 * 3600),
      );

      expect(
        result.isValid,
        isFalse,
        reason: 'an expired document must never import as valid, or the '
            'operator is shown "تم تفعيل الرخصة بنجاح" and sent to the '
            'success screen for a licence that expired before it was opened',
      );
    });

    test('the refusal explains that it expired', () async {
      final result = await manager.importLicenseDocument(
        age(issue(days: 1), 3 * 24 * 3600),
      );

      expect(result.errorMessage, isNotNull);
      expect(result.license, isNull);
    });
  });

  group('AC2 — an expired import never destroys a working license', () {
    test('a valid license survives an expired import', () async {
      final valid = await manager.importLicenseDocument(issue(days: 30));
      expect(valid.isValid, isTrue, reason: valid.errorMessage ?? '');
      // The activation screen invalidates its providers after a successful
      // import, which re-reads the license; that read is what refreshes the
      // in-memory snapshot the guards use.
      await manager.getCurrentLicense();
      expect(LicenseEntitlement.instance.grants('manufacturing'), isTrue);

      final expired = await manager.importLicenseDocument(
        age(issue(days: 1), 3 * 24 * 3600),
      );
      expect(expired.isValid, isFalse);

      final stillThere = await manager.getCurrentLicense();
      expect(
        stillThere?.isValid,
        isTrue,
        reason: 'the working licence must still be on disk after a refused '
            'import — the operator has to be able to recover',
      );
      expect(
        LicenseEntitlement.instance.grants('manufacturing'),
        isTrue,
        reason: 'a refused import must not lock a licensed install',
      );
    });
  });

  group('AC3 — no gated module opens for an expired license', () {
    test('the paid modules are not granted', () async {
      await manager.importLicenseDocument(age(issue(days: 1), 3 * 24 * 3600));
      await manager.getCurrentLicense();

      for (final f in ['manufacturing', 'custody', 'damaged_goods']) {
        expect(LicenseEntitlement.instance.grants(f), isFalse, reason: f);
      }
    });

    test('the gated routes are closed', () async {
      await manager.importLicenseDocument(age(issue(days: 1), 3 * 24 * 3600));
      await manager.getCurrentLicense();

      for (final route in [
        '/manufacturing',
        '/manufacturing/orders',
        '/custody',
        '/damaged-items',
      ]) {
        expect(
          LicenseEntitlement.instance.allowsNavigation(route),
          isFalse,
          reason: '$route must be closed after expiry',
        );
      }
    });

    test('a refused write throws and leaves the database untouched', () async {
      await manager.importLicenseDocument(age(issue(days: 1), 3 * 24 * 3600));
      await manager.getCurrentLicense();

      expect(
        () => damagedDao.insertDamagedItem(
          DamagedItemsCompanion.insert(
            productId: productId,
            quantity: 5,
            unitCost: 10,
            totalLoss: 50,
            reason: 'damaged',
            damageDate: DateTime(2026, 1, 1),
          ),
        ),
        throwsA(isA<FeatureNotLicensedException>()),
      );
      expect(
        () => moDao.createOrder(
          ManufacturingOrdersCompanion.insert(
            orderNumber: 'MO-1',
            bomId: 1,
            finishedProductId: 1,
            plannedQuantity: 10,
          ),
        ),
        throwsA(isA<FeatureNotLicensedException>()),
      );
      expect(
        () => custodyDao.insertCustody(
          CashCustodiesCompanion.insert(
            custodyNumber: 'C-1',
            staffId: '1',
            staffName: 'كاشير',
            date: DateTime(2026, 1, 1),
            amount: 1000,
            remainingAmount: 1000,
          ),
        ),
        throwsA(isA<FeatureNotLicensedException>()),
      );

      expect(await db.select(db.damagedItems).get(), isEmpty);
      expect(await db.select(db.manufacturingOrders).get(), isEmpty);
      expect(await db.select(db.cashCustodies).get(), isEmpty);
    });
  });
}

/// Rewrites `iat`/`exp`/`license_expires_at` backwards by [seconds] and
/// re-signs with [signingKeyPath].
String ageDocument(String envelope, int seconds, String signingKeyPath) {
  final map = jsonDecode(envelope) as Map<String, dynamic>;
  final parts = (map['lease'] as String).split('.');
  final payload =
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
  payload['iat'] = (payload['iat'] as int) - seconds;
  payload['exp'] = (payload['exp'] as int) - seconds;
  final expiresAt = payload['license_expires_at'];
  if (expiresAt is int) {
    payload['license_expires_at'] = expiresAt - seconds;
  } else if (expiresAt is String) {
    payload['license_expires_at'] = DateTime.parse(expiresAt)
        .toUtc()
        .subtract(Duration(seconds: seconds))
        .toIso8601String();
  }

  final unsigned =
      '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';
  final signed = Process.runSync('node', [
    '-e',
    'const c=require("crypto"),f=require("fs");'
        'const u=process.argv[1];'
        'const s=c.createSign("RSA-SHA256");s.update(u);'
        'process.stdout.write(u+"."+s.sign(fs.readFileSync(process.argv[2]),"base64url"));',
    unsigned,
    signingKeyPath,
  ]);
  if (signed.exitCode != 0) {
    throw StateError('re-signing failed: ${signed.stderr}');
  }
  map['lease'] = signed.stdout.toString().trim();
  return jsonEncode(map);
}
