import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

const String secretKey = String.fromEnvironment(
  'LICENSE_SECRET_KEY',
  defaultValue: 'CHANGE_ME',
);

/// Duration of the license in days. Defaults to 365 (1 year) so existing
/// usage without the flag keeps working.
const int licenseDays = int.fromEnvironment(
  'LICENSE_DAYS',
  defaultValue: 365,
);

/// Device fingerprint this license is locked to. Defaults to 'UNBOUND'
/// (any device) so existing usage keeps working. For a specific customer,
/// pass their device fingerprint from the activation screen.
const String deviceFingerprint = String.fromEnvironment(
  'DEVICE_FINGERPRINT',
  defaultValue: 'UNBOUND',
);

/// Full set of every feature string checked anywhere in the app (see
/// lib/services/feature_gate_service.dart + lib/services/license_manager.dart).
/// 'all' is a legacy catch-all entry carried over from generate_device_license.dart
/// — hasFeature() is a plain list-contains, so it doesn't act as a wildcard,
/// but including it alongside the real names is harmless and keeps old
/// check-paths working.
const List<String> fullFeatures = [
  'pos',
  'inventory',
  'customers',
  'suppliers',
  'purchases',
  'reports',
  'advanced_reports',
  'accounting',
  'users',
  'staff_management',
  'attendance',
  'payroll',
  'credit_sales',
  'auto_backup',
  'backup',
  'export',
  'admin',
  'all',
];

String _encrypt(String plainText) {
  final keyBytes = md5.convert(utf8.encode(secretKey)).bytes;
  final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
  final iv = encrypt_pkg.IV(Uint8List(16)); // 16 bytes of zeros
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
  );

  final encrypted = encrypter.encrypt(plainText, iv: iv);
  return encrypted.base64;
}

String _generateSignature(String data) {
  final bytes = utf8.encode(data + secretKey);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

void main() {
  if (secretKey == 'CHANGE_ME') {
    stderr.writeln(
      "LICENSE_SECRET_KEY is 'CHANGE_ME'. "
      "Run with: dart run --define=LICENSE_SECRET_KEY=... tools/gen_year_license.dart"
    );
    exit(1);
  }

  final now = DateTime.now();
  final expiry = now.add(Duration(days: licenseDays));

  final licenseData = {
    'device': deviceFingerprint,
    'type': 'professional',
    'issue_date': now.toIso8601String(),
    'expiry': expiry.toIso8601String(),
    'features': fullFeatures,
    'max_users': 999,
    'company_name': 'User License',
    'contact_email': 'support@company.com',
    'version': '1.0',
  };

  final jsonString = jsonEncode(licenseData);
  final encryptedData = _encrypt(jsonString);
  final signature = _generateSignature(encryptedData);
  final licenseKey = '$encryptedData.$signature';

  print('=' * 60);
  print('LICENSE KEY ($licenseDays days - Professional, full features)');
  print('=' * 60);
  print('Type: Professional');
  print('Device: ${deviceFingerprint == 'UNBOUND' ? 'UNBOUND (any device)' : deviceFingerprint}');
  print('Max Users: 999');
  print('Expires: ${expiry.toIso8601String().split('T')[0]}');
  print('Features: ${fullFeatures.join(', ')}');
  print('=' * 60);
  print('\nLICENSE KEY:');
  print(licenseKey);
  print('=' * 60);
  print('\nSummary: ${licenseDays}-day license, '
      '${deviceFingerprint == 'UNBOUND' ? 'UNBOUND (any device)' : 'device-bound'}, '
      '${fullFeatures.length} features, max 999 users.');
}
