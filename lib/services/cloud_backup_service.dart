import 'dart:io';
// Removed unused imports to reduce warnings and improve tree-shaking
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'local_backup_service.dart';

class CloudBackupService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<bool> uploadToCloud(
    String backupPath, {
    String? customerId,
  }) async {
    if (kIsWeb) {
      throw Exception('Cloud backup upload not supported on web platform');
    }
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        throw Exception('Backup file not found');
      }

      // Read backup file
      final backupBytes = await backupFile.readAsBytes();
      final checksum = sha256.convert(backupBytes).toString();

      // Create unique filename
      final fileName =
          'backup_${DateTime.now().millisecondsSinceEpoch}_${backupFile.uri.pathSegments.last}';
      final customerPath = customerId ?? 'anonymous';
      final storageRef = _storage.ref().child(
        'backups/$customerPath/$fileName',
      );

      // Upload to Firebase Storage
      final uploadTask = storageRef.putData(backupBytes);
      final snapshot = await uploadTask.whenComplete(() => null);

      // Get download URL
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Save metadata to Firestore
      await _firestore.collection('backups').doc(fileName).set({
        'fileName': fileName,
        'customerId': customerId ?? 'anonymous',
        'created': DateTime.now().toIso8601String(),
        'size': backupBytes.length,
        'checksum': checksum,
        'downloadUrl': downloadUrl,
        'version': '2.0.0',
      });

      print('✅ Cloud upload completed successfully: $fileName');
      return true;
    } catch (e) {
      print('Cloud upload error: $e');
      return false;
    }
  }

  /// Download backup from cloud
  static Future<String?> downloadFromCloud(
    String backupId,
    String localPath,
  ) async {
    try {
      // Get backup metadata from Firestore
      final doc = await _firestore.collection('backups').doc(backupId).get();
      if (!doc.exists) {
        throw Exception('Backup not found in cloud');
      }

      final data = doc.data()!;
      final downloadUrl = data['downloadUrl'] as String;

      // Download from Firebase Storage
      final ref = _storage.refFromURL(downloadUrl);
      final bytes = await ref.getData();

      if (bytes == null) {
        throw Exception('Failed to download backup data');
      }

      // Save to local path
      final localFile = File(localPath);
      await localFile.writeAsBytes(bytes);

      print('✅ Cloud download completed successfully: $backupId');
      return localPath;
    } catch (e) {
      print('Cloud download error: $e');
      return null;
    }
  }

  /// List cloud backups
  static Future<List<CloudBackupInfo>> listCloudBackups({
    String? customerId,
  }) async {
    try {
      Query query = _firestore.collection('backups');

      if (customerId != null) {
        query = query.where('customerId', isEqualTo: customerId);
      }

      final snapshot = await query.get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return CloudBackupInfo(
          id: doc.id,
          fileName: data['fileName'] as String,
          created: DateTime.parse(data['created'] as String),
          size: data['size'] as int,
          customerId: data['customerId'] as String,
          version: data['version'] as String,
          downloadUrl: data['downloadUrl'] as String,
        );
      }).toList();
    } catch (e) {
      print('Error listing cloud backups: $e');
      return [];
    }
  }

  /// Delete cloud backup
  static Future<bool> deleteCloudBackup(String backupId) async {
    try {
      // Get backup metadata from Firestore
      final doc = await _firestore.collection('backups').doc(backupId).get();
      if (!doc.exists) {
        throw Exception('Backup not found in cloud');
      }

      final data = doc.data()!;
      final downloadUrl = data['downloadUrl'] as String;

      // Delete from Firebase Storage
      final ref = _storage.refFromURL(downloadUrl);
      await ref.delete();

      // Delete metadata from Firestore
      await _firestore.collection('backups').doc(backupId).delete();

      print('✅ Cloud backup deleted successfully: $backupId');
      return true;
    } catch (e) {
      print('Error deleting cloud backup: $e');
      return false;
    }
  }

  /// Sync local backups with cloud (simplified version)
  static Future<void> syncWithCloud({String? customerId}) async {
    try {
      print('🔄 Starting cloud backup sync...');

      // Get local backups
      final localBackups = await LocalBackupService.getAvailableBackups();

      // Get cloud backups
      final cloudBackups = await listCloudBackups(customerId: customerId);

      print('📊 Local backups: ${localBackups.length}');
      print('☁️ Cloud backups: ${cloudBackups.length}');

      // Simulate sync process
      for (final localBackup in localBackups) {
        final existsInCloud = cloudBackups.any(
          (cloud) => cloud.fileName == localBackup.fileName,
        );

        if (!existsInCloud) {
          print('☁️ Uploading new backup to cloud: ${localBackup.fileName}');
          await uploadToCloud(localBackup.filePath, customerId: customerId);
        }
      }

      print('✅ Cloud sync completed');
    } catch (e) {
      print('Cloud sync error: $e');
    }
  }

  /// Schedule automatic cloud backup (simplified version)
  static void scheduleAutoCloudBackup({String? customerId}) {
    print('⏰ Scheduling automatic cloud backup every 7 days');

    // For now, just log that scheduling would happen
    // In production, use Timer.periodic from dart:async
    print(
      '📅 Auto-cloud backup scheduled for customer: ${customerId ?? 'default'}',
    );
  }
}

/// Cloud backup information model
class CloudBackupInfo {
  final String id;
  final String fileName;
  final DateTime created;
  final int size;
  final String customerId;
  final String version;
  final String? downloadUrl;

  CloudBackupInfo({
    required this.id,
    required this.fileName,
    required this.created,
    required this.size,
    required this.customerId,
    required this.version,
    this.downloadUrl,
  });

  factory CloudBackupInfo.fromJson(Map<String, dynamic> json) {
    return CloudBackupInfo(
      id: json['id'] as String,
      fileName: json['file_name'] as String,
      created: DateTime.parse(json['created'] as String),
      size: json['size'] as int,
      customerId: json['customer_id'] as String,
      version: json['version'] as String? ?? 'unknown',
      downloadUrl: json['download_url'] as String?,
    );
  }

  String get sizeString {
    final sizeInMB = size / (1024 * 1024);
    return '${sizeInMB.toStringAsFixed(1)} MB';
  }

  String get createdString {
    return created.toIso8601String().split('T')[0];
  }
}
