import 'dart:convert';
import 'package:crypto/crypto.dart';

// Generate license key for current device
void main() async {
  // Get device fingerprint
  print('Generating license key for current device...');
  
  // Simulate getting device fingerprint (in real app, this would come from HardwareFingerprintService)
  const deviceFingerprint = 'CURRENT-DEVICE-FINGERPRINT-PLACEHOLDER';
  
  // Admin license data
  final licenseData = {
    'device': deviceFingerprint,
    'expires': DateTime.now().add(const Duration(days: 3650)).toIso8601String(), // 10 years
    'features': ['pos', 'inventory', 'customers', 'reports', 'admin', 'all'],
    'max_users': 999,
    'license_type': 'enterprise_admin',
    'created': DateTime.now().toIso8601String(),
    'version': '2.0.0',
  };

  final jsonString = jsonEncode(licenseData);
  final bytes = utf8.encode(jsonString);
  final encoded = base64.encode(bytes);
  final hmacBytes = utf8.encode('POS2026-SECURE-KEY-32-CHARS!');
  final hmac = Hmac(sha256, hmacBytes);
  final signature = hmac.convert(utf8.encode(encoded));
  final licenseKey = '$encoded.${signature.toString()}';

  print('=================================');
  print('   LICENSE KEY FOR CURRENT DEVICE');
  print('=================================');
  print('Device ID: $deviceFingerprint');
  print('Type: Enterprise Admin');
  print('Max Users: 999');
  print('Duration: 10 years');
  print('Features: All features unlocked');
  print('=================================');
  print('LICENSE KEY:');
  print(licenseKey);
  print('=================================');
  print('');
  print('This license key is valid for your current device only!');
  print('Save this license key for future use.');
  print('');
  print('To generate a license for a different device, run:');
  print('dart run tools/license_generator.dart');
}
