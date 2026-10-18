import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurityService {
  static const _storage = FlutterSecureStorage();
  static const _dbKeyName = 'pos_database_encryption_key';
  static String? _cachedKey;

  /// Last-resort key, used ONLY when platform secure storage is unavailable.
  ///
  /// MUST be exactly 32 bytes — AES-256 accepts only 128/192/256 bits.
  /// FEAT-013: the old `catch` fallback
  /// `DEVELOPMENT_BACKUP_KEY_32_CHARS!!` was **33 bytes (264 bits)** despite
  /// its name, so `DatabaseEncryptionService` threw
  /// "Key length not 128/192/256 bits" and EVERY
  /// `SecureLicenseStorage.write()` failed silently — a paying customer's
  /// license was never persisted. Nothing can have been encrypted with the
  /// broken value, so correcting the length costs no data.
  static const String _fallbackKey = 'POS2026-PROD-ENCRYPT-32-SECURE!!';

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
      _cachedKey = _fallbackKey;
    }
  }

  /// Get the persistent encryption key
  static String get encryptionKey {
    if (_cachedKey == null || _cachedKey!.isEmpty) {
      // Should only happen if initialize() was never called.
      return _fallbackKey;
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
