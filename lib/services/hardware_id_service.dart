import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/utils/logger.dart';

/// Individual hardware components for comparison.
/// Used for tolerant matching instead of full hash comparison.
class HardwareComponents {
  final String computerName;
  final int numberOfCores;
  final String? deviceId; // Stable Windows machine ID — replaces volatile RAM

  HardwareComponents({
    required this.computerName,
    required this.numberOfCores,
    this.deviceId,
  });

  /// Serialize to string for hashing.
  /// RAM is excluded for stability; Windows also adds the stable `deviceId`.
  String toHashString() {
    final base = 'name:$computerName|cores:$numberOfCores';
    if (deviceId == null || deviceId!.isEmpty) return base;
    return '$base|deviceId:$deviceId';
  }

  /// Serialize to JSON for storage.
  Map<String, dynamic> toJson() {
    return {
      'computerName': computerName,
      'numberOfCores': numberOfCores,
      if (deviceId != null) 'deviceId': deviceId,
    };
  }

  factory HardwareComponents.fromJson(Map<String, dynamic> json) {
    return HardwareComponents(
      computerName: json['computerName'] ?? '',
      numberOfCores: json['numberOfCores'] ?? 0,
      deviceId: json['deviceId'] as String?,
    );
  }

  /// Count matching components with another set.
  /// Returns number of matching fields.
  int countMatches(HardwareComponents other) {
    int matches = 0;
    if (computerName == other.computerName) matches++;
    if (numberOfCores == other.numberOfCores) matches++;
    // RAM is NOT counted for matching - it's too volatile; deviceId is stable
    if (deviceId != null &&
        deviceId!.isNotEmpty &&
        deviceId == other.deviceId) {
      matches++;
    }
    return matches;
  }
}

/// Generates a stable hardware fingerprint for the device.
/// Uses device_info_plus signals combined into a stable identifier.
/// 
/// RAM removed from fingerprint (Windows) because it changes after 
/// Windows Updates, driver reinstalls, or BIOS memory remaps,
/// causing false "activated on another device" lockouts.
/// The stable Windows `deviceId` (machine GUID) replaces it.
/// See: https://github.com/momenmohammed312-dev/ERP_App/issues/[hardware-fingerprint-fix]
class HardwareIdService {
  static String? _cachedId;
  static HardwareComponents? _cachedComponents;

  /// Get the stable hardware fingerprint (SHA-256 hash).
  /// Result is cached in memory for the app session.
  static Future<String> getHardwareId() async {
    if (_cachedId != null) return _cachedId!;

    try {
      final components = await _collectHardwareComponents();
      final raw = components.toHashString();
      final hash = sha256.convert(utf8.encode(raw)).toString();
      _cachedId = hash;
      _cachedComponents = components;
      AppLogger.i('Hardware ID generated: $hash (components: ${components.toHashString()})');
      return hash;
    } catch (e) {
      AppLogger.e('Failed to generate hardware ID', e);
      // Fallback: use whatever we can get
      return _fallbackHardwareId();
    }
  }

  /// Get individual hardware components for tolerant comparison.
  /// Result is cached in memory for the app session.
  static Future<HardwareComponents> getHardwareComponents() async {
    if (_cachedComponents != null) return _cachedComponents!;

    try {
      final components = await _collectHardwareComponents();
      _cachedComponents = components;
      return components;
    } catch (e) {
      AppLogger.e('Failed to collect hardware components', e);
      // Return empty components as fallback
      return HardwareComponents(computerName: '', numberOfCores: 0);
    }
  }

