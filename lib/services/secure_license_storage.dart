import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../config/license_config.dart';
import '../core/utils/logger.dart';
import 'database_encryption_service.dart';

/// Encrypted, tamper-proof storage for license data.
/// Replaces SharedPreferences for all license-related data.
///
/// File format: AES-encrypted JSON, signed with HMAC-SHA256.
/// Location: %APPDATA%/pos_offline_desktop/secure_license.dat
/// Survives uninstall (AppData is not removed).
class SecureLicenseStorage {
  static const String _fileName = 'secure_license.dat';
  static const String _backupFileName = 'secure_license.bak';
  static Directory? _appDir;

  /// Initialize the storage directory.
  static Future<void> init() async {
    try {
      _appDir = await getApplicationSupportDirectory();
    } catch (e) {
      AppLogger.e('Failed to get app directory', e);
      // Fallback: use temp directory (NOT Directory.current, which may be Program Files)
      _appDir = Directory.systemTemp;
    }
  }

  static File get _file => File('${_appDir!.path}/$_fileName');
  static File get _backupFile => File('${_appDir!.path}/$_backupFileName');

  // ════════════════════════════════════════════════════════════════
  //  READ / WRITE
  // ════════════════════════════════════════════════════════════════

  /// Read and decrypt the license data. Returns null if file doesn't exist or is corrupt.
  static Future<SecureLicenseData?> read() async {
    try {
      if (!await _file.exists()) {
        // Try backup
        if (await _backupFile.exists()) {
          AppLogger.w('Primary file missing, restoring from backup');
          await _backupFile.copy(_file.path);
        } else {
          return null;
        }
      }

      final encryptedContent = await _file.readAsString();

      // Verify HMAC signature
      final signatureValid = _verifySignature(encryptedContent);
      if (!signatureValid) {
        AppLogger.w('License file signature INVALID — possible tampering');

        // Try backup
        if (await _backupFile.exists()) {
          AppLogger.w('Attempting recovery from backup');
          final backupContent = await _backupFile.readAsString();
          if (_verifySignature(backupContent)) {
            await _backupFile.copy(_file.path);
            return _decryptAndParse(backupContent);
          }
        }

        return null;
      }

      return _decryptAndParse(encryptedContent);
    } catch (e) {
      AppLogger.e('Error reading secure license', e);
      return null;
    }
  }

  /// Write and encrypt the license data. Creates backup before overwriting.
  static Future<bool> write(SecureLicenseData data) async {
    try {
      if (_appDir == null) await init();

      // Create backup of current file
      if (await _file.exists()) {
        await _file.copy(_backupFile.path);
      }

      // Serialize, encrypt, sign
      final json = data.toJson();
      final jsonString = jsonEncode(json);
      final encrypted = DatabaseEncryptionService.encryptData(jsonString);
      final signature = _computeSignature(encrypted);
      final fileContent = '$encrypted\n$signature';

      await _file.writeAsString(fileContent);
      AppLogger.i('Secure license saved to ${_file.path}');
      return true;
    } catch (e) {
      AppLogger.e('Error writing secure license', e);
      return false;
    }
  }

  /// Delete the license file (and backup).
  static Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
      if (await _backupFile.exists()) await _backupFile.delete();
    } catch (e) {
      AppLogger.e('Error clearing secure license', e);
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  SIGNATURE (HMAC-SHA256)
  // ════════════════════════════════════════════════════════════════

  static String _computeSignature(String encryptedPayload) {
    final key = utf8.encode(LicenseConfig.secretKey);
    final bytes = utf8.encode(encryptedPayload);
    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  static bool _verifySignature(String fileContent) {
    try {
      final lines = fileContent.split('\n');
      if (lines.length < 2) return false;
      final encryptedPayload = lines[0];
      final storedSignature = lines[1];
      final expectedSignature = _computeSignature(encryptedPayload);
      return expectedSignature == storedSignature;
    } catch (_) {
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════
  //  DECRYPT
  // ════════════════════════════════════════════════════════════════

  static SecureLicenseData? _decryptAndParse(String fileContent) {
    try {
      final encryptedPayload = fileContent.split('\n')[0];
      final decrypted = DatabaseEncryptionService.decryptData(encryptedPayload);
      final json = jsonDecode(decrypted) as Map<String, dynamic>;
      return SecureLicenseData.fromJson(json);
    } catch (e) {
      AppLogger.e('Failed to decrypt license file', e);
      return null;
    }
  }
}

/// Data model for the secure license file.
class SecureLicenseData {
  final DateTime firstRunDate;
  final String hardwareId;
  final Map<String, dynamic>? licenseJson;
  final DateTime lastCheckTime;
  final int sessionElapsedMs;
  final int installCount;
  final String? appVersion;

  SecureLicenseData({
    required this.firstRunDate,
    required this.hardwareId,
    this.licenseJson,
    required this.lastCheckTime,
    this.sessionElapsedMs = 0,
    this.installCount = 1,
    this.appVersion,
  });

  /// Create a fresh entry for first run.
  factory SecureLicenseData.create({
    required DateTime firstRunDate,
    required String hardwareId,
    Map<String, dynamic>? licenseJson,
    String? appVersion,
  }) {
    return SecureLicenseData(
      firstRunDate: firstRunDate,
      hardwareId: hardwareId,
      licenseJson: licenseJson,
      lastCheckTime: DateTime.now(),
      sessionElapsedMs: 0,
      installCount: 1,
      appVersion: appVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'first_run_date': firstRunDate.toIso8601String(),
    'hardware_id': hardwareId,
    'license': licenseJson,
    'last_check_time': lastCheckTime.toIso8601String(),
    'session_elapsed_ms': sessionElapsedMs,
    'install_count': installCount,
    'app_version': appVersion,
  };

  factory SecureLicenseData.fromJson(Map<String, dynamic> json) {
    return SecureLicenseData(
      firstRunDate: DateTime.parse(json['first_run_date']),
      hardwareId: json['hardware_id'] ?? '',
      licenseJson: json['license'] as Map<String, dynamic>?,
      lastCheckTime: DateTime.tryParse(json['last_check_time'] ?? '') ?? DateTime.now(),
      sessionElapsedMs: json['session_elapsed_ms'] ?? 0,
      installCount: json['install_count'] ?? 1,
      appVersion: json['app_version'] as String?,
    );
  }

  /// Copy with modifications.
  SecureLicenseData copyWith({
    DateTime? firstRunDate,
    String? hardwareId,
    Map<String, dynamic>? licenseJson,
    DateTime? lastCheckTime,
    int? sessionElapsedMs,
    int? installCount,
    String? appVersion,
    bool clearLicense = false,
  }) {
    return SecureLicenseData(
      firstRunDate: firstRunDate ?? this.firstRunDate,
      hardwareId: hardwareId ?? this.hardwareId,
      licenseJson: clearLicense ? null : (licenseJson ?? this.licenseJson),
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
      sessionElapsedMs: sessionElapsedMs ?? this.sessionElapsedMs,
      installCount: installCount ?? this.installCount,
      appVersion: appVersion ?? this.appVersion,
    );
  }
}
