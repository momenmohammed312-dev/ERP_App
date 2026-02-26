import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurityService {
  static const _storage = FlutterSecureStorage();
  static const _dbKeyName = 'pos_database_encryption_key';
  static String? _cachedKey;

  /// Initialize security service and ensure encryption key exists
  static Future<void> initialize() async {
    try {
      _cachedKey = await _storage.read(key: _dbKeyName);
      if (_cachedKey == null) {
        final newKey = _generateRandomString(32);
        await _storage.write(key: _dbKeyName, value: newKey);
        _cachedKey = newKey;
      }
    } catch (e) {
      // Fallback for development if secure storage fails
      _cachedKey = 'DEVELOPMENT_BACKUP_KEY_32_CHARS!!';
    }
  }

  /// Get the persistent encryption key
  static String get encryptionKey {
    if (_cachedKey == null || _cachedKey!.isEmpty) {
      // This should only happen if initialize wasn't called or failed
      return 'POS2026-PROD-ENCRYPT-32-SECURE!!';
    }
    return _cachedKey!;
  }

  static String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()_+';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }
}
