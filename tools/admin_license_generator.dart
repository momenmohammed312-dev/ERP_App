import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

const String secretKey = String.fromEnvironment(
  'LICENSE_SECRET_KEY',
  defaultValue: 'CHANGE_ME',
);

void main(List<String> arguments) async {
  if (secretKey == 'CHANGE_ME') {
    stderr.writeln(
      "LICENSE_SECRET_KEY is 'CHANGE_ME'. "
      "Run with: dart --define=LICENSE_SECRET_KEY=... tools/admin_license_generator.dart"
    );
    exit(1);
  }

  print('=================================');
  print('   ADMIN LICENSE GENERATOR');
  print('=================================\n');

  // Get device ID from command line argument or use default
  final deviceFingerprint = arguments.isNotEmpty
      ? arguments[0]
      : 'test-device-123';

  print('Generating admin license for device: $deviceFingerprint');

  // Admin license configuration
  final adminLicenseData = {
    'device': deviceFingerprint,
    'expires': DateTime.now()
        .add(Duration(days: 36500))
        .toIso8601String(), // 100 years = lifetime
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
    'duration': 'مدى الحياة',
    'duration_days': 36500,
    'price_multiplier': 0,
    'created': DateTime.now().toIso8601String(),
    'version': '2.0.0',
  };

  // Generate license key
  final jsonString = jsonEncode(adminLicenseData);
  final bytes = utf8.encode(jsonString);
  final encoded = base64.encode(bytes);
  final hmacBytes = utf8.encode(secretKey);
  final hmac = Hmac(sha256, hmacBytes);
  final signature = hmac.convert(utf8.encode(encoded));
  final licenseKey = '$encoded.${signature.toString()}';

  // Display results
  print('=' * 60);
  print('ADMIN LICENSE GENERATED SUCCESSFULLY');
  print('=' * 60);
  print('Type: admin');
  print('Duration: مدى الحياة (Lifetime)');
  print('Max Users: 999 (Unlimited)');
  print('Expires: Never (lifetime license)');
  print('Features: ${(adminLicenseData['features'] as List).join(", ")}');
  print('=' * 60);
  print('\nADMIN ACTIVATION KEY:');
  print(licenseKey);
  print('=' * 60);

  // Save to file
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final filename = 'admin_license_$timestamp.txt';
  final file = File('licenses/$filename');
  await file.create(recursive: true);
  await file.writeAsString('''
ADMIN LICENSE INFORMATION
=========================
Generated: ${DateTime.now()}
Device ID: $deviceFingerprint
Type: admin
Max Users: 999
Duration: LIFETIME
Expires: Never (lifetime license)
Features: ${(adminLicenseData['features'] as List).join(", ")}

ADMIN ACTIVATION KEY:
$licenseKey
''');

  print('\nAdmin license saved to: $filename\n');
  print(
    'IMPORTANT: This admin key works with any device ID for testing purposes.',
  );
  print('For production, you should generate keys with specific device IDs.');
}
