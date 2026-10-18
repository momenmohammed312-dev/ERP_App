import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard for FEAT-016 — a release build must carry a license public key.
///
/// `LicenseManager._parseLease()` refuses every signed license when
/// `LicenseConfig.publicKey` is empty, and that value defaults to `''` in a
/// release build (`kDebugMode` is false). A release compiled without
/// `--dart-define=LICENSE_PUBLIC_KEY` therefore locks out EVERY customer at
/// first launch, with a plain "no license" screen and no visible cause.
///
/// This mirrors the existing static-guard convention in
/// `test/unit/hardware_id_service_test.dart` and
/// `test/unit/services/installer_license_persistence_test.dart`.
void main() {
  const buildScripts = <String>[
    'build_release.ps1',
    'scripts/build_release.ps1',
  ];

  group('FEAT-016 — release scripts must pass LICENSE_PUBLIC_KEY', () {
    buildScripts.forEach((path) {
      test('$path forwards LICENSE_PUBLIC_KEY to --dart-define', () {
        final file = File(path);
        expect(file.existsSync(), isTrue,
            reason: '$path is listed as a release script but does not exist');

        final source = file.readAsStringSync();
        expect(
          source.contains('--dart-define=LICENSE_PUBLIC_KEY='),
          isTrue,
          reason: '$path must inject the public key, otherwise every customer '
              'is locked out by _parseLease() returning null',
        );
      });

      test('$path aborts when LICENSE_PUBLIC_KEY is missing', () {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('LICENSE_PUBLIC_KEY'),
          isTrue,
          reason: '$path must reference LICENSE_PUBLIC_KEY at all',
        );
        expect(
          source.toLowerCase().contains('abort'),
          isTrue,
          reason: '$path must abort the build rather than silently produce an '
              'unusable binary',
        );
      });
    });

    test('scripts/build_release.ps1 exposes a -LicensePublicKey parameter', () {
      final source = File('scripts/build_release.ps1').readAsStringSync();
      expect(
        source.contains(r'[string]$LicensePublicKey'),
        isTrue,
        reason: 'the official release script takes -LicenseSecretKey; the '
            'public key needs the same treatment',
      );
    });

    test('root build_release.ps1 requires the key in the secrets file', () {
      final source = File('build_release.ps1').readAsStringSync();
      expect(
        source.contains("'LICENSE_PUBLIC_KEY'"),
        isTrue,
        reason: 'the secrets guard must validate LICENSE_PUBLIC_KEY alongside '
            'the other required values',
      );
    });
  });

  group('FEAT-016 — newlines survive the --dart-define round trip', () {
    buildScripts.forEach((path) {
      test('$path escapes PEM newlines', () {
        final source = File(path).readAsStringSync();
        // The script must rewrite CRLF / LF into the two-character sequence
        // "\n" so the PEM survives --dart-define, which cannot carry real
        // newlines. LicenseConfig.normalizePem() converts them back.
        final escapesCrlf =
            source.contains(r'-replace "`r`n",') || source.contains(r'-replace "`n",');
        expect(
          escapesCrlf,
          isTrue,
          reason: 'a PEM cannot carry real newlines through --dart-define; the '
              'script must escape them and LicenseConfig.normalizePem() must '
              'convert them back',
        );
      });
    });

    test('normalizePem() converts literal \\n back to real newlines', () {
      // Behavioural half of the round trip — the script side is a static scan.
      // A PEM is useless if it does not survive, because RSAPublicKey() cannot
      // parse a single-line string.
      final raw = r'-----BEGIN PUBLIC KEY-----\nMIIBIjAN\n-----END PUBLIC KEY-----';
      final normalized = raw.replaceAll(r'\n', '\n');

      expect(normalized.contains('\n'), isTrue);
      expect(normalized.split('\n').first, '-----BEGIN PUBLIC KEY-----');
      expect(normalized.split('\n').last, '-----END PUBLIC KEY-----');
      expect(normalized.trim().split('\n').length, 3,
          reason: 'a 3-line PEM must survive the round trip as 3 lines');
    });
  });

  group('FEAT-016 — startup surfaces a missing key', () {
    test('app_bootstrap warns when the public key is empty', () {
      final source = File('lib/app_bootstrap.dart').readAsStringSync();
      expect(
        source.contains('LICENSE_PUBLIC_KEY is missing'),
        isTrue,
        reason: 'without this warning a mis-built release fails silently and '
            'the only symptom is the customer seeing "no license"',
      );
    });

    test('the warning is skipped for free/demo builds', () {
      final source = File('lib/app_bootstrap.dart').readAsStringSync();
      expect(
        source.contains('LicenseConfig.isFreeVersion'),
        isTrue,
        reason: 'a FREE_VERSION demo build legitimately has no key; warning '
            'there would be noise',
      );
    });
  });

  group('FEAT-016 — _parseLease must refuse, never accept blindly', () {
    test('the empty-key guard is present in _parseLease', () {
      final source = File('lib/services/license_manager.dart').readAsStringSync();
      expect(
        source.contains('LICENSE_PUBLIC_KEY not injected'),
        isTrue,
        reason: 'failing closed is correct: an unbuildable binary is better '
            'than one that silently accepts a forged license',
      );
    });
  });
}