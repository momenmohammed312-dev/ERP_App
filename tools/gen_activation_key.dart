// Generates activation key for a specific device fingerprint
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

const String secretKey = String.fromEnvironment(
  'LICENSE_SECRET_KEY',
  defaultValue: 'CHANGE_ME',
);

const String deviceFingerprint =
    '35fe7a40a81de4830f557fdf783b2f75ca9e9369942ad366306a8cf9dd568181';

String _encrypt(String plainText, String key) {
  final keyBytes = md5.convert(utf8.encode(key)).bytes;
  final encKey = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
  final iv = encrypt_pkg.IV(Uint8List(16));
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(encKey, mode: encrypt_pkg.AESMode.cbc),
  );
  final encrypted = encrypter.encrypt(plainText, iv: iv);
  return encrypted.base64;
}

String _signature(String data, String key) {
  final bytes = utf8.encode(data + key);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

String generateKey(String key, String device, String type, int days,
    List<String> features, int maxUsers) {
  final now = DateTime.now();
  final expiry = now.add(Duration(days: days));

  final data = {
    'device': device,
    'type': type,
    'issue_date': now.toIso8601String(),
    'expiry': expiry.toIso8601String(),
    'features': features,
    'max_users': maxUsers,
    'company_name': 'User Device',
    'contact_email': 'admin@mo2.com',
    'version': '1.0',
  };

  final encrypted = _encrypt(jsonEncode(data), key);
  return '$encrypted.${_signature(encrypted, key)}';
}

void main() {
  if (secretKey == 'CHANGE_ME') {
    stderr.writeln(
      "LICENSE_SECRET_KEY is 'CHANGE_ME'. "
      "Run with: dart --define=LICENSE_SECRET_KEY=... tools/gen_activation_key.dart"
    );
    exit(1);
  }

  final allFeatures = [
    'cash_sales',
    'credit_sales',
    'customers',
    'suppliers',
    'purchases',
    'inventory',
    'advanced_reports',
    'auto_backup',
    'staff_management',
    'attendance',
    'payroll',
    'admin_dashboard',
    'api_access',
  ];

  print('===== بصمة الجهاز الحالية =====');
  print('Device: $deviceFingerprint\n');

  // Use unified secretKey for all variants
  final k1 = generateKey(secretKey, deviceFingerprint, 'professional', 365, allFeatures, 5);
  print('--- Production key - Professional 1 year ---');
  print(k1);
  print('');

  final k2 = generateKey(secretKey, 'UNBOUND', 'professional', 365, allFeatures, 5);
  print('--- Floating (UNBOUND) - Production key - Professional 1 year ---');
  print(k2);
  print('');
}
