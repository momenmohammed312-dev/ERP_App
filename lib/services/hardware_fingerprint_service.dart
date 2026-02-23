import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class HardwareFingerprintService {
  /// Generate unique device fingerprint
  static Future<String> generateFingerprint() async {
    if (kIsWeb) {
      // Web doesn't support device fingerprinting, return a generic one
      return 'web-device-fingerprint';
    }
    final deviceInfo = DeviceInfoPlugin();
    String fingerprint = '';

    try {
      if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        fingerprint =
            '${windowsInfo.computerName}-'
            '${windowsInfo.numberOfCores}-'
            '${windowsInfo.systemMemoryInMegabytes}';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        fingerprint = '${linuxInfo.machineId}-${linuxInfo.name}';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        fingerprint = '${macInfo.systemGUID}-${macInfo.model}';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        fingerprint =
            '${androidInfo.id}-${androidInfo.model}-${androidInfo.manufacturer}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        fingerprint = '${iosInfo.identifierForVendor}-${iosInfo.model}';
      } else {
        // Fallback for other platforms
        fingerprint = 'unknown-device-${DateTime.now().millisecondsSinceEpoch}';
      }

      // Hash the fingerprint for consistency
      final bytes = utf8.encode(fingerprint);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      // Fallback in case of error
      return 'fallback-device-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Verify if current device matches fingerprint
  static Future<bool> verifyFingerprint(String storedFingerprint) async {
    final currentFingerprint = await generateFingerprint();
    return currentFingerprint == storedFingerprint;
  }
}
