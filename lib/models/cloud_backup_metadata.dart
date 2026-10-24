import 'package:intl/intl.dart';

class CloudBackupMetadata {
  final String id;
  final String name;
  final int size;
  final DateTime createdTime;
  final String checksum;
  final String appVersion;
  final bool isEncrypted;
  final bool isAutoBackup;
  final String? driveLink;

  CloudBackupMetadata({
    required this.id,
    required this.name,
    required this.size,
    required this.createdTime,
    required this.checksum,
    this.appVersion = '2.3.0',
    this.isEncrypted = true,
    this.isAutoBackup = false,
    this.driveLink,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(2)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedDate {
    try {
      final formatter = DateFormat('yyyy-MM-dd HH:mm:ss', 'ar_EG');
      return formatter.format(createdTime);
    } catch (_) {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(createdTime);
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'size': size,
      'created_time': createdTime.toIso8601String(),
      'checksum': checksum,
      'app_version': appVersion,
      'is_encrypted': isEncrypted,
      'is_auto_backup': isAutoBackup,
      'drive_link': driveLink,
    };
  }

  factory CloudBackupMetadata.fromJson(Map<String, dynamic> json) {
    return CloudBackupMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      size: json['size'] is int
          ? json['size'] as int
          : int.tryParse(json['size'].toString()) ?? 0,
      createdTime: DateTime.parse(json['created_time'] as String),
      checksum: json['checksum'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? '2.3.0',
      isEncrypted: json['is_encrypted'] as bool? ?? true,
      isAutoBackup: json['is_auto_backup'] as bool? ?? false,
      driveLink: json['drive_link'] as String?,
    );
  }

  factory CloudBackupMetadata.fromDriveProperties({
    required String fileId,
    required String fileName,
    required int fileSize,
    required DateTime createdTime,
    Map<String, String?>? appProperties,
    String? webViewLink,
  }) {
    final isAuto = appProperties?['isAutoBackup'] == 'true';
    final checksum = appProperties?['checksum'] ?? '';
    final version = appProperties?['appVersion'] ?? '2.3.0';

    return CloudBackupMetadata(
      id: fileId,
      name: fileName,
      size: fileSize,
      createdTime: createdTime,
      checksum: checksum,
      appVersion: version,
      isEncrypted: true,
      isAutoBackup: isAuto,
      driveLink: webViewLink,
    );
  }
}
