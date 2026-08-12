import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Static source-scan guard for the hardware fingerprint formula.
///
/// The Windows RAM figure (`systemMemoryInMegabytes`) is not stable across
/// boots/updates (OS-reserved memory, integrated GPU shared memory, Windows
/// updates can shift it by small amounts). Because the fingerprint is a
/// SHA-256 hash, a single-MB shift changes the hash and makes a genuine
/// returning device look "new", forcing license re-activation.
///
/// The fix uses the stable Windows `deviceId` instead. We cannot mock
/// `device_info_plus` platform channels in a simple unit test, so this test
/// verifies statically that the unstable signal never reappears in either
/// file and that the stable `deviceId` signal is present.
void main() {
  const serviceSource = 'lib/services/hardware_id_service.dart';
  const toolSource = 'tools/device/get_device_fingerprint.dart';

  group('hardware fingerprint source stability', () {
    for (final path in [serviceSource, toolSource]) {
      test('$path never references the unstable RAM signal', () {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('systemMemoryInMegabytes')),
            reason: 'the unstable Windows RAM signal must never be used in '
                'the fingerprint formula (it causes false re-activation when '
                'the reported RAM shifts between boots/updates)');
      });

      test('$path uses the stable Windows deviceId signal', () {
        final source = File(path).readAsStringSync();
        expect(source, contains('deviceId'),
            reason: 'the Windows fingerprint must be built from the stable '
                'deviceId signal, not the volatile RAM value');
      });
    }
  });
}
