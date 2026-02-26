import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'local_backup_service.dart';
import '../core/utils/logger.dart';

class ManualBackupService {
  /// Export backup to user-selected location
  static Future<String?> exportToUserLocation() async {
    if (kIsWeb) {
      throw Exception('Manual backup export not supported on web platform');
    }
    try {
      // Create backup first
      final backupPath = await LocalBackupService.createManualBackup(
        'user_export',
      );

      // Let user choose save location
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نسخة احتياطية',
        fileName: path.basename(backupPath),
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null) {
        // Copy backup to user-selected location
        final backupFile = File(backupPath);
        final targetFile = File(result);
        await backupFile.copy(result);

        AppLogger.i('✅ Backup exported to: $result');
        return result;
      } else {
        // User cancelled
        await File(backupPath).delete(); // Clean up temp backup
        return null;
      }
    } catch (e) {
      AppLogger.e('Export backup error', e);
      return null;
    }
  }

  /// Import backup from user-selected location
  static Future<bool> importFromUserLocation() async {
    try {
      // Let user choose backup file
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر نسخة احتياطية للاستعادة',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.single.path != null) {
        final backupPath = result.files.single.path!;

        // Restore from selected backup
        return await LocalBackupService.restoreFromBackup(backupPath);
      } else {
        return false; // User cancelled
      }
    } catch (e) {
      AppLogger.e('Import backup error', e);
      return false;
    }
  }

  /// Export to USB drive (if available)
  static Future<String?> exportToUSB() async {
    try {
      // Create backup first
      final backupPath = await LocalBackupService.createManualBackup(
        'usb_export',
      );

      // Try to detect USB drives (platform-specific)
      final usbPath = await _getUSBDrivePath();

      if (usbPath != null) {
        final backupFile = File(backupPath);
        final targetPath = path.join(
          usbPath,
          'POS_Backup_${DateTime.now().millisecondsSinceEpoch}.zip',
        );
        final targetFile = File(targetPath);

        await backupFile.copy(targetPath);

        AppLogger.i('✅ Backup exported to USB: $targetPath');
        return targetPath;
      } else {
        // Fallback to user selection
        return await exportToUserLocation();
      }
    } catch (e) {
      AppLogger.e('USB export error', e);
      return null;
    }
  }

  /// Get USB drive path (platform-specific implementation)
  static Future<String?> _getUSBDrivePath() async {
    try {
      if (Platform.isWindows) {
        // On Windows, check for removable drives
        final drives = await _getWindowsDrives();
        for (final drive in drives) {
          if (drive['type'] == 'removable') {
            return drive['path'] as String?;
          }
        }
      } else if (Platform.isMacOS) {
        // On macOS, check /Volumes for external drives
        final volumesDir = Directory('/Volumes');
        if (await volumesDir.exists()) {
          final volumes = await volumesDir.list().toList();
          for (final volume in volumes) {
            if (volume is Directory && !volume.path.endsWith('/Macintosh HD')) {
              return volume.path;
            }
          }
        }
      } else if (Platform.isLinux) {
        // On Linux, check /media for mounted drives
        final mediaDir = Directory('/media');
        if (await mediaDir.exists()) {
          final media = await mediaDir.list().toList();
          for (final item in media) {
            if (item is Directory) {
              return item.path;
            }
          }
        }
      }

      return null; // No USB drive found
    } catch (e) {
      AppLogger.e('Error detecting USB drive', e);
      return null;
    }
  }

  /// Get Windows drives information
  static Future<List<Map<String, dynamic>>> _getWindowsDrives() async {
    // This is a simplified implementation
    // In a real app, you'd use Windows-specific APIs
    return [
      {'path': 'C:\\', 'type': 'fixed'},
      {'path': 'D:\\', 'type': 'removable'}, // Example USB drive
    ];
  }

  /// Create backup with custom name and notes
  static Future<String> createCustomBackup({
    required String name,
    required String notes,
  }) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupName = 'custom_${name}_$timestamp';

      // Create backup
      final backupPath = await LocalBackupService.createBackup(backupName);

      // Create notes file
      final notesFile = File(
        path.join(path.dirname(backupPath), 'notes_$timestamp.txt'),
      );
      await notesFile.writeAsString('''
Backup Name: $name
Created: ${DateTime.now().toIso8601String()}
Notes: $notes
Version: 2.0.0
''');

      AppLogger.i('✅ Custom backup created: $backupPath');
      return backupPath;
    } catch (e) {
      AppLogger.e('Custom backup error', e);
      rethrow;
    }
  }

  /// Verify backup integrity
  static Future<bool> verifyBackupIntegrity(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        return false;
      }

      // For ZIP files, check if they can be opened
      // This is a simplified check - in real implementation you'd verify the archive structure
      final fileSize = await backupFile.length();
      return fileSize > 1024; // At least 1KB
    } catch (e) {
      AppLogger.e('Backup verification error', e);
      return false;
    }
  }

  /// Get backup statistics
  static Future<Map<String, dynamic>> getBackupStatistics() async {
    try {
      final backups = await LocalBackupService.getAvailableBackups();

      final totalSize = backups.fold<int>(
        0,
        (sum, backup) => sum + backup.size,
      );
      final oldestBackup = backups.isNotEmpty
          ? backups.last.created
          : DateTime.now();
      final newestBackup = backups.isNotEmpty
          ? backups.first.created
          : DateTime.now();

      return {
        'total_backups': backups.length,
        'total_size': totalSize,
        'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(1),
        'oldest_backup': oldestBackup.toIso8601String(),
        'newest_backup': newestBackup.toIso8601String(),
        'backup_types': {
          'manual': backups.where((b) => b.type == 'manual').length,
          'auto': backups.where((b) => b.type == 'auto').length,
        },
      };
    } catch (e) {
      AppLogger.e('Error getting backup statistics', e);
      return {};
    }
  }
}
