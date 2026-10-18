import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static source-scan guard for FEAT-013 — an application update must never
/// delete a customer's license.
///
/// Windows installers used to run a "clear old license data" step on every
/// install. That wiped `secure_license.dat` / `.bak` from the AppData folder,
/// so a routine update could cost a paying customer their license.
///
/// The guarded scripts are the DISTRIBUTED installers. `reset_license_and_run.bat`
/// is a developer utility whose entire purpose is to clear the license, so it
/// is deliberately excluded and must keep working.
///
/// This mirrors the existing static-guard convention in
/// `test/unit/hardware_id_service_test.dart`.
void main() {
  /// Files an end customer actually runs. Anything added here is a shipped
  /// artifact that must never touch license storage.
  const installers = <String>[
    'installer/update_factory_setup.iss',
    'installer/Simple_Setup.bat',
    'installer/POS_Factory_Simple_Setup/Simple_Setup.bat',
    'installer/POS_Factory_Setup_v2.3.0.ps1',
    'installer/POS_Factory_Setup_v2.3.0/POS_Factory_Setup_v2.3.0.ps1',
    'installer/factory_setup.iss',
    'installer/install.bat',
    'installer/POS_Factory_Setup_v2.3.0.bat',
    'installer/Run_Setup.bat',
    'installer/Install_Update.bat',
    'installer/update_installer.ps1',
    'installer/POS_Update_Installer.ps1',
  ];

  /// Development-only helper. Clearing the license is the whole point of this
  /// script, so it is intentionally NOT protected by this guard.
  const devTools = <String>['reset_license_and_run.bat'];

  bool deletesLicense(String source) {
    final lines = source
        .split('\n')
        .map((l) => l.trim())
        // Drop comment lines so the explanatory notes in the installers do not
        // read as violations of themselves.
        .where((l) => !l.startsWith('//') && !l.startsWith('REM')
            && !l.startsWith('#') && !l.startsWith('*'));
    for (final line in lines) {
      final mentionsLicense =
          line.contains('secure_license') || line.contains('app_license');
      if (!mentionsLicense) continue;
      final isDelete = line.contains('del ') ||
          line.contains('Remove-Item') ||
          line.contains('DeleteFile') ||
          line.contains('rm ') ||
          line.contains('ClearOldLicenseData');
      if (isDelete) return true;
    }
    return false;
  }

  group('FEAT-013 — installers must never delete license data', () {
    installers.forEach((path) {
      test('$path does not delete the license file', () {
        final file = File(path);
        expect(file.existsSync(), isTrue,
            reason: '$path is listed as a shipped installer but does not '
                'exist. Add the new installer to this list or remove it.');

        final source = file.readAsStringSync();
        expect(
          deletesLicense(source),
          isFalse,
          reason: '$path deletes the customer license. Updating MADAR must '
              'never cost a paying customer their license — a routine update '
              'used to wipe secure_license.dat.',
        );
      });
    });
  });

  group('FEAT-013 — the license file is still acknowledged, not forgotten', () {
    test('Simple_Setup.bat mentions the license so the customer sees it', () {
      final source = File('installer/Simple_Setup.bat').readAsStringSync();
      expect(
        source.contains('secure_license'),
        isTrue,
        reason: 'the installer should tell the customer whether a license file '
            'was found — silently ignoring it is worse than preserving it',
      );
    });
  });

  group('FEAT-013 — the developer reset tool keeps working', () {
    devTools.forEach((path) {
      test('$path still clears the license (by design)', () {
        final file = File(path);
        expect(file.existsSync(), isTrue,
            reason: '$path is the developer reset helper');
        expect(
          deletesLicense(file.readAsStringSync()),
          isTrue,
          reason: '$path exists precisely to wipe the license during testing. '
              'If this stops deleting, the dev workflow breaks.',
        );
      });
    });
  });
}