import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'security_service.dart';

class DatabaseEncryptionService {
  static encrypt_pkg.Key get _key =>
      encrypt_pkg.Key.fromUtf8(SecurityService.encryptionKey);

  static encrypt_pkg.Encrypter get _encrypter => encrypt_pkg.Encrypter(
    encrypt_pkg.AES(_key, mode: encrypt_pkg.AESMode.cbc),
  );

  /// Encrypt sensitive data
  static String encryptData(String plainText) {
    try {
      final iv = encrypt_pkg.IV.fromSecureRandom(16);
      final encrypted = _encrypter.encrypt(plainText, iv: iv);
      final combined = iv.bytes + encrypted.bytes;
      return base64Encode(combined);
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  /// Decrypt data
  static String decryptData(String encryptedText) {
    try {
      final combined = base64Decode(encryptedText);
      final ivBytes = combined.sublist(0, 16);
      final encryptedBytes = combined.sublist(16);
      final iv = encrypt_pkg.IV(ivBytes);
      final encrypted = encrypt_pkg.Encrypted(encryptedBytes);
      return _encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  /// Encrypt JSON object
  static String encryptJson(Map<String, dynamic> jsonData) {
    final jsonString = jsonEncode(jsonData);
    return encryptData(jsonString);
  }

  /// Decrypt to JSON
  static Map<String, dynamic> decryptJson(String encryptedText) {
    final decrypted = decryptData(encryptedText);
    return jsonDecode(decrypted) as Map<String, dynamic>;
  }
}
