import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';
import '../../services/firebase_license_service.dart';
import '../../services/license_manager.dart';

/// Service for handling periodic online license validation
/// Performs validation every 7 days with grace period handling
class PeriodicLicenseValidator {
  static const String _lastValidationKey = 'last_online_validation';
  static const Duration _validationInterval = Duration(days: 7);
  static const int _maxOfflineDays = 14; // 7 days + 7 days grace

  // Singleton
  static final PeriodicLicenseValidator _instance =
      PeriodicLicenseValidator._internal();
  factory PeriodicLicenseValidator() => _instance;
  PeriodicLicenseValidator._internal();

  /// Main validation method that checks if periodic validation is needed
  static Future<bool> validateWithPeriodicCheck() async {
    try {
      final licenseManager = LicenseManager();
      final isLicenseValid = await licenseManager.isLicenseValid();

      if (isLicenseValid) {
        // Check if we need to perform periodic online validation
        final needsCheck = await _needsPeriodicValidation();
        if (needsCheck) {
          await _performPeriodicValidation();
        }
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.e('Error validating license: $e');
      return false;
    }
  }

  /// Check if periodic validation is needed (7 days since last validation)
  static Future<bool> _needsPeriodicValidation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastValidationStr = prefs.getString(_lastValidationKey);

      if (lastValidationStr == null) {
        return true; // Never validated before
      }

      final lastValidation = DateTime.parse(lastValidationStr);
      final now = DateTime.now();

      return now.difference(lastValidation) >= _validationInterval;
    } catch (e) {
      AppLogger.e('Error checking if periodic validation needed: $e');
      return true; // On error, try to validate
    }
  }

  /// Perform the actual periodic validation
  static Future<void> _performPeriodicValidation() async {
    try {
      final licenseManager = LicenseManager();
      final currentLicense = await licenseManager.getCurrentLicense();

      if (currentLicense == null) {
        AppLogger.w('No current license found for periodic validation');
        return;
      }

      final firebaseService = FirebaseLicenseService();
      final result = await firebaseService.performCheckinIfNeeded(
        currentLicense.licenseKey,
      );

      // Update last validation timestamp regardless of result
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastValidationKey,
        DateTime.now().toIso8601String(),
      );

      // Handle different validation results
      switch (result.status) {
        case FirebaseLicenseStatus.active:
          AppLogger.i('Periodic validation successful');
          break;

        case FirebaseLicenseStatus.expired:
          AppLogger.w('License expired during periodic validation');
          await _showLicenseWarning('تنبيه: ترخيصك منتهي الصلاحية');
          break;

        case FirebaseLicenseStatus.suspended:
          AppLogger.w('License suspended during periodic validation');
          await _showLicenseWarning('تنبيه: ترخيصك موقوف');
          break;

        case FirebaseLicenseStatus.offline:
          AppLogger.i('Unable to perform online validation, working offline');
          // Check grace period
          final daysSinceLastValidation = await _getDaysSinceLastValidation();
          if (daysSinceLastValidation > _maxOfflineDays) {
            await _showLicenseWarning(
              'تنبيه: لم يتم التحقق من الترخيص منذ فترة طويلة',
            );
          }
          break;

        default:
          AppLogger.w('Unexpected validation status: ${result.status}');
          break;
      }
    } catch (e) {
      AppLogger.e('Error during periodic validation: $e');
    }
  }

  /// Get days since last validation
  static Future<int> _getDaysSinceLastValidation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastValidationStr = prefs.getString(_lastValidationKey);

      if (lastValidationStr == null) {
        return 999; // Never validated
      }

      final lastValidation = DateTime.parse(lastValidationStr);
      return DateTime.now().difference(lastValidation).inDays;
    } catch (e) {
      AppLogger.e('Error calculating days since last validation: $e');
      return 999;
    }
  }

  /// Show license warning to user
  static Future<void> _showLicenseWarning(String message) async {
    // This would typically show a non-intrusive notification
    // For now, we'll just log it
    AppLogger.w('License warning: $message');
    // TODO: Implement in-app notification system
  }

  /// Clear validation cache (for testing or license changes)
  static Future<void> clearValidationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastValidationKey);
      AppLogger.i('License validation cache cleared');
    } catch (e) {
      AppLogger.e('Error clearing validation cache: $e');
    }
  }

  /// Get validation status info
  static Future<Map<String, dynamic>> getValidationStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastValidationStr = prefs.getString(_lastValidationKey);
      final daysSinceLastValidation = await _getDaysSinceLastValidation();
      final needsValidation = await _needsPeriodicValidation();

      return {
        'lastValidation': lastValidationStr,
        'daysSinceLastValidation': daysSinceLastValidation,
        'needsValidation': needsValidation,
        'isInGracePeriod':
            daysSinceLastValidation > 7 && daysSinceLastValidation <= 14,
        'isBeyondGracePeriod': daysSinceLastValidation > 14,
      };
    } catch (e) {
      AppLogger.e('Error getting validation status: $e');
      return {'error': e.toString()};
    }
  }
}
