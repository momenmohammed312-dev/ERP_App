import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

void main() {
  const String secretKey = 'POS-SaaS-2026-PROD-SECURE-K3Y-F0R-L1C3NS3!';
  const String deviceId =
      'db16569b055a26d5789151f1021b895e4106bdf9cf2045fbfc91e8313eeab023';

  final now = DateTime.now();
  final expiry = now.add(const Duration(days: 365));

  final licenseData = {
    'device': deviceId,
    'type': 'professional',
    'issue_date': now.toIso8601String(),
    'expiry': expiry.toIso8601String(),
    'features': [
      'sales',
      'inventory',
      'customers',
      'suppliers',
      'staff_management',
      'multi_user'
    ],
    'max_users': 5,
    'company_name': 'Momen Device',
    'contact_email': 'admin@mo2.com',
    'version': '1.0',
  };

  final jsonString = jsonEncode(licenseData);

  // Encrypt
  final keyBytes = md5.convert(utf8.encode(secretKey)).bytes;
  final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
  final iv = encrypt_pkg.IV.fromLength(16);
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
  );

  final encrypted = encrypter.encrypt(jsonString, iv: iv);
  final encryptedData = encrypted.base64;

  // Sign
  final bytes = utf8.encode(encryptedData + secretKey);
  final digest = sha256.convert(bytes);
  final signature = digest.toString();

  print('GENERATED_KEY: $encryptedData.$signature');
}
