// Quick license generator for specific needs
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

const String secretKey = String.fromEnvironment(
  'LICENSE_SECRET_KEY',
  defaultValue: 'CHANGE_ME',
);

void main() async {
  print('=================================');
  print('   QUICK LICENSE GENERATOR');
  print('=================================\n');

  print('1. Generate 1-month customer license');
  print('2. Generate 1-year customer license');
  print('3. Generate lifetime admin license');
  stdout.write('\nSelect option (1-3): ');
  final choice = stdin.readLineSync()?.trim() ?? '1';

  stdout.write('Enter Device ID: ');
  final deviceFingerprint = stdin.readLineSync()?.trim() ?? '';
  if (deviceFingerprint.isEmpty) {
    print('ERROR: Device ID is required!');
    exit(1);
  }

  if (choice == '1') {
    await generateCustomerLicense(deviceFingerprint, 1); // 1 month
  } else if (choice == '2') {
    await generateCustomerLicense(deviceFingerprint, 12); // 1 year
  } else if (choice == '3') {
    await generateAdminLicense(deviceFingerprint);
  } else {
    print('Invalid choice!');
  }
}

Future<void> generateCustomerLicense(
  String deviceFingerprint,
  int months,
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
  print('CUSTOMER LICENSE GENERATED');
  print('=' * 60);
  print('Type: Basic');
  print('Max Users: 1');
  print('Duration: $months months (${30 * months} days)');
  print('Expires: ${expiryDate.toIso8601String().split('T')[0]}');
  print('Features: pos, inventory, customers, suppliers, reports, backup');
  print('=' * 60);
  print('\nLICENSE KEY:');
  print(licenseKey);
  print('=' * 60);

  await _saveLicense(licenseData, licenseKey, 'customer_${months}month');
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
  print('Features: ALL FEATURES INCLUDING ADMIN');
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
      : '${(licenseData['license_type'] == 'basic' ? (licenseData['created'] != null ? 6 : 12) : 12)} months';

  await file.writeAsString('''
LICENSE INFORMATION
===================
Generated: ${DateTime.now()}
Device ID: ${licenseData['device']}
Type: ${licenseData['license_type']}
Max Users: ${licenseData['max_users']}
Duration: ${licenseData['license_type'] == 'admin' ? 'LIFETIME' : '${type.contains('1') && type.contains('month') ? '1' : '12'} months'}
Expires: ${licenseData['license_type'] == 'admin' ? 'Never (lifetime license)' : DateTime.parse(licenseData['expiry']).toIso8601String().split('T')[0]}
Features: ${(licenseData['features'] as List).join(", ")}

LICENSE KEY:
$licenseKey
''');

  print('\nLicense saved to: $filename\n');
}
