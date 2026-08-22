import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter/foundation.dart';
import '../core/utils/logger.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'hardware_id_service.dart';
import 'secure_license_storage.dart';

enum LicenseType {
  free, // مجاني — كل المميزات بدون تفعيل
  trial, // تجريبي - 7 أيام - مستخدم واحد
  basic, // أساسي - مستخدم واحد
  standard, // قياسي - 3 مستخدمين
  professional, // احترافي - 5 مستخدمين
  enterprise, // مؤسسي - 10 مستخدمين
}

class License {
  final String licenseKey;
  final String deviceFingerprint;
  final LicenseType type;
  final DateTime issueDate;
  final DateTime expiryDate;
  final List<String> features;
  final int maxUsers;
  final String companyName;
  final String contactEmail;
  final String? signature;
  final String? hardwareId;
  final int gracePeriodDays = 7;

  License({
    required this.licenseKey,
    required this.deviceFingerprint,
    required this.type,
    required this.issueDate,
    required this.expiryDate,
    required this.features,
    required this.maxUsers,
    required this.companyName,
    required this.contactEmail,
    this.signature,
    this.hardwareId,
  });

  bool get isExpired {
    final now = DateTime.now();
    final effectiveExpiry = expiryDate.add(Duration(days: gracePeriodDays));
    return now.isAfter(effectiveExpiry);
  }

  bool get isValid => !isExpired && isSignatureValid;

  bool get isSignatureValid {
    if (signature == null) return true;
    final data =
        '$licenseKey$deviceFingerprint$type$issueDate$expiryDate$maxUsers$companyName';
    final expectedSignature = _generateSignature(data);
    return expectedSignature == signature;
  }

  Future<bool> get isHardwareBound async {
    if (hardwareId == null) return true;
    return hardwareId == await HardwareIdService.getHardwareId();
  }

  int get daysRemaining {
    if (isExpired) return 0;
    return expiryDate.difference(DateTime.now()).inDays;
  }

  String get licenseType => type.toString().split('.').last;

  static String _generateSignature(String data) {
    final key = utf8.encode(LicenseConfig.secretKey);
    final bytes = utf8.encode(data);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return base64Encode(digest.bytes);
  }

  Map<String, dynamic> toJson() => {
    'license_key': licenseKey,
    'device': deviceFingerprint,
    'type': type.toString().split('.').last,
    'issue_date': issueDate.toIso8601String(),
    'expiry': expiryDate.toIso8601String(),
    'features': features,
    'max_users': maxUsers,
    'company_name': companyName,
    'contact_email': contactEmail,
    'signature': signature,
    'hardware_id': hardwareId,
  };

  factory License.fromJson(Map<String, dynamic> json) {
    return License(
      licenseKey: json['license_key'],
      deviceFingerprint: json['device'],
      type: LicenseType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
      ),
      issueDate: DateTime.parse(json['issue_date']),
      expiryDate: DateTime.parse(json['expiry']),
      features: List<String>.from(json['features']),
      maxUsers: json['max_users'],
      companyName: json['company_name'],
      contactEmail: json['contact_email'],
      signature: json['signature'],
      hardwareId: json['hardware_id'],
    );
  }
}

class LicenseManager {
  static const String _storageKey = 'app_license';
  static const String _secretKey = LicenseConfig.secretKey;
  static const String _firstRunKey = 'free_version_first_run';
  static const int _freeTrialDays = 36500; // 100 years
  static const int _trialDurationDays = 7; // مدة النسخة التجريبية: 7 أيام

  // Singleton
  static final LicenseManager _instance = LicenseManager._internal();
  factory LicenseManager() => _instance;
  LicenseManager._internal();

  // ════════════════════════════════════════════════════════════════════
  // توليد بصمة الجهاز (Device Fingerprinting)
  // ════════════════════════════════════════════════════════════════════

