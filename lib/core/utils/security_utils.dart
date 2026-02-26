import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecurityUtils {
  static const String _hashSalt = 'POS_2026_SECURE_SALT_v1_';

  /// Hash a password with a secure salt
  static String hashPassword(String password) {
    final bytes = utf8.encode(_hashSalt + password);
    return sha256.convert(bytes).toString();
  }
}
