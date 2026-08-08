// Non-interactive license generator for testing
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

const String secretKey = String.fromEnvironment(
  'LICENSE_SECRET_KEY',
  defaultValue: 'CHANGE_ME',
);

void main() async {
  print('=================================');
  print('   TEST LICENSE GENERATOR');
  print('=================================\n');

  // Test device ID
  final deviceFingerprint = 'DEVICE_1770116009416_217';

  // Generate 1-month test license
  await generateCustomerLicense(deviceFingerprint, 1, '1month');

  // Generate 1-year test license
  await generateCustomerLicense(deviceFingerprint, 12, '1year');

  // Generate lifetime admin license
  await generateAdminLicense(deviceFingerprint);
}

Future<void> generateCustomerLicense(
  String deviceFingerprint,
  int months,
  String type,
) async {
  print('\nGenerating $months-month customer license...');

  final expiryDate = DateTime.now().add(Duration(days: 30 * months));
  final licenseData = {
    'device': deviceFingerprint,
    'expiry': expiryDate.toIso8601String(),
    'features': [
      'pos',
      'inventory',
      'customers',
      'suppliers',
      'reports',
      'backup',
    ],
    'max_users': 1,
    'license_type': 'basic',
    'created': DateTime.now().toIso8601String(),
    'version': '2.0.0',
  };

  final licenseKey = _generateLicenseKey(licenseData);

  print('\n${'=' * 60}');
  print('CUSTOMER LICENSE GENERATED - $type');
  print('=' * 60);
  print('Type: Basic');
  print('Max Users: 1');
  print('Duration: $months months (${30 * months} days)');
  print('Expires: ${expiryDate.toIso8601String().split('T')[0]}');
  print('Device ID: $deviceFingerprint');
  print('=' * 60);
  print('\nLICENSE KEY:');
  print(licenseKey);
  print('=' * 60);

  await _saveLicense(licenseData, licenseKey, 'customer_$type');
}

Future<void> generateAdminLicense(String deviceFingerprint) async {
  print('\nGenerating lifetime admin license...');

  final expiryDate = DateTime.now().add(Duration(days: 365 * 100)); // 100 years
  final licenseData = {
    'device': deviceFingerprint,
    'expiry': expiryDate.toIso8601String(),
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
    'created': DateTime.now().toIso8601String(),
    'version': '2.0.0',
  };

  final licenseKey = _generateLicenseKey(licenseData);

  print('\n${'=' * 60}');
  print('ADMINISTRATOR LICENSE GENERATED');
  print('=' * 60);
  print('Type: Administrator');
  print('Max Users: 999 (unlimited)');
  print('Duration: LIFETIME');
  print('Expires: Never (lifetime license)');
  print('Device ID: $deviceFingerprint');
  print('=' * 60);
  print('\nLICENSE KEY:');
  print(licenseKey);
  print('=' * 60);

  await _saveLicense(licenseData, licenseKey, 'admin_lifetime');
}

String _generateLicenseKey(Map<String, dynamic> licenseData) {
  final jsonString = jsonEncode(licenseData);
  final bytes = utf8.encode(jsonString);
  final encoded = base64.encode(bytes);
  final hmacBytes = utf8.encode(secretKey);
  final hmac = Hmac(sha256, hmacBytes);
  final signature = hmac.convert(utf8.encode(encoded));
  return '$encoded.${signature.toString()}';
}

Future<void> _saveLicense(
  Map<String, dynamic> licenseData,
  String licenseKey,
  String type,
) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final filename = 'license_${type}_$timestamp.txt';
  final file = File('licenses/$filename');
  await file.create(recursive: true);

  final expiry = licenseData['license_type'] == 'admin'
      ? 'Never (lifetime license)'
      : DateTime.parse(licenseData['expiry']).toIso8601String().split('T')[0];

  await file.writeAsString('''
LICENSE INFORMATION
===================
Generated: ${DateTime.now()}
Device ID: ${licenseData['device']}
Type: ${licenseData['license_type']}
Max Users: ${licenseData['max_users']}
Duration: ${licenseData['license_type'] == 'admin' ? 'LIFETIME' : '${type.contains('1') && type.contains('month') ? '1' : '12'} months'}
Expires: $expiry
Features: ${(licenseData['features'] as List).join(", ")}

LICENSE KEY:
$licenseKey
''');

  print('\nLicense saved to: $filename\n');
}