  /// Collect hardware components for comparison.
  static Future<HardwareComponents> _collectHardwareComponents() async {
    // Device info signals
    if (!kIsWeb && Platform.isWindows) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final win = await deviceInfo.windowsInfo;
        return HardwareComponents(
          computerName: win.computerName,
          numberOfCores: win.numberOfCores,
          deviceId: win.deviceId,
        );
      } catch (e) {
        AppLogger.w('DeviceInfo unavailable: $e');
      }
    } else if (!kIsWeb && Platform.isLinux) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final linux = await deviceInfo.linuxInfo;
        // For Linux, use machineId as computerName, no cores available
        return HardwareComponents(
          computerName: linux.machineId ?? '',
          numberOfCores: 0, // Not available via device_info_plus on Linux
        );
      } catch (e) {
        AppLogger.w('DeviceInfo unavailable: $e');
      }
    } else if (!kIsWeb && Platform.isMacOS) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final mac = await deviceInfo.macOsInfo;
        // For macOS, use systemGUID as computerName, no cores available
        return HardwareComponents(
          computerName: mac.systemGUID ?? '',
          numberOfCores: 0, // Not available via device_info_plus on macOS
        );
      } catch (e) {
        AppLogger.w('DeviceInfo unavailable: $e');
      }
    } else {
      // Android / iOS / web fallback signals
      try {
        final deviceInfo = DeviceInfoPlugin();
        final android = await deviceInfo.androidInfo;
        // android.id is not nullable per device_info_plus
        return HardwareComponents(
          computerName: android.id,
          numberOfCores: 0, // Not used in mobile fingerprint
        );
      } catch (e) {
        AppLogger.w('AndroidInfo unavailable: $e');
      }
      try {
        final deviceInfo = DeviceInfoPlugin();
        final ios = await deviceInfo.iosInfo;
        return HardwareComponents(
          computerName: ios.identifierForVendor ?? '',
          numberOfCores: 0, // Not used in mobile fingerprint
        );
      } catch (e) {
        AppLogger.w('IosInfo unavailable: $e');
      }
    }

    throw Exception('No hardware signals available');
  }

  /// Fallback if nothing else works.
  static Future<String> _fallbackHardwareId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isWindows) {
        final win = await deviceInfo.windowsInfo;
        // Fallback also excludes RAM for consistency; uses stable deviceId.
        final raw = '${win.computerName}_${win.numberOfCores}_${win.deviceId}';
        final hash = sha256.convert(utf8.encode(raw)).toString();
        _cachedId = hash;
        return hash;
      }
    } catch (_) {}
    return 'fallback_unknown';
  }

  /// Verify that the current device matches a previously saved hardware ID.
  /// This is a simple hash comparison - for tolerant matching, use isSameDeviceTolerant.
  static Future<bool> isSameDevice(String savedHardwareId) async {
    final current = await getHardwareId();
    return current == savedHardwareId;
  }

  /// Tolerant device matching using component comparison.
  /// Returns true if at least 2 of the available components match.
  /// Returns true if saved components are empty/null (first activation).
  static Future<bool> isSameDeviceTolerant(
    String savedHardwareId,
    HardwareComponents? savedComponents,
  ) async {
    final current = await getHardwareId();
    
    // If no saved components, fall back to hash comparison
    if (savedComponents == null) {
      return current == savedHardwareId;
    }

    final currentComponents = await getHardwareComponents();
    
    // Count available components for threshold calculation
    int availableComponents = 0;
    if (savedComponents.computerName.isNotEmpty) availableComponents++;
    if (savedComponents.numberOfCores > 0) availableComponents++;
    
    // If no components available, fall back to hash comparison
    if (availableComponents == 0) {
      return current == savedHardwareId;
    }

    // Count matches
    final matches = currentComponents.countMatches(savedComponents);
    
    // Require at least 2 matches OR majority of available components
    final threshold = availableComponents >= 2 ? 2 : availableComponents;
    final isMatch = matches >= threshold;
    
    if (!isMatch) {
      AppLogger.w(
        'Hardware component mismatch: '
        'matches=$matches/$availableComponents, '
        'saved=${savedComponents.toHashString()}, '
        'current=${currentComponents.toHashString()}'
      );
    }
    
    return isMatch;
  }
}
