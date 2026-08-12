import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/services/hardware_id_service.dart';

void main() {
  // Initialize test binding to avoid DeviceInfo warnings
  TestWidgetsFlutterBinding.ensureInitialized();
  group('HardwareComponents', () {
    test('toHashString uses name, cores and deviceId (stable, no RAM)', () {
      final components = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-1234',
      );

      final hashString = components.toHashString();

      expect(hashString, contains('name:TEST-PC'));
      expect(hashString, contains('cores:8'));
      expect(hashString, contains('deviceId:GUID-1234'));
      expect(hashString, isNot(contains('ram')));
      expect(hashString, isNot(contains('memory')));
    });

    test('toHashString omits deviceId when absent (non-Windows)', () {
      final components = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
      );

      final hashString = components.toHashString();

      expect(hashString, contains('name:TEST-PC'));
      expect(hashString, contains('cores:8'));
      expect(hashString, isNot(contains('deviceId')));
    });

    test('countMatches returns correct match count', () {
      final components1 = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-1234',
      );

      final components2 = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-9999', // Different deviceId
      );

      final matches = components1.countMatches(components2);

      // Should match 2 components (name and cores), deviceId is NOT counted
      // because the saved value differs
      expect(matches, equals(2));
    });

    test('countMatches with different computerName', () {
      final components1 = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-1234',
      );

      final components2 = HardwareComponents(
        computerName: 'DIFFERENT-PC',
        numberOfCores: 8,
        deviceId: 'GUID-9999',
      );

      final matches = components1.countMatches(components2);

      // Should match 1 component (cores only)
      expect(matches, equals(1));
    });

    test('countMatches with no matches', () {
      final components1 = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-1234',
      );

      final components2 = HardwareComponents(
        computerName: 'DIFFERENT-PC',
        numberOfCores: 4,
        deviceId: 'GUID-9999',
      );

      final matches = components1.countMatches(components2);

      // Should match 0 components
      expect(matches, equals(0));
    });

    test('toJson and fromJson roundtrip', () {
      final original = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-1234',
      );

      final json = original.toJson();
      final restored = HardwareComponents.fromJson(json);

      expect(restored.computerName, equals(original.computerName));
      expect(restored.numberOfCores, equals(original.numberOfCores));
      expect(restored.deviceId, equals(original.deviceId));
    });

    test('toJson with null deviceId', () {
      final components = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
      );

      final json = components.toJson();

      expect(json, containsPair('computerName', 'TEST-PC'));
      expect(json, containsPair('numberOfCores', 8));
      expect(json, isNot(contains('deviceId')));
    });
  });

  group('Fingerprint Stability', () {
    test('Same components produce same hash string', () {
      final components1 = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-1234',
      );

      final components2 = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-1234',
      );

      expect(components1.toHashString(), equals(components2.toHashString()));
    });

    test('Different deviceId produces different hash string', () {
      final components1 = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-1234',
      );

      final components2 = HardwareComponents(
        computerName: 'TEST-PC',
        numberOfCores: 8,
        deviceId: 'GUID-9999',
      );

      expect(
        components1.toHashString(),
        isNot(equals(components2.toHashString())),
      );
    });
  });

  group('HardwareIdService', () {
    test('isSameDeviceTolerant with null savedComponents falls back to hash comparison', () async {
      // This is a basic test - full integration testing would require mocking
      // the actual hardware info which is complex
      // Since we can't mock device_info_plus easily, we just verify
      // the method structure is correct and returns a boolean
      final result = await HardwareIdService.isSameDeviceTolerant(
        'test-hash',
        null,
      );
      // With null components and no matching hash, it should return false
      expect(result, isA<bool>());
      expect(result, isFalse);
    });
  });
}
