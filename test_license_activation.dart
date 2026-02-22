import 'dart:convert';
import 'package:crypto/crypto.dart';

// License activation script for testing
void main() async {
  print('=================================');
  print('   LICENSE ACTIVATION FOR TESTING');
  print('=================================\n');

  // Use a universal device ID for testing
  const deviceId = 'TEST-DEVICE-UNIVERSAL';

  // Create a test license data
  final licenseData = {
    'device': deviceId,
    'expires': DateTime.now().add(const Duration(days: 365)).toIso8601String(),
    'features': [
      'pos',
      'inventory',
      'customers',
      'suppliers',
      'reports',
      'accounting',
      'users',
      'backup',
      'export',
      'admin',
    ],
    'max_users': 999,
    'license_type': 'admin',
    'duration': 'سنوي',
    'duration_days': 365,
    'price_multiplier': 0,
    'created': DateTime.now().toIso8601String(),
    'version': '2.0.0',
    'company_name': 'Test Company',
    'contact_email': 'test@example.com',
    'issue_date': DateTime.now().toIso8601String(),
    'type': 'enterprise',
  };

  const secretKey = 'POS-SaaS-2026-PROD-SECURE-K3Y-F0R-L1C3NS3!';

  final jsonString = jsonEncode(licenseData);
  final bytes = utf8.encode(jsonString);
  final encoded = base64.encode(bytes);
  final hmacBytes = utf8.encode(secretKey);
  final hmac = Hmac(sha256, hmacBytes);
  final signature = hmac.convert(utf8.encode(encoded));
  final licenseKey = '$encoded.${signature.toString()}';

  print('Test License Generated:');
  print('Device ID: $deviceId');
  print('License Key: $licenseKey');
  print('\nCopy this license key and paste it in the activation screen.');
  print('\n=================================');
}
