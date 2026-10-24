// Offline lease verification + online license service tests.
//
// These tests exercise the REAL LicenseManager / OnlineLicenseService code.
// Only the outside world is replaced:
//   * the license server  -> http MockClient
//   * the app data folder -> a temp directory
//   * device IDs          -> HardwareIdService.debug* overrides
//   * the RSA key pair    -> test-only keys in test/fixtures/license
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/hardware_id_service.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/online_license_service.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fixtures = 'test/fixtures/license';
late final String _publicPem;
late final RSAPrivateKey _serverKey;
late final RSAPrivateKey _attackerKey;

const _machine = 'MACHINE-A';
const _install = 'INSTALL-A';

/// Builds a lease exactly like the Edge Function does (RS256, iat/exp in s).
String makeLease({
  String? machine = _machine,
  String? install = _install,
  String plan = 'standard',
  List<String>? features = const ['cash_sales', 'credit_sales'],
  String? licenseExpiresAt,
  Duration validFor = const Duration(days: 30),
  RSAPrivateKey? key,
  String licenseKey = 'MO2-TEST-0001',
}) {
  final now = DateTime.now();
  int secs(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
  return JWT({
    'license_key': licenseKey,
    'machine_guid': machine,
    'install_uuid': install,
    'plan': plan,
    'features': features,
    'license_expires_at': licenseExpiresAt,
    'status': 'active',
    'iat': secs(now.subtract(const Duration(minutes: 1))),
    'exp': secs(now.add(validFor)),
  }).sign(
    key ?? _serverKey,
    algorithm: JWTAlgorithm.RS256,
    noIssueAt: true,
  );
}

String _b64(Map<String, dynamic> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

void main() {
  late Directory tmp;
  final manager = LicenseManager();

  setUpAll(() {
    _publicPem = File('$_fixtures/test_public.pem').readAsStringSync();
    _serverKey = RSAPrivateKey(
      File('$_fixtures/test_private.pem').readAsStringSync(),
    );
    _attackerKey = RSAPrivateKey(
      File('$_fixtures/attacker_private.pem').readAsStringSync(),
    );
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lease_test_');
    SecureLicenseStorage.useDirectory(tmp);
    SharedPreferences.setMockInitialValues({});
    LicenseConfig.publicKeyOverride = _publicPem;
    HardwareIdService.debugMachineGuid = _machine;
    HardwareIdService.debugInstallUuid = _install;
    OnlineLicenseService.apiUrlOverride = 'https://test.local/license_api';
    OnlineLicenseService.httpClientOverride = null;
  });

  tearDown(() async {
    LicenseConfig.publicKeyOverride = null;
    HardwareIdService.debugMachineGuid = null;
    HardwareIdService.debugInstallUuid = null;
    OnlineLicenseService.apiUrlOverride = null;
    OnlineLicenseService.httpClientOverride = null;
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  // ══════════════════════════════════════════════════════════════════════
  group('lease basics', () {
    test('valid lease is accepted and survives a "restart" (read from disk)',
        () async {
      final r = await manager.saveLease(makeLease());
      expect(r.isValid, isTrue, reason: r.errorMessage);

      final lic = await manager.getCurrentLicense();
      expect(lic, isNotNull);
      expect(lic!.licenseKey, 'MO2-TEST-0001');
      expect(lic.type, LicenseType.standard);
      expect(lic.features, containsAll(['cash_sales', 'credit_sales']));
      expect(await manager.isLicenseActive(), isTrue);
    });

    test('nothing stored -> no license, not active', () async {
      expect(await manager.getCurrentLicense(), isNull);
      expect(await manager.isLicenseActive(), isFalse);
    });

    test('renewal replaces the old lease (plan change is picked up)',
        () async {
      await manager.saveLease(makeLease(plan: 'basic'));
      expect((await manager.getCurrentLicense())!.type, LicenseType.basic);
      await manager.saveLease(makeLease(plan: 'professional'));
      expect(
        (await manager.getCurrentLicense())!.type,
        LicenseType.professional,
      );
    });

    test('deactivate() removes the lease', () async {
      await manager.saveLease(makeLease());
      await manager.deactivate();
      expect(await manager.getCurrentLicense(), isNull);
    });

    test('corrupted license file -> null, never throws', () async {
      await manager.saveLease(makeLease());
      await File('${tmp.path}/secure_license.dat').writeAsString('garbage');
      expect(await manager.getCurrentLicense(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('signature / forgery', () {
    test('lease signed with ANOTHER private key is rejected', () async {
      final r = await manager.saveLease(makeLease(key: _attackerKey));
      expect(r.isValid, isFalse);
      expect(await manager.getCurrentLicense(), isNull);
    });

    test('tampered payload (plan upgraded) is rejected', () async {
      final parts = makeLease(plan: 'basic').split('.');
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      payload['plan'] = 'professional';
      final forged = '${parts[0]}.${_b64(payload)}.${parts[2]}';
      expect((await manager.saveLease(forged)).isValid, isFalse);
    });

    test('HS256 token (alg-confusion attempt) is rejected', () async {
      final t = JWT({
        'license_key': 'X',
        'machine_guid': _machine,
        'install_uuid': _install,
        'plan': 'professional',
        'features': <String>[],
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'exp': DateTime.now()
                .add(const Duration(days: 30))
                .millisecondsSinceEpoch ~/
            1000,
      }).sign(SecretKey(_publicPem), algorithm: JWTAlgorithm.HS256);
      expect((await manager.saveLease(t)).isValid, isFalse);
    });

    test('alg:none token is rejected', () async {
      final h = _b64({'alg': 'none', 'typ': 'JWT'});
      final p = _b64({
        'license_key': 'X',
        'machine_guid': _machine,
        'install_uuid': _install,
        'plan': 'professional',
        'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'exp': DateTime.now()
                .add(const Duration(days: 30))
                .millisecondsSinceEpoch ~/
            1000,
      });
      expect((await manager.saveLease('$h.$p.')).isValid, isFalse);
    });

    for (final junk in ['', 'abc', 'a.b.c', '....']) {
      test('garbage "$junk" is rejected without throwing', () async {
        expect((await manager.saveLease(junk)).isValid, isFalse);
      });
    }

    test('public key not configured -> everything rejected', () async {
      LicenseConfig.publicKeyOverride = '';
      expect((await manager.saveLease(makeLease())).isValid, isFalse);
    });

    test('normalizePem converts literal \\n from --dart-define', () {
      expect(
        LicenseConfig.normalizePem(r'-----BEGIN PUBLIC KEY-----\nABC\n-----END PUBLIC KEY-----'),
        '-----BEGIN PUBLIC KEY-----\nABC\n-----END PUBLIC KEY-----',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('device binding (either ID is enough)', () {
    test('both IDs differ -> rejected', () async {
      final t = makeLease(machine: 'OTHER-M', install: 'OTHER-I');
      expect((await manager.saveLease(t)).isValid, isFalse);
    });

    test('only install UUID matches (Windows reinstalled) -> accepted',
        () async {
      final t = makeLease(machine: 'OTHER-M', install: _install);
      expect((await manager.saveLease(t)).isValid, isTrue);
    });

    test('only machine GUID matches (AppData wiped) -> accepted', () async {
      final t = makeLease(machine: _machine, install: 'OTHER-I');
      expect((await manager.saveLease(t)).isValid, isTrue);
    });

    test('empty IDs never match each other', () async {
      HardwareIdService.debugMachineGuid = '';
      HardwareIdService.debugInstallUuid = '';
      final t = makeLease(machine: '', install: '');
      expect((await manager.saveLease(t)).isValid, isFalse);
    });

    test('lease copied to another PC stops working', () async {
      await manager.saveLease(makeLease());
      HardwareIdService.debugMachineGuid = 'OTHER-PC';
      HardwareIdService.debugInstallUuid = 'OTHER-INSTALL';
      expect(await manager.getCurrentLicense(), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('expiry', () {
    test('lease expired 3 days ago is still inside the 7-day grace',
        () async {
      final t = makeLease(validFor: const Duration(days: -3));
      expect((await manager.saveLease(t)).isValid, isTrue);
    });

    test('lease expired 8 days ago needs online renewal', () async {
      final t = makeLease(validFor: const Duration(days: -8));
      expect((await manager.saveLease(t)).isValid, isFalse);
    });

    test('lifetime license (no expiry) is active', () async {
      await manager.saveLease(makeLease(licenseExpiresAt: null));
      expect(await manager.isLicenseActive(), isTrue);
      expect((await manager.getCurrentLicense())!.daysRemaining, greaterThan(3000));
    });

    test('license expiring in 5 days is active', () async {
      final exp = DateTime.now().add(const Duration(days: 5)).toUtc().toIso8601String();
      await manager.saveLease(makeLease(licenseExpiresAt: exp));
      expect(await manager.isLicenseActive(), isTrue);
    });

    // CHANGED 2026-10-18 after merging fa890eb (BUG-007).
    //
    // This test used to assert that a license whose commercial end date passed
    // 5 days ago is still active, because LicenseManager._leaseGraceDays = 7.
    // The owner reviewed a customer report — "after day 7 the counter went
    // negative and the app kept working" — and ruled option (a): HARD EXPIRY,
    // NO GRACE. A license that passed its expiry date is therefore dead
    // immediately, with no 7-day tail.
    //
    // The assertion is inverted rather than deleted so the regression stays
    // covered: if a grace period is ever reintroduced, this fails.
    test('license that ended 5 days ago is NOT active (no grace period)', () async {
      final exp = DateTime.now().subtract(const Duration(days: 5)).toUtc().toIso8601String();
      await manager.saveLease(makeLease(licenseExpiresAt: exp));
      expect(
        await manager.isLicenseActive(),
        isFalse,
        reason: 'BUG-007: the 7-day grace was removed by owner decision. A '
            'commercial licence past its end date must stop granting access '
            'immediately — reintroducing a grace is a product change, not an '
            'accident.',
      );
    });

    test('license that ended 10 days ago is NOT active', () async {
      final exp = DateTime.now().subtract(const Duration(days: 10)).toUtc().toIso8601String();
      await manager.saveLease(makeLease(licenseExpiresAt: exp));
      expect(await manager.isLicenseActive(), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('features & users', () {
    test('server feature list is respected', () async {
      await manager.saveLease(makeLease(features: ['cash_sales']));
      expect(await manager.hasFeature('cash_sales'), isTrue);
      expect(await manager.hasFeature('payroll'), isFalse);
    });

    test('empty feature list falls back to the plan defaults', () async {
      await manager.saveLease(makeLease(plan: 'standard', features: []));
      expect(await manager.hasFeature('credit_sales'), isTrue);
      expect(await manager.hasFeature('payroll'), isFalse);
    });

    test('unknown plan + empty features -> basic defaults, not "everything"',
        () async {
      await manager.saveLease(makeLease(plan: 'weird', features: []));
      expect(await manager.hasFeature('cash_sales'), isTrue);
      expect(await manager.hasFeature('payroll'), isFalse);
    });

    test('max users follow the plan (standard = 3)', () async {
      await manager.saveLease(makeLease(plan: 'standard'));
      expect(await manager.canAddUser(2), isTrue);
      expect(await manager.canAddUser(3), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('clock rollback', () {
    test('device clock >1 day behind the last server time -> rejected',
        () async {
      final ahead = DateTime.now().toUtc().add(const Duration(days: 3));
      await manager.saveLease(makeLease(), serverTime: ahead.toIso8601String());
      expect(await manager.getCurrentLicense(), isNull);
    });

    test('small drift (12h) is tolerated', () async {
      final ahead = DateTime.now().toUtc().add(const Duration(hours: 12));
      await manager.saveLease(makeLease(), serverTime: ahead.toIso8601String());
      expect(await manager.getCurrentLicense(), isNotNull);
    });

    test('a fresh online lease recovers from a rejected clock', () async {
      final ahead = DateTime.now().toUtc().add(const Duration(days: 3));
      await manager.saveLease(makeLease(), serverTime: ahead.toIso8601String());
      expect(await manager.getCurrentLicense(), isNull);
      // user fixes the clock, goes online -> new lease with a sane server_time
      await manager.saveLease(makeLease());
      expect(await manager.getCurrentLicense(), isNotNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  group('OnlineLicenseService', () {
    final svc = OnlineLicenseService();

    http.Response okResp(String token) => http.Response(
          jsonEncode({
            'status': 'success',
            'lease_token': token,
            'expires_at':
                DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'server_time': DateTime.now().toUtc().toIso8601String(),
          }),
          200,
        );
    http.Response errResp(int code, String msg) =>
        http.Response(jsonEncode({'error': msg}), code);

    MockClient client(http.Response Function(http.Request) h, [List<http.Request>? log]) =>
        MockClient((req) async {
          log?.add(req);
          return h(req);
        });

    test('activate success: stores lease + sends the right payload', () async {
      final calls = <http.Request>[];
      OnlineLicenseService.httpClientOverride =
          client((_) => okResp(makeLease()), calls);

      final r = await svc.activateLicense('MO2-TEST-0001');
      expect(r.isAllowed, isTrue);
      expect(await manager.getCurrentLicense(), isNotNull);

      final body = jsonDecode(calls.single.body) as Map<String, dynamic>;
      expect(body['action'], 'activate');
      expect(body['license_key'], 'MO2-TEST-0001');
      expect(body['machine_guid'], _machine);
      expect(body['install_uuid'], _install);
    });

    test('activate with no internet: clear message, nothing stored', () async {
      OnlineLicenseService.httpClientOverride =
          MockClient((_) async => throw const SocketException('offline'));
      final r = await svc.activateLicense('K');
      expect(r.status, OnlineLicenseStatus.offline);
      expect(r.message, contains('الإنترنت'));
      expect(await manager.getCurrentLicense(), isNull);
    });

    test('LICENSE_API_URL not configured -> clear offline message', () async {
      OnlineLicenseService.apiUrlOverride = null; // const default is ''
      final r = await svc.activateLicense('K');
      expect(r.status, OnlineLicenseStatus.offline);
    });

    final rejections = <String, (int, String, OnlineLicenseStatus)>{
      'suspended': (403, 'License is suspended', OnlineLicenseStatus.suspended),
      'revoked': (403, 'License is revoked', OnlineLicenseStatus.revoked),
      'expired': (403, 'License expired', OnlineLicenseStatus.expired),
      'device limit': (
        403,
        'Device limit reached for this license. Contact support to transfer.',
        OnlineLicenseStatus.wrongDevice
      ),
      'device blocked': (403, 'Device blocked', OnlineLicenseStatus.wrongDevice),
      'invalid key': (404, 'Invalid license key', OnlineLicenseStatus.notFound),
    };
    rejections.forEach((name, spec) {
      test('activate: server says "$name" -> mapped, nothing stored', () async {
        OnlineLicenseService.httpClientOverride =
            client((_) => errResp(spec.$1, spec.$2));
        final r = await svc.activateLicense('K');
        expect(r.status, spec.$3);
        expect(r.isAllowed, isFalse);
        expect(await manager.getCurrentLicense(), isNull);
      });
    });

    test('FORGED server (lease signed by attacker) is not accepted', () async {
      OnlineLicenseService.httpClientOverride =
          client((_) => okResp(makeLease(key: _attackerKey)));
      final r = await svc.activateLicense('K');
      expect(r.isAllowed, isFalse);
      expect(await manager.getCurrentLicense(), isNull);
    });

    test('lease for ANOTHER device from the server is not accepted', () async {
      OnlineLicenseService.httpClientOverride = client(
        (_) => okResp(makeLease(machine: 'X', install: 'Y')),
      );
      expect((await svc.activateLicense('K')).isAllowed, isFalse);
      expect(await manager.getCurrentLicense(), isNull);
    });

    test('proxy/HTML error page (502) is treated as "offline", not a rejection',
        () async {
      OnlineLicenseService.httpClientOverride =
          client((_) => http.Response('<html>Bad gateway</html>', 502));
      final r = await svc.activateLicense('K');
      expect(r.status, OnlineLicenseStatus.offline);
      expect(r.isDefinitiveRejection, isFalse);
    });

    group('check-in', () {
      setUp(() async {
        await manager.saveLease(makeLease());
        // pretend the last check-in was 2 days ago so the network is used
        SharedPreferences.setMockInitialValues({
          'online_last_checkin':
              DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        });
      });

      test('server suspends -> lease is dropped (locks on NEXT start)',
          () async {
        OnlineLicenseService.httpClientOverride =
            client((_) => errResp(403, 'License is suspended'));
        final r = await svc.performCheckinIfNeeded('MO2-TEST-0001');
        expect(r.isSuspended, isTrue);
        expect(await manager.getCurrentLicense(), isNull);
      });

      test('server error 500 -> customer keeps working', () async {
        OnlineLicenseService.httpClientOverride =
            client((_) => errResp(500, 'LICENSE_PRIVATE_KEY is not configured'));
        final r = await svc.performCheckinIfNeeded('MO2-TEST-0001');
        expect(r.status, OnlineLicenseStatus.offline);
        expect(await manager.getCurrentLicense(), isNotNull);
      });

      test('no internet -> customer keeps working', () async {
        OnlineLicenseService.httpClientOverride =
            MockClient((_) async => throw const SocketException('offline'));
        await svc.performCheckinIfNeeded('MO2-TEST-0001');
        expect(await manager.getCurrentLicense(), isNotNull);
      });

      test('success renews the lease (new plan visible)', () async {
        OnlineLicenseService.httpClientOverride =
            client((_) => okResp(makeLease(plan: 'professional')));
        final r = await svc.performCheckinIfNeeded('MO2-TEST-0001');
        expect(r.isAllowed, isTrue);
        expect(
          (await manager.getCurrentLicense())!.type,
          LicenseType.professional,
        );
      });

      test('recent check-in (<1 day) makes NO network call', () async {
        SharedPreferences.setMockInitialValues({
          'online_last_checkin': DateTime.now().toIso8601String(),
        });
        final calls = <http.Request>[];
        OnlineLicenseService.httpClientOverride =
            client((_) => okResp(makeLease()), calls);
        final r = await svc.performCheckinIfNeeded('MO2-TEST-0001');
        expect(r.isAllowed, isTrue);
        expect(calls, isEmpty);
      });

      test('check-in older than 1 day does call the server once', () async {
        final calls = <http.Request>[];
        OnlineLicenseService.httpClientOverride =
            client((_) => okResp(makeLease()), calls);
        await svc.performCheckinIfNeeded('MO2-TEST-0001');
        expect(calls, hasLength(1));
        expect(
          (jsonDecode(calls.single.body) as Map)['action'],
          'checkin',
        );
      });
    });
  });
}
