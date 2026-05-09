import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

const String secretKey = 'POS-SaaS-2026-PROD-SECURE-K3Y-F0R-L1C3NS3!';

String _encrypt(String plainText) {
  final keyBytes = md5.convert(utf8.encode(secretKey)).bytes;
  final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
  final iv = encrypt_pkg.IV.fromLength(16);
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
  final deviceFingerprint =
      'db16569b055a26d5789151f1021b895e4106bdf9cf2045fbfc91e8313eeab023';
  final now = DateTime.now();
  final expiryDate = now.add(Duration(days: 36500));
  final licenseData = {
    'device': deviceFingerprint,
    'type': 'enterprise',
    'issue_date': now.toIso8601String(),
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
    'company_name': 'Administrator',
    'contact_email': 'support@company.com',
    'version': '1.0',
  };

  final jsonString = jsonEncode(licenseData);
  final encryptedData = _encrypt(jsonString);
  final signature = _generateSignature(encryptedData);
  final licenseKey = '$encryptedData.$signature';

  print(licenseKey);
}
