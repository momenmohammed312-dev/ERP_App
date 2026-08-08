import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

const String secretKey = String.fromEnvironment(
  'LICENSE_SECRET_KEY',
  defaultValue: 'CHANGE_ME',
);

void main() async {
  if (secretKey == 'CHANGE_ME') {
    stderr.writeln(
      "LICENSE_SECRET_KEY is 'CHANGE_ME'. "
      "Run with: dart --define=LICENSE_SECRET_KEY=... tools/licensing/quick_test_license.dart"
    );
    exit(1);
  }

  print('=================================');
  print('   QUICK LICENSE GENERATOR');
  print('=================================\n');

  // Use test device fingerprint
  final deviceFingerprint = 'test-device-123';
  print('Using Device ID: $deviceFingerprint');

  // Generate Standard license (3 users, yearly)
  final expiryDate = DateTime.now().add(const Duration(days: 365));
  final licenseData = {
    'device': deviceFingerprint,
    'expiry': expiryDate.toIso8601String(),
    'features': ['pos', 'inventory', 'customers', 'suppliers', 'reports'],
    'max_users': 3,
    'license_type': 'standard',
    'created': DateTime.now().toIso8601String(),
    'version': '2.0.0',
  };

  final jsonString = jsonEncode(licenseData);
  final bytes = utf8.encode(jsonString);
  final encoded = base64.encode(bytes);
  final hmacBytes = utf8.encode(secretKey);
  final hmac = Hmac(sha256, hmacBytes);
  final signature = hmac.convert(utf8.encode(encoded));
  final licenseKey = '$encoded.${signature.toString()}';

  // Display results
  print('\n${'=' * 60}');
  print('STANDARD LICENSE GENERATED');
  print('=' * 60);
  print('Type: standard');
  print('Duration: Yearly (365 days)');
  print('Max Users: 3');
  print('Expires: ${expiryDate.toIso8601String().split('T')[0]}');
  print('Features: pos, inventory, customers, suppliers, reports');
  print('=' * 60);
  print('\nLICENSE KEY:');
  print(licenseKey);
  print('=' * 60);

  // Save to file
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final filename = 'test_license_standard_$timestamp.txt';
  final file = File('licenses/$filename');
  await file.create(recursive: true);
  await file.writeAsString('''
TEST LICENSE INFORMATION
========================
Generated: ${DateTime.now()}
Device ID: $deviceFingerprint
Type: standard
Max Users: 3
Duration: 365 days
Expires: ${expiryDate.toIso8601String().split('T')[0]}
Features: pos, inventory, customers, suppliers, reports

LICENSE KEY:
$licenseKey
''');

  print('\nLicense saved to: $filename\n');
  print('Copy this license key for testing:');
  print(licenseKey);
}
