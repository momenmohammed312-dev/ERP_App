import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

void main() async {
  final deviceInfo = DeviceInfoPlugin();
  String fingerprint = '';

  try {
    if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      fingerprint =
          '${windowsInfo.computerName}-'
          '${windowsInfo.numberOfCores}-'
          '${windowsInfo.systemMemoryInMegabytes}';
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfo.linuxInfo;
      fingerprint =
          '${linuxInfo.machineId ?? 'unknown'}-'
          '${linuxInfo.name}';
    } else if (Platform.isMacOS) {
      final macInfo = await deviceInfo.macOsInfo;
      fingerprint =
          '${macInfo.systemGUID ?? 'unknown'}-'
          '${macInfo.model}';
    }
    
    // Hash the fingerprint for security
    final bytes = utf8.encode(fingerprint);
    final digest = sha256.convert(bytes);
    final hashedFingerprint = digest.toString();
    
    print('=================================');
    print('   DEVICE FINGERPRINT');
    print('=================================');
    print('Original: $fingerprint');
    print('Hashed: $hashedFingerprint');
    print('=================================');
    
    // Generate license key for this device
    final licenseData = {
      'device': hashedFingerprint,
      'expires': DateTime.now().add(const Duration(days: 3650)).toIso8601String(),
      'features': ['pos', 'inventory', 'customers', 'reports', 'admin', 'all'],
      'max_users': 999,
      'license_type': 'enterprise_admin',
      'created': DateTime.now().toIso8601String(),
      'version': '2.0.0',
    };

    final jsonString = jsonEncode(licenseData);
    final bytes2 = utf8.encode(jsonString);
    final encoded = base64.encode(bytes2);
    final hmacBytes = utf8.encode('POS2026-SECURE-KEY-32-CHARS!');
    final hmac = Hmac(sha256, hmacBytes);
    final signature = hmac.convert(utf8.encode(encoded));
    final licenseKey = '$encoded.${signature.toString()}';

    print('LICENSE KEY FOR THIS DEVICE:');
    print(licenseKey);
    print('=================================');
    
  } catch (e) {
    print('Error: $e');
  }
}
