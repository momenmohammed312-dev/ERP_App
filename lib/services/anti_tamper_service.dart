import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_encryption_service.dart';
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

  /// Check if system clock was tampered
  static Future<bool> detectClockTampering() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encryptedLastDate = prefs.getString(_lastDateKey);

      if (encryptedLastDate == null) {
        // First run - store current date
        await _storeCurrentDate();
        return false; // No tampering
      }

      final db = _db;

      // Decrypt last known date
      final lastDateStr = DatabaseEncryptionService.decryptData(
        encryptedLastDate,
      );
      final lastDate = DateTime.parse(lastDateStr);
      final currentDate = DateTime.now();

      // Check if current date is BEFORE last date
      // Allow small margin for timezone issues (1 hour)
      final timeDiff = currentDate.difference(lastDate);

      if (timeDiff.inHours < -1) {
        // TAMPERING DETECTED!
        AppLogger.w('⚠️ CLOCK TAMPERING DETECTED!');
        AppLogger.w('Last known: $lastDate');
        AppLogger.w('Current: $currentDate');
        AppLogger.w('Difference: ${timeDiff.inHours} hours');

        // Log the tampering attempt
        await AuditService.log(
          db: db,
          action: AuditAction.licenseDeactivate,
          tableName: 'system',
          details: {
            'reason': 'clock_tampering_detected',
            'last_date': lastDate.toIso8601String(),
            'current_date': currentDate.toIso8601String(),
            'difference_hours': timeDiff.inHours,
          },
        );

        return true; // Tampering detected
      }

      // Update last known date
      await _storeCurrentDate();
      return false; // No tampering
    } catch (e) {
      AppLogger.e('Error in tamper detection', e);
      // If decryption fails, the data is likely corrupted or from an incompatible version
      // Reset it to avoid persistent errors and allow the system to re-initialize
      await resetTamperCheck();
      return false;
    }
  }

  /// Store current date encrypted
  static Future<void> _storeCurrentDate() async {
    try {
      final currentDate = DateTime.now();
      final encrypted = DatabaseEncryptionService.encryptData(
        currentDate.toIso8601String(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastDateKey, encrypted);
    } catch (e) {
      AppLogger.e('Error storing date', e);
    }
  }

  /// Reset tamper detection (for legitimate clock changes)
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
