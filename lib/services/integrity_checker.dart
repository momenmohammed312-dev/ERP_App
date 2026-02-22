import 'dart:async';
import 'package:flutter/foundation.dart';
import 'license_manager.dart';
import 'anti_tamper_service.dart';
import 'audit_service.dart';
import 'user_session_service.dart';
import '../core/database/database_singleton.dart';

class IntegrityChecker {
  static Timer? _periodicCheckTimer;
  static bool _isRunning = false;
  static bool _lastCheckResult = true;
  static DateTime? _lastCheckTime;
  static int _consecutiveFailures = 0;

  /// Start periodic integrity checks
  static void startPeriodicCheck() {
    if (_isRunning) {
      debugPrint('Integrity checker already running');
      return;
    }

    _isRunning = true;
    debugPrint('🔍 Starting integrity checker (every 30 minutes)');

    // Run first check immediately
    _performCheck();

    // Schedule periodic checks every 30 minutes
    _periodicCheckTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _performCheck();
    });
  }

  /// Stop the integrity checker
  static void stop() {
    _isRunning = false;
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    debugPrint('🛑 Integrity checker stopped');
  }

  /// Perform a complete integrity check
  static Future<void> _performCheck() async {
    try {
      debugPrint('🔍 Performing integrity check...');
      _lastCheckTime = DateTime.now();

      final db = await DatabaseSingleton.getInstance();

      // Check 1: License validity
      final licenseValid = await _checkLicenseValidity();

      // Check 2: Clock tampering
      final clockTampered = await AntiTamperService.detectClockTampering();

      // Check 3: User session limits
      final sessionStats = await UserSessionService.getSessionStats();
      final sessionsValid =
          !sessionStats['isAtLimit'] ||
          sessionStats['utilizationPercent'] <= 100;

      // Overall result
      final checkResult = licenseValid && !clockTampered && sessionsValid;

      if (checkResult) {
        _consecutiveFailures = 0;
        debugPrint('✅ Integrity check passed');
      } else {
        _consecutiveFailures++;
        debugPrint(
          '❌ Integrity check failed (consecutive failures: $_consecutiveFailures)',
        );
        await _handleFailedCheck(
          licenseValid,
          clockTampered,
          sessionsValid,
          sessionStats,
        );
      }

      _lastCheckResult = checkResult;

      // Log the check result
      await AuditService.log(
        db: db,
        action: AuditAction.read,
        tableName: 'system_integrity',
        details: {
          'check_time': _lastCheckTime?.toIso8601String(),
          'license_valid': licenseValid,
          'clock_tampered': clockTampered,
          'sessions_valid': sessionsValid,
          'check_result': checkResult,
          'consecutive_failures': _consecutiveFailures,
          'active_users': sessionStats['activeUsers'],
          'max_users': sessionStats['maxUsers'],
        },
      );
    } catch (e) {
      _consecutiveFailures++;
      debugPrint('❌ Integrity check error: $e');

      final db = await DatabaseSingleton.getInstance();

      await AuditService.log(
        db: db,
        action: AuditAction.read,
        tableName: 'system_integrity',
        details: {
          'check_time': DateTime.now().toIso8601String(),
          'error': e.toString(),
          'consecutive_failures': _consecutiveFailures,
        },
      );
    }
  }

  /// Check license validity
  static Future<bool> _checkLicenseValidity() async {
    try {
      final db = await DatabaseSingleton.getInstance();

      final licenseManager = LicenseManager();
      final isValid = await licenseManager.isLicenseValid();

      if (!isValid) {
        debugPrint('❌ License validation failed');

        // Get license details for logging
        final currentLicense = await licenseManager.getCurrentLicense();
        if (currentLicense != null) {
          await AuditService.log(
            db: db,
            action: AuditAction.licenseDeactivate,
            tableName: 'license',
            details: {
              'reason': 'integrity_check_failed',
              'license_type': currentLicense.licenseType,
              'is_expired': currentLicense.isExpired,
              'days_remaining': currentLicense.daysRemaining,
            },
          );
        }
      }

      return isValid;
    } catch (e) {
      debugPrint('Error checking license validity: $e');
      return false;
    }
  }

  /// Handle failed integrity check
  static Future<void> _handleFailedCheck(
    bool licenseValid,
    bool clockTampered,
    bool sessionsValid,
    Map<String, dynamic> sessionStats,
  ) async {
    final db = await DatabaseSingleton.getInstance();

    debugPrint('🚨 INTEGRITY BREACH DETECTED!');
    debugPrint('  License Valid: $licenseValid');
    debugPrint('  Clock Tampered: $clockTampered');
    debugPrint('  Sessions Valid: $sessionsValid');
    debugPrint(
      '  Active Users: ${sessionStats['activeUsers']}/${sessionStats['maxUsers']}',
    );

    // Log security incident
    await AuditService.log(
      db: db,
      action: AuditAction.licenseDeactivate,
      tableName: 'security_incident',
      details: {
        'incident_type': 'integrity_check_failed',
        'license_valid': licenseValid,
        'clock_tampered': clockTampered,
        'sessions_valid': sessionsValid,
        'consecutive_failures': _consecutiveFailures,
        'session_stats': sessionStats,
      },
    );

    // If consecutive failures exceed threshold, take action
    if (_consecutiveFailures >= 3) {
      await _handleCriticalFailure();
    }
  }

  /// Handle critical integrity failure
  static Future<void> _handleCriticalFailure() async {
    final db = await DatabaseSingleton.getInstance();

    debugPrint('🚨 CRITICAL INTEGRITY FAILURE - Taking protective action');

    await AuditService.log(
      db: db,
      action: AuditAction.licenseDeactivate,
      tableName: 'security_incident',
      details: {
        'incident_type': 'critical_integrity_failure',
        'action_taken': 'protective_shutdown',
        'consecutive_failures': _consecutiveFailures,
      },
    );

    // Deactivate license to protect system
    final licenseManager = LicenseManager();
    await licenseManager.deactivateLicense();

    // Stop all services
    UserSessionService.stopSessionCleanup();
    stop();

    debugPrint('🛑 System protection activated - license deactivated');
  }

  /// Get current integrity status
  static Map<String, dynamic> getStatus() {
    return {
      'isRunning': _isRunning,
      'lastCheckResult': _lastCheckResult,
      'lastCheckTime': _lastCheckTime?.toIso8601String(),
      'consecutiveFailures': _consecutiveFailures,
      'status': _getStatusText(),
    };
  }

  /// Get human-readable status text
  static String _getStatusText() {
    if (!_isRunning) return 'Stopped';
    if (_consecutiveFailures >= 3) return 'Critical Failure';
    if (_consecutiveFailures > 0) return 'Warning';
    if (_lastCheckResult) return 'Healthy';
    return 'Failed';
  }

  /// Force immediate integrity check
  static Future<void> checkNow() async {
    debugPrint('🔍 Forcing immediate integrity check...');
    await _performCheck();
  }

  /// Reset failure counter (admin function)
  static void resetFailureCounter() {
    _consecutiveFailures = 0;
    _lastCheckResult = true;
    debugPrint('🔄 Integrity failure counter reset');
  }

  /// Get detailed integrity report
  static Future<Map<String, dynamic>> getDetailedReport() async {
    try {
      final licenseManager = LicenseManager();
      final currentLicense = await licenseManager.getCurrentLicense();
      final sessionStats = await UserSessionService.getSessionStats();

      return {
        'integrity_status': getStatus(),
        'license_status': {
          'is_valid': await licenseManager.isLicenseValid(),
          'current_license': currentLicense?.toJson(),
        },
        'session_status': sessionStats,
        'last_checks': {
          'last_check_time': _lastCheckTime?.toIso8601String(),
          'last_check_result': _lastCheckResult,
          'consecutive_failures': _consecutiveFailures,
        },
        'system_health': {
          'is_running': _isRunning,
          'status_text': _getStatusText(),
          'needs_attention': _consecutiveFailures > 0 || !_lastCheckResult,
        },
      };
    } catch (e) {
      return {'error': e.toString(), 'integrity_status': getStatus()};
    }
  }

  /// Validate system before critical operations
  static Future<bool> validateForCriticalOperation() async {
    try {
      // Quick check before allowing critical operations
      final licenseValid = await _checkLicenseValidity();
      final clockTampered = await AntiTamperService.detectClockTampering();

      if (!licenseValid || clockTampered) {
        debugPrint(
          '🚨 System integrity compromised - blocking critical operation',
        );
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error validating for critical operation: $e');
      return false;
    }
  }
}
