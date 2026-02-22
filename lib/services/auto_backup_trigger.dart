import 'dart:async';
import 'package:flutter/foundation.dart';
import 'local_backup_service.dart';
import 'audit_service.dart';
import '../core/database/database_singleton.dart';

class AutoBackupTrigger {
  static Timer? _dailyBackupTimer;
  static Timer? _cleanupTimer;
  static int _transactionCount = 0;
  static const int _transactionThreshold = 100;
  static const int _retentionDays = 7;
  static bool _isRunning = false;

  /// Start automatic backup system
  static void start() {
    if (_isRunning) {
      debugPrint('Auto backup trigger already running');
      return;
    }

    _isRunning = true;
    debugPrint('🔄 Starting automatic backup system');

    // Schedule daily backup at 11 PM
    _scheduleDailyBackup();

    debugPrint('✅ Auto backup system started');
    debugPrint('  - Daily backup: 11:00 PM');
    debugPrint(
      '  - Transaction backup: Every $_transactionThreshold transactions',
    );
    debugPrint('  - Retention: $_retentionDays days');
  }

  /// Stop automatic backup system
  static void stop() {
    _isRunning = false;
    _dailyBackupTimer?.cancel();
    _cleanupTimer?.cancel();
    _dailyBackupTimer = null;
    _cleanupTimer = null;
    debugPrint('🛑 Auto backup system stopped');
  }

  /// Increment transaction count
  static void incrementTransactionCount() async {
    if (!_isRunning) return;

    _transactionCount++;

    if (_transactionCount >= _transactionThreshold) {
      debugPrint(
        '🔄 Transaction threshold reached ($_transactionThreshold) - triggering backup',
      );
      await _performTransactionBackup();
      _transactionCount = 0;
    }
  }

  /// Schedule daily backup at 11 PM
  static void _scheduleDailyBackup() {
    _dailyBackupTimer?.cancel();

    final now = DateTime.now();
    var scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      23, // 11 PM
      0, // 0 minutes
      0, // 0 seconds
    );

    // If 11 PM has passed today, schedule for tomorrow
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    final initialDelay = scheduledTime.difference(now);
    debugPrint(
      '📅 Next daily backup scheduled for: $scheduledTime (in ${initialDelay.inHours} hours)',
    );

    _dailyBackupTimer = Timer(initialDelay, () {
      _performDailyBackup();
      // Schedule for next day
      _scheduleDailyBackup();
    });
  }

  /// Perform daily backup
  static Future<void> _performDailyBackup() async {
    try {
      final db = await DatabaseSingleton.getInstance();

      debugPrint('🔄 Performing daily automatic backup...');

      final backupPath = await LocalBackupService.createAutoBackup(
        isTransactionBased: false,
      );

      debugPrint('✅ Daily backup completed: $backupPath');

      await AuditService.log(
        db: db,
        action: AuditAction.create,
        tableName: 'backup',
        details: {
          'backup_type': 'daily_automatic',
          'backup_path': backupPath,
          'transaction_count': _transactionCount,
        },
      );
    } catch (e) {
      debugPrint('❌ Error in daily backup: $e');

      try {
        final db = await DatabaseSingleton.getInstance();
        await AuditService.log(
          db: db,
          action: AuditAction.create,
          tableName: 'backup',
          details: {
            'backup_type': 'daily_automatic',
            'status': 'failed',
            'error': e.toString(),
          },
        );
      } catch (auditError) {
        debugPrint('❌ Error logging failed backup: $auditError');
      }
    }
  }

  /// Perform transaction-based backup
  static Future<void> _performTransactionBackup() async {
    try {
      final db = await DatabaseSingleton.getInstance();

      debugPrint('🔄 Performing transaction-based backup...');

      final backupPath = await LocalBackupService.createAutoBackup(
        isTransactionBased: true,
      );

      debugPrint('✅ Transaction backup completed: $backupPath');

      await AuditService.log(
        db: db,
        action: AuditAction.create,
        tableName: 'backup',
        details: {
          'backup_type': 'transaction_automatic',
          'backup_path': backupPath,
          'transaction_count': _transactionCount,
        },
      );
    } catch (e) {
      debugPrint('❌ Error in transaction backup: $e');
    }
  }

  /// Get backup statistics
  static Future<Map<String, dynamic>> getBackupStats() async {
    try {
      final backups = await LocalBackupService.getAvailableBackups();
      final totalSize = backups.fold<int>(
        0,
        (sum, backup) => sum + backup.size,
      );

      // Count automatic vs manual backups
      int automaticCount = 0;
      int manualCount = 0;

      for (final backup in backups) {
        if (backup.type == 'auto') {
          automaticCount++;
        } else {
          manualCount++;
        }
      }

      return {
        'total_backups': backups.length,
        'automatic_backups': automaticCount,
        'manual_backups': manualCount,
        'total_size_mb': (totalSize / 1024 / 1024).toStringAsFixed(2),
        'transaction_count': _transactionCount,
        'transaction_threshold': _transactionThreshold,
        'is_running': _isRunning,
        'retention_days': _retentionDays,
        'oldest_backup': backups.isNotEmpty
            ? backups.last.created.toIso8601String()
            : null,
        'newest_backup': backups.isNotEmpty
            ? backups.first.created.toIso8601String()
            : null,
      };
    } catch (e) {
      debugPrint('Error getting backup stats: $e');
      return {'error': e.toString(), 'is_running': _isRunning};
    }
  }

  /// Force immediate backup
  static Future<String?> forceBackup({String? description}) async {
    try {
      final db = await DatabaseSingleton.getInstance();

      debugPrint('🔄 Forcing immediate backup...');

      final backupName =
          description ??
          'manual_forced_${DateTime.now().millisecondsSinceEpoch}';
      final backupPath = await LocalBackupService.createManualBackup(
        backupName,
      );

      debugPrint('✅ Forced backup completed: $backupPath');

      await AuditService.log(
        db: db,
        action: AuditAction.create,
        tableName: 'backup',
        details: {
          'backup_type': 'manual_forced',
          'backup_path': backupPath,
          'description': description,
        },
      );

      return backupPath;
    } catch (e) {
      debugPrint('❌ Error in forced backup: $e');
      return null;
    }
  }

  /// Reset transaction counter
  static void resetTransactionCounter() {
    _transactionCount = 0;
    debugPrint('🔄 Transaction counter reset');
  }

  /// Get current status
  static Map<String, dynamic> getStatus() {
    return {
      'is_running': _isRunning,
      'transaction_count': _transactionCount,
      'transaction_threshold': _transactionThreshold,
      'retention_days': _retentionDays,
      'next_daily_backup': _getNextDailyBackupTime(),
    };
  }

  /// Get next daily backup time
  static String? _getNextDailyBackupTime() {
    if (_dailyBackupTimer == null) return null;

    final now = DateTime.now();
    final scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      23, // 11 PM
      0, // 0 minutes
      0, // 0 seconds
    );

    if (scheduledTime.isBefore(now)) {
      return scheduledTime.add(const Duration(days: 1)).toIso8601String();
    } else {
      return scheduledTime.toIso8601String();
    }
  }
}