  Future<String> generateDeviceFingerprint() async {
    if (kIsWeb) return 'web-device-fingerprint';

    try {
      return await HardwareIdService.getHardwareId();
    } catch (e) {
      AppLogger.e('Error generating fingerprint', e);
      throw Exception('فشل في توليد بصمة الجهاز: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // توليد مفتاح ترخيص
  // ════════════════════════════════════════════════════════════════════

  String generateLicenseKey({
    required String deviceFingerprint,
    required LicenseType type,
    required int validityDays,
    required List<String> features,
    required String companyName,
    required String contactEmail,
  }) {
    final now = DateTime.now();
    final expiry = now.add(Duration(days: validityDays));

    final maxUsers = _getMaxUsersForType(type);

    final licenseData = {
      'device': deviceFingerprint,
      'type': type.toString().split('.').last,
      'issue_date': now.toIso8601String(),
      'expiry': expiry.toIso8601String(),
      'features': features,
      'max_users': maxUsers,
      'company_name': companyName,
      'contact_email': contactEmail,
      'version': '1.0',
    };

    final jsonString = jsonEncode(licenseData);
    final encryptedData = _encrypt(jsonString);
    final signature = _generateSignature(encryptedData);

    return '$encryptedData.$signature';
  }

  // ════════════════════════════════════════════════════════════════════
  // التحقق من صحة الترخيص
  // ════════════════════════════════════════════════════════════════════

  Future<LicenseValidationResult> validateLicense(String licenseKey) async {
    try {
      final parts = licenseKey.split('.');
      if (parts.length != 2) {
        return LicenseValidationResult.invalid('صيغة مفتاح الترخيص غير صحيحة');
      }

      final encryptedData = parts[0];
      final providedSignature = parts[1];

      final calculatedSignature = _generateSignature(encryptedData);
      if (calculatedSignature != providedSignature) {
        return LicenseValidationResult.invalid(
          'مفتاح الترخيص غير صحيح (توقيع خاطئ)',
        );
      }

      final decryptedJson = _decrypt(encryptedData);
      final licenseData = jsonDecode(decryptedJson) as Map<String, dynamic>;

      // Hardware binding with tolerant matching
      final currentFingerprint = await generateDeviceFingerprint();
      final currentComponents = await HardwareIdService.getHardwareComponents();
      final savedDevice = licenseData['device'];

      if (savedDevice == 'UNBOUND' || savedDevice.isEmpty) {
        licenseData['device'] = currentFingerprint;
      } else {
        // Try tolerant matching first
        final isSameDevice = await HardwareIdService.isSameDeviceTolerant(
          savedDevice,
          null, // No saved components in license key itself
        );
        
        if (!isSameDevice) {
          // Hard mismatch - this is a different device
          return LicenseValidationResult.invalid(
            'هذا الترخيص مُفعَّل على جهاز آخر',
          );
        }
      }

      // Expiry check
      final expiryDate = DateTime.parse(licenseData['expiry']);
      if (DateTime.now().isAfter(expiryDate)) {
        return LicenseValidationResult.expired(
          'انتهت صلاحية الترخيص في ${_formatDate(expiryDate)}',
        );
      }

      // Build License with hardware ID
      final hardwareId = await HardwareIdService.getHardwareId();
      final license = License(
        licenseKey: licenseKey,
        deviceFingerprint: licenseData['device'],
        type: LicenseType.values.firstWhere(
          (e) => e.toString().split('.').last == licenseData['type'],
        ),
        issueDate: DateTime.parse(licenseData['issue_date']),
        expiryDate: expiryDate,
        features: List<String>.from(licenseData['features']),
        maxUsers: licenseData['max_users'],
        companyName: licenseData['company_name'],
        contactEmail: licenseData['contact_email'],
        hardwareId: hardwareId,
      );

      // Save to secure storage
      await _saveLicenseSecure(license);

      return LicenseValidationResult.valid(license);
    } catch (e) {
      return LicenseValidationResult.invalid('خطأ في التحقق من الترخيص: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // التحقق من الترخيص المحفوظ
  // ════════════════════════════════════════════════════════════════════

  Future<bool> isLicenseActive() async {
    // Free version — always active, no license required
    if (LicenseConfig.isFreeVersion) {
      return true;
    }

    // Paid license: check from secure storage first, fallback to prefs
    final license = await getCurrentLicense();
    if (license == null) return false;
    return license.isValid;
  }

  Future<bool> isLicenseValid() async {
    return await isLicenseActive();
  }

  Future<bool> isFeatureEnabled(String feature) async {
    return await hasFeature(feature);
  }

  Future<void> deactivateLicense() async {
    await deactivate();
  }

  /// Current app version - when this changes, old license data is cleared
  /// to give clients a fresh 100-year period after updates.
  static const String _currentAppVersion = '2.3.0';

  Future<License?> getCurrentLicense() async {
    if (LicenseConfig.isFreeVersion) {
      final data = await SecureLicenseStorage.read();
      final hardwareId = await HardwareIdService.getHardwareId();

      // Clear old license data if app version changed (update detected)
      if (data != null && data.appVersion != _currentAppVersion) {
        AppLogger.i('App updated from ${data.appVersion} to $_currentAppVersion — resetting license');
        await SecureLicenseStorage.clear();
        // Fall through to create fresh data below
      }

      final freshData = await SecureLicenseStorage.read();

      if (freshData == null) {
        // First run or update — create and save fresh data
        final now = DateTime.now();
        final currentComponents = await HardwareIdService.getHardwareComponents();
        final newData = SecureLicenseData.create(
          firstRunDate: now,
          hardwareId: hardwareId,
          appVersion: _currentAppVersion,
          hardwareComponents: currentComponents.toJson(),
        );
        await SecureLicenseStorage.write(newData);
        // Also save to SharedPreferences for migration
        await _saveFirstRunDate(now);
        return License(
          licenseKey: 'FREE_VERSION',
          deviceFingerprint: 'free',
          type: LicenseType.free,
          issueDate: now,
          expiryDate: now.add(Duration(days: _freeTrialDays)),
          features: List<String>.from(LicenseConfig.availableFeatures),
          maxUsers: 999,
          companyName: 'Free Version',
          contactEmail: '',
          hardwareId: hardwareId,
        );
      }

      // Hardware binding check with grace period
      if (freshData.hardwareId.isNotEmpty) {
        final currentComponents = await HardwareIdService.getHardwareComponents();
        final savedComponents = freshData.lastHardwareComponents != null
            ? HardwareComponents.fromJson(freshData.lastHardwareComponents!)
            : null;
        
        final isSameDevice = await HardwareIdService.isSameDeviceTolerant(
          freshData.hardwareId,
          savedComponents,
        );
        
        if (!isSameDevice) {
          // Increment mismatch counter
          final newMismatchCount = freshData.hardwareMismatchCount + 1;
          AppLogger.w(
            'Hardware mismatch — free version bound to different device '
            '(mismatch count: $newMismatchCount)'
          );
          
          if (newMismatchCount >= 2) {
            // Second consecutive mismatch - block
            AppLogger.e('Hardware mismatch persisted - blocking free version');
            return null;
          } else {
            // First mismatch - update counter and allow grace launch
            final updatedData = freshData.copyWith(
              hardwareMismatchCount: newMismatchCount,
              lastMismatchTime: DateTime.now(),
              lastHardwareComponents: currentComponents.toJson(),
            );
            await SecureLicenseStorage.write(updatedData);
            AppLogger.w('First hardware mismatch - grace launch allowed, user should reactivate');
            // Allow this launch but log warning
          }
        } else {
          // Match successful - reset mismatch counter
          if (freshData.hardwareMismatchCount > 0) {
            final updatedData = freshData.copyWith(
              hardwareMismatchCount: 0,
              lastMismatchTime: null,
              lastHardwareComponents: currentComponents.toJson(),
            );
            await SecureLicenseStorage.write(updatedData);
            AppLogger.i('Hardware match confirmed - mismatch counter reset');
          }
        }
      }

      final expiry = freshData.firstRunDate.add(Duration(days: _freeTrialDays));
      if (DateTime.now().isAfter(expiry)) return null;

      return License(
        licenseKey: 'FREE_VERSION',
        deviceFingerprint: 'free',
        type: LicenseType.free,
        issueDate: freshData.firstRunDate,
        expiryDate: expiry,
        features: List<String>.from(LicenseConfig.availableFeatures),
        maxUsers: 999,
        companyName: 'Free Version',
        contactEmail: '',
        hardwareId: freshData.hardwareId,
      );
    }

    // Paid license: try secure storage first
    try {
      final secureData = await SecureLicenseStorage.read();
      if (secureData != null && secureData.licenseJson != null) {
        final license = License.fromJson(secureData.licenseJson!);

        // Hardware binding check with grace period
        final currentHwId = await HardwareIdService.getHardwareId();
        final currentComponents = await HardwareIdService.getHardwareComponents();
        final savedComponents = secureData.lastHardwareComponents != null
            ? HardwareComponents.fromJson(secureData.lastHardwareComponents!)
            : null;
        
        if (secureData.hardwareId.isNotEmpty) {
          final isSameDevice = await HardwareIdService.isSameDeviceTolerant(
            secureData.hardwareId,
            savedComponents,
          );
          
          if (!isSameDevice) {
            // Increment mismatch counter
            final newMismatchCount = secureData.hardwareMismatchCount + 1;
            AppLogger.w(
              'Hardware mismatch — license bound to different device '
              '(mismatch count: $newMismatchCount)'
            );
            
            if (newMismatchCount >= 2) {
              // Second consecutive mismatch - block
              AppLogger.e('Hardware mismatch persisted - blocking paid license');
              return null;
            } else {
              // First mismatch - update counter and allow grace launch
              final updatedData = secureData.copyWith(
                hardwareMismatchCount: newMismatchCount,
                lastMismatchTime: DateTime.now(),
                lastHardwareComponents: currentComponents.toJson(),
              );
              await SecureLicenseStorage.write(updatedData);
              AppLogger.w('First hardware mismatch - grace launch allowed, user should reactivate');
              // Allow this launch but log warning
            }
          } else {
            // Match successful - reset mismatch counter
            if (secureData.hardwareMismatchCount > 0) {
              final updatedData = secureData.copyWith(
                hardwareMismatchCount: 0,
                lastMismatchTime: null,
                lastHardwareComponents: currentComponents.toJson(),
              );
              await SecureLicenseStorage.write(updatedData);
              AppLogger.i('Hardware match confirmed - mismatch counter reset');
            }
          }
        }

        // Update session tracking
        await _updateSessionTracking(secureData);

        return license;
      }
    } catch (e) {
      AppLogger.e('Error reading license from secure storage', e);
    }

    // Fallback to SharedPreferences (migration path)
    try {
      final prefs = await SharedPreferences.getInstance();
      final licenseJson = prefs.getString(_storageKey);
      if (licenseJson == null) return null;

      final data = jsonDecode(licenseJson);
      final license = License.fromJson(data);

      // Migrate to secure storage
      await _saveLicenseSecure(license);

      return license;
    } catch (e) {
      AppLogger.e('Error loading current license: $e');
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // FEATURE / USER CHECKS
  // ════════════════════════════════════════════════════════════════════

  Future<bool> hasFeature(String featureName) async {
    if (LicenseConfig.isFreeVersion) return true;
    final license = await getCurrentLicense();
    if (license == null || !license.isValid) return false;
    return license.features.contains(featureName);
  }

  Future<bool> canAddUser(int currentUserCount) async {
    if (LicenseConfig.isFreeVersion) return true;
    final license = await getCurrentLicense();
    if (license == null || !license.isValid) return false;
    return currentUserCount < license.maxUsers;
  }

  // ════════════════════════════════════════════════════════════════════
  // FREE TRIAL ACTIVATION
  // ════════════════════════════════════════════════════════════════════

  Future<LicenseValidationResult> activateTrial() async {
    try {
      final key = generateLicenseKey(
        deviceFingerprint: 'UNBOUND',
        type: LicenseType.trial,
        validityDays: _trialDurationDays,
        features: List<String>.from(LicenseConfig.availableFeatures),
        companyName: 'Trial',
        contactEmail: '',
      );
      return await validateLicense(key);
    } catch (e) {
      return LicenseValidationResult.invalid('فشل تفعيل النسخة التجريبية: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // DEACTIVATION
  // ════════════════════════════════════════════════════════════════════

  Future<void> deactivate() async {
    // Clear secure storage
    await SecureLicenseStorage.clear();
    // Also clear SharedPreferences (legacy)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  // ════════════════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ════════════════════════════════════════════════════════════════════

  /// Save license to secure storage (encrypted file).
  Future<void> _saveLicenseSecure(License license) async {
    final existing = await SecureLicenseStorage.read();
    final hardwareId = await HardwareIdService.getHardwareId();
    final currentComponents = await HardwareIdService.getHardwareComponents();

    final data = SecureLicenseData(
      firstRunDate: existing?.firstRunDate ?? DateTime.now(),
      hardwareId: hardwareId,
      licenseJson: license.toJson(),
      lastCheckTime: DateTime.now(),
      sessionElapsedMs: existing?.sessionElapsedMs ?? 0,
      installCount: (existing?.installCount ?? 0) + 1,
      lastHardwareComponents: currentComponents.toJson(),
      // Reset mismatch counter on successful activation
      hardwareMismatchCount: 0,
      lastMismatchTime: null,
    );

    await SecureLicenseStorage.write(data);

    // Also keep SharedPreferences for backward compatibility
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(license.toJson()));
  }

  /// Update session elapsed time tracking.
  Future<void> _updateSessionTracking(SecureLicenseData current) async {
    final now = DateTime.now();
    final elapsed = now.difference(current.lastCheckTime).inMilliseconds;

    // Only add if elapsed is reasonable (not negative, not more than 24h)
    final adjustedElapsed = (elapsed > 0 && elapsed < 86400000)
        ? current.sessionElapsedMs + elapsed
        : current.sessionElapsedMs;

    final updated = current.copyWith(
      lastCheckTime: now,
      sessionElapsedMs: adjustedElapsed,
    );

    await SecureLicenseStorage.write(updated);
  }

  // ════════════════════════════════════════════════════════════════════
  // MIGRATION FROM SHARED PREFERENCES
  // ════════════════════════════════════════════════════════════════════

  Future<void> _saveFirstRunDate(DateTime date) async {
    final hwId = await HardwareIdService.getHardwareId();
    final currentComponents = await HardwareIdService.getHardwareComponents();
    final existing = await SecureLicenseStorage.read();

    if (existing != null) {
      // Update existing
      await SecureLicenseStorage.write(
        existing.copyWith(
          firstRunDate: date,
          lastHardwareComponents: currentComponents.toJson(),
        )
      );
    } else {
      // Create new
      await SecureLicenseStorage.write(SecureLicenseData.create(
        firstRunDate: date,
        hardwareId: hwId,
        hardwareComponents: currentComponents.toJson(),
      ));
    }

    // Also save to SharedPreferences for backward compatibility
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_firstRunKey, date.toIso8601String());
  }

  // ════════════════════════════════════════════════════════════════════
  // ENCRYPTION HELPERS
  // ════════════════════════════════════════════════════════════════════

  String _encrypt(String plainText) {
    final keyBytes = md5.convert(utf8.encode(_secretKey)).bytes;
    final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt_pkg.IV(Uint8List(16));
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );

    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  String _decrypt(String encryptedText) {
    final keyBytes = md5.convert(utf8.encode(_secretKey)).bytes;
    final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
    final iv = encrypt_pkg.IV(Uint8List(16));
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );

    final encrypted = encrypt_pkg.Encrypted.fromBase64(encryptedText);
    return encrypter.decrypt(encrypted, iv: iv);
  }

  String _generateSignature(String data) {
    final bytes = utf8.encode(data + _secretKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  int _getMaxUsersForType(LicenseType type) {
    switch (type) {
      case LicenseType.free:
      case LicenseType.trial:
      case LicenseType.basic:
        return 1;
      case LicenseType.standard:
        return 3;
      case LicenseType.professional:
        return 5;
      case LicenseType.enterprise:
        return 10;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class LicenseValidationResult {
  final bool isValid;
  final String? errorMessage;
  final License? license;

  LicenseValidationResult.valid(this.license)
    : isValid = true,
      errorMessage = null;

  LicenseValidationResult.invalid(this.errorMessage)
    : isValid = false,
      license = null;

  LicenseValidationResult.expired(this.errorMessage)
    : isValid = false,
      license = null;
}
