import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../core/utils/logger.dart';

class UpdateService {
  static const String updateCheckUrl =
      'https://api.mo2-systems.com/pos/updates/latest.json';
  final Dio _dio = Dio();

  /// Check if update is available
  Future<UpdateInfo?> checkForUpdate() async {
    if (kIsWeb) {
      return null; // Updates not available on web
    }
    try {
      AppLogger.i('Checking for updates...');

      // Get current version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.parse(packageInfo.buildNumber);

      AppLogger.i('Current version: $currentVersion (build $currentBuild)');

      // Fetch latest version info
      final response = await _dio.get(
        updateCheckUrl,
        options: Options(
          receiveTimeout: Duration(seconds: 10),
          sendTimeout: Duration(seconds: 10),
        ),
      );

      if (response.statusCode != 200) {
        AppLogger.e('Failed to check for updates: ${response.statusCode}');
        return null;
      }

      final data = response.data;
      final latestVersion = data['version'] as String;
      final latestBuild = data['build_number'] as int;

      AppLogger.i('Latest version: $latestVersion (build $latestBuild)');

      // Compare versions
      if (latestBuild > currentBuild) {
        AppLogger.i('✅ Update available!');
        return UpdateInfo.fromJson(data);
      } else {
        AppLogger.i('ℹ️ Already on latest version');
        return null;
      }
    } on DioException catch (e) {
      // No internet or server unreachable
      AppLogger.w('Update check failed (no internet): ${e.message}');
      return null;
    } catch (e) {
      AppLogger.e('Update check error', e);
      return null;
    }
  }

  /// Download update file
  Future<File?> downloadUpdate(
    UpdateInfo update,
    Function(double progress) onProgress,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final filename = update.downloadUrl.split('/').last;
      final savePath = '${tempDir.path}/$filename';

      print('Downloading update to: $savePath');

      await _dio.download(
        update.downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            onProgress(progress);
            AppLogger.d(
              'Download progress: ${(progress * 100).toStringAsFixed(1)}%',
            );
          }
        },
      );

      final file = File(savePath);

      // Verify file size
      final fileSize = await file.length();
      if (fileSize != update.downloadSize) {
        AppLogger.e(
          '❌ Size mismatch: expected ${update.downloadSize}, got $fileSize',
        );
        await file.delete();
        throw Exception('Downloaded file size mismatch');
      }

      // Verify checksum
      if (update.checksum != null) {
        final isValid = await _verifyChecksum(file, update.checksum!);
        if (!isValid) {
          AppLogger.e('❌ Checksum verification failed');
          await file.delete();
          throw Exception('Checksum verification failed');
        }
      }

      AppLogger.i('✅ Download and verification successful');
      return file;
    } catch (e) {
      AppLogger.e('Download error', e);
      return null;
    }
  }

  /// Verify file checksum
  Future<bool> _verifyChecksum(File file, String expectedChecksum) async {
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      final actualChecksum = 'sha256:$digest';

      return actualChecksum == expectedChecksum;
    } catch (e) {
      AppLogger.e('Checksum verification error', e);
      return false;
    }
  }

  /// Install update
  Future<void> installUpdate(File updateFile) async {
    try {
      if (Platform.isWindows) {
        // Run installer
        final result = await Process.run(updateFile.path, [
          '/SILENT',
          '/CLOSEAPPLICATIONS',
        ]);

        if (result.exitCode == 0) {
          AppLogger.i('✅ Update installed successfully');
          // Exit current app so installer can replace files
          exit(0);
        } else {
          throw Exception('Installer failed with code ${result.exitCode}');
        }
      } else if (Platform.isMacOS) {
        // Open DMG
        await Process.run('open', [updateFile.path]);
        exit(0);
      } else if (Platform.isLinux) {
        // Install DEB
        await Process.run('sudo', ['dpkg', '-i', updateFile.path]);
        exit(0);
      }
    } catch (e) {
      AppLogger.e('Installation error', e);
      rethrow;
    }
  }
}

/// Update information model
class UpdateInfo {
  final String version;
  final int buildNumber;
  final DateTime releaseDate;
  final bool isCritical;
  final String minSupportedVersion;
  final List<String> changelog;
  final String downloadUrl;
  final int downloadSize;
  final String? checksum;
  final List<String> features;
  final String? releaseNotesUrl;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseDate,
    required this.isCritical,
    required this.minSupportedVersion,
    required this.changelog,
    required this.downloadUrl,
    required this.downloadSize,
    this.checksum,
    required this.features,
    this.releaseNotesUrl,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final downloads = json['downloads'] as Map<String, dynamic>;
    Map<String, dynamic> platformDownload;

    if (Platform.isWindows) {
      platformDownload = downloads['windows'] as Map<String, dynamic>;
    } else if (Platform.isMacOS) {
      platformDownload = downloads['macos'] as Map<String, dynamic>;
    } else {
      platformDownload = downloads['linux'] as Map<String, dynamic>;
    }

    return UpdateInfo(
      version: json['version'] as String,
      buildNumber: json['build_number'] as int,
      releaseDate: DateTime.parse(json['release_date'] as String),
      isCritical: json['is_critical'] as bool? ?? false,
      minSupportedVersion: json['min_supported_version'] as String,
      changelog: List<String>.from(json['changelog']['ar'] as List),
      downloadUrl: platformDownload['url'] as String,
      downloadSize: platformDownload['size'] as int,
      checksum: platformDownload['checksum'] as String?,
      features: List<String>.from(json['features'] ?? []),
      releaseNotesUrl: json['release_notes_url'] as String?,
    );
  }

  String get sizeString {
    final sizeInMB = downloadSize / (1024 * 1024);
    return '${sizeInMB.toStringAsFixed(1)} MB';
  }
}
