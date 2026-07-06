import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_encryption_service.dart';
import '../services/secure_license_storage.dart';
import '../services/audit_service.dart';
import '../core/database/app_database.dart';
import '../core/utils/logger.dart';

class AntiTamperService {
  static const String _lastDateKey = 'last_known_date_encrypted';

  static AppDatabase? _dbInstance;
  static void init(AppDatabase db) {
    _dbInstance = db;
  }

  static AppDatabase get _db => _dbInstance!;

  /// Check if system clock was tampered.
  /// Uses both SharedPreferences (legacy) and SecureLicenseStorage (new).
  static Future<bool> detectClockTampering() async {
    try {
      bool tampered = false;

      // 1. Check via SecureLicenseStorage (session elapsed tracking)
      tampered = await _checkSessionElapsed();
      if (tampered) return true;

      // 2. Check via SharedPreferences (encrypted date comparison)
      tampered = await _checkEncryptedDate();
      return tampered;
    } catch (e) {
      AppLogger.e('Error in tamper detection', e);
      return false;
    }
  }

  /// Check clock tampering via session elapsed time in SecureLicenseStorage.
  static Future<bool> _checkSessionElapsed() async {
    try {
      final data = await SecureLicenseStorage.read();
      if (data == null) return false;

      final now = DateTime.now();
      final calendarElapsed = now.difference(data.lastCheckTime).inMilliseconds;

      // Clock went backwards more than 1 minute
      if (calendarElapsed < -60000) {
        AppLogger.w('⚠️ SESSION TAMPER: Clock rolled back by ${-calendarElapsed}ms');

        await _logTampering(
          reason: 'session_elapsed_rollback',
          lastDate: data.lastCheckTime,
          currentDate: now,
          diffMs: calendarElapsed,
        );

        return true;
      }

      // Also check: session elapsed vs calendar elapsed
      // If total session time is significantly more than calendar time since first run
      // someone may have manipulated the clock forward
      final calendarSinceFirstRun = now.difference(data.firstRunDate).inMilliseconds;
      if (calendarSinceFirstRun > 0 && data.sessionElapsedMs > calendarSinceFirstRun * 1.5) {
        // Session elapsed is 50% more than calendar — suspicious
        AppLogger.w('⚠️ SESSION TAMPER: Session elapsed ($data.sessionElapsedMs) >> calendar ($calendarSinceFirstRun)');

        await _logTampering(
          reason: 'session_elapsed_excess',
          lastDate: data.lastCheckTime,
          currentDate: now,
          diffMs: data.sessionElapsedMs - calendarSinceFirstRun,
        );

        return true;
      }

      return false;
    } catch (e) {
      AppLogger.e('Session elapsed check error', e);
      return false;
    }
  }

  /// Legacy check via encrypted date in SharedPreferences.
  static Future<bool> _checkEncryptedDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encryptedLastDate = prefs.getString(_lastDateKey);

      if (encryptedLastDate == null) {
        await _storeCurrentDate();
        return false;
      }

      final lastDateStr = DatabaseEncryptionService.decryptData(encryptedLastDate);
      final lastDate = DateTime.parse(lastDateStr);
      final currentDate = DateTime.now();

      final timeDiff = currentDate.difference(lastDate);

      if (timeDiff.inHours < -1) {
        AppLogger.w('⚠️ CLOCK TAMPERING (legacy)!');
        AppLogger.w('Last known: $lastDate');
        AppLogger.w('Current: $currentDate');

        await _logTampering(
          reason: 'clock_tampering_legacy',
          lastDate: lastDate,
          currentDate: currentDate,
          diffMs: timeDiff.inMilliseconds,
        );

        return true;
      }

      await _storeCurrentDate();
      return false;
    } catch (e) {
      AppLogger.e('Legacy tamper check error', e);
      await resetTamperCheck();
      return false;
    }
  }

  /// Store current date (both SharedPreferences and SecureLicenseStorage).
  static Future<void> _storeCurrentDate() async {
    try {
      final now = DateTime.now();

      // SharedPreferences (legacy)
      final encrypted = DatabaseEncryptionService.encryptData(now.toIso8601String());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastDateKey, encrypted);

      // SecureLicenseStorage (new) — update lastCheckTime
      final data = await SecureLicenseStorage.read();
      if (data != null) {
        final calendarElapsed = now.difference(data.lastCheckTime).inMilliseconds;
        final adjustedElapsed = (calendarElapsed > 0 && calendarElapsed < 86400000)
            ? data.sessionElapsedMs + calendarElapsed
            : data.sessionElapsedMs;

        await SecureLicenseStorage.write(data.copyWith(
          lastCheckTime: now,
          sessionElapsedMs: adjustedElapsed,
        ));
      }
    } catch (e) {
      AppLogger.e('Error storing date', e);
    }
  }

  /// Log tampering attempt to audit log.
  static Future<void> _logTampering({
    required String reason,
    required DateTime lastDate,
    required DateTime currentDate,
    required int diffMs,
  }) async {
    try {
      final db = _dbInstance;
      if (db == null) return;

      await AuditService.log(
        db: db,
        action: AuditAction.licenseDeactivate,
        tableName: 'system',
        details: {
          'reason': reason,
          'last_date': lastDate.toIso8601String(),
          'current_date': currentDate.toIso8601String(),
          'difference_ms': diffMs,
        },
      );
    } catch (e) {
      AppLogger.e('Failed to log tampering', e);
    }
  }

  /// Reset tamper detection (for legitimate clock changes).
  static Future<void> resetTamperCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastDateKey);
      AppLogger.i('Tamper check reset');
    } catch (e) {
      AppLogger.e('Error resetting tamper check', e);
    }
  }
}
