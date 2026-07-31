import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

const String secretKey = 'CHANGE_ME';

String _encrypt(String plainText) {
  final keyBytes = md5.convert(utf8.encode(secretKey)).bytes;
  final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
  final iv = encrypt_pkg.IV(Uint8List(16));
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
  final now = DateTime.now();
  final expiry = now.add(const Duration(days: 365));

  final licenseData = {
    'device': 'UNBOUND',
    'type': 'professional',
    'issue_date': now.toIso8601String(),
    'expiry': expiry.toIso8601String(),
    'features': [
      'pos',
      'inventory',
      'customers',
      'suppliers',
      'reports',
      'accounting',
      'users',
    ],
    'max_users': 5,
    'company_name': 'User License',
    'contact_email': 'support@company.com',
    'version': '1.0',
  };

  final jsonString = jsonEncode(licenseData);
  final encryptedData = _encrypt(jsonString);
  final signature = _generateSignature(encryptedData);
  final licenseKey = '$encryptedData.$signature';

  print('=' * 60);
  print('LICENSE KEY (1 Year - Professional)');
  print('=' * 60);
  print('Type: Professional');
  print('Device: UNBOUND (any device)');
  print('Max Users: 5');
  print('Expires: ${expiry.toIso8601String().split('T')[0]}');
  print('Features: pos, inventory, customers, suppliers, reports, accounting, users');
  print('=' * 60);
  print('\nLICENSE KEY:');
  print(licenseKey);
  print('=' * 60);
}
