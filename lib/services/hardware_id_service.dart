import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/utils/logger.dart';

/// Generates a stable hardware fingerprint for the device.
/// Uses device_info_plus signals combined into a stable identifier.
class HardwareIdService {
  static String? _cachedId;

  /// Get the stable hardware fingerprint (SHA-256 hash).
  /// Result is cached in memory for the app session.
  static Future<String> getHardwareId() async {
    if (_cachedId != null) return _cachedId!;

    try {
      final raw = await _collectHardwareSignals();
      final hash = sha256.convert(utf8.encode(raw)).toString();
      _cachedId = hash;
      AppLogger.i('Hardware ID generated: $hash');
      return hash;
    } catch (e) {
      AppLogger.e('Failed to generate hardware ID', e);
      // Fallback: use whatever we can get
      return _fallbackHardwareId();
    }
  }

  /// Collect raw hardware signals (not hashed yet).
  static Future<String> _collectHardwareSignals() async {
    final parts = <String>[];

    // Device info signals
    if (!kIsWeb && Platform.isWindows) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final win = await deviceInfo.windowsInfo;
        parts.add('name:${win.computerName}');
        parts.add('cores:${win.numberOfCores}');
        parts.add('ram:${win.systemMemoryInMegabytes}');
      } catch (e) {
        AppLogger.w('DeviceInfo unavailable: $e');
      }
    } else if (!kIsWeb && Platform.isLinux) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final linux = await deviceInfo.linuxInfo;
        parts.add('machine:${linux.machineId}');
        parts.add('name:${linux.name}');
      } catch (e) {
        AppLogger.w('DeviceInfo unavailable: $e');
      }
    } else if (!kIsWeb && Platform.isMacOS) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final mac = await deviceInfo.macOsInfo;
        parts.add('guid:${mac.systemGUID}');
        parts.add('model:${mac.model}');
      } catch (e) {
        AppLogger.w('DeviceInfo unavailable: $e');
      }
    } else {
      // Android / iOS / web fallback signals
      try {
        final deviceInfo = DeviceInfoPlugin();
        final android = await deviceInfo.androidInfo;
        parts.add('androidId:${android.id}');
        parts.add('board:${android.board}');
        parts.add('model:${android.model}');
      } catch (e) {
        AppLogger.w('AndroidInfo unavailable: $e');
      }
      try {
        final deviceInfo = DeviceInfoPlugin();
        final ios = await deviceInfo.iosInfo;
        parts.add('identifier:${ios.identifierForVendor}');
        parts.add('model:${ios.utsname.machine}');
      } catch (e) {
        AppLogger.w('IosInfo unavailable: $e');
      }
    }

    if (parts.isEmpty) {
      throw Exception('No hardware signals available');
    }

    return parts.join('|');
  }

  /// Fallback if nothing else works.
  static Future<String> _fallbackHardwareId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isWindows) {
        final win = await deviceInfo.windowsInfo;
        final raw = '${win.computerName}_${win.numberOfCores}_${win.systemMemoryInMegabytes}';
        final hash = sha256.convert(utf8.encode(raw)).toString();
        _cachedId = hash;
        return hash;
      }
    } catch (_) {}
    return 'fallback_unknown';
  }

  /// Verify that the current device matches a previously saved hardware ID.
  static Future<bool> isSameDevice(String savedHardwareId) async {
    final current = await getHardwareId();
    return current == savedHardwareId;
  }
}
