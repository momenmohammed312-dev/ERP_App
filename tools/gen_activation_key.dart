// Generates activation key for a specific device fingerprint
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

const String deviceFingerprint =
    '35fe7a40a81de4830f557fdf783b2f75ca9e9369942ad366306a8cf9dd568181';

String _encrypt(String plainText, String secretKey) {
  final keyBytes = md5.convert(utf8.encode(secretKey)).bytes;
  final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
  final iv = encrypt_pkg.IV(Uint8List(16));
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
  );
  final encrypted = encrypter.encrypt(plainText, iv: iv);
  return encrypted.base64;
}

String _signature(String data, String secretKey) {
  final bytes = utf8.encode(data + secretKey);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

String generateKey(String secretKey, String device, String type, int days,
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

  final encrypted = _encrypt(jsonEncode(data), secretKey);
  return '$encrypted.${_signature(encrypted, secretKey)}';
}

void main() {
  const prodKey = 'POS-SaaS-2026-PROD-SECURE-K3Y-F0R-L1C3NS3!';
  const defaultKey = 'CHANGE_ME';
  const trialKey = 'CHANGE_ME';
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

  print('===== ببصمة الجهاز الحالية =====');
  print('Device: $deviceFingerprint\n');

  // --- PROD key ---
  final k1 = generateKey(prodKey, deviceFingerprint, 'professional', 365, allFeatures, 5);
  print('--- Production key (POS-SaaS...) - Professional 1 year ---');
  print(k1);
  print('');

  // --- Default key ---
  final k2 = generateKey(defaultKey, deviceFingerprint, 'professional', 365, allFeatures, 5);
  print('--- Default key (CHANGE_ME) - Professional 1 year ---');
  print(k2);
  print('');

  // --- UNBOUND with prod key ---
  final k3 = generateKey(prodKey, 'UNBOUND', 'professional', 365, allFeatures, 5);
  print('--- Floating (UNBOUND) - Production key - Professional 1 year ---');
  print(k3);
  print('');

  // --- UNBOUND with default key ---
  final k4 = generateKey(defaultKey, 'UNBOUND', 'professional', 365, allFeatures, 5);
  print('--- Floating (UNBOUND) - Default key (CHANGE_ME) - Professional 1 year ---');
  print(k4);
}