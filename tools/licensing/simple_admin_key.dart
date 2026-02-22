import 'dart:convert';
import 'package:crypto/crypto.dart';

// Generate simple admin license key for testing
void main() {
  // Use a simple device ID that will work
  const deviceFingerprint = 'test-device-123';
  
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
  print('   SIMPLE ADMIN LICENSE KEY');
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
  print('Use Device ID: test-device-123');
  print('Use the license key above');
}
