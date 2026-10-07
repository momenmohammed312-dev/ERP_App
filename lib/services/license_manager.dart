import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
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

    // Paid license: signed lease issued by the license server.
    // The lease is verified offline with the baked-in PUBLIC key.
    try {
      final secureData = await SecureLicenseStorage.read();
      final token = secureData?.licenseJson?['lease_token'] as String?;
      if (secureData == null || token == null) return null;

      final license = await _parseLease(token);
      if (license == null) return null;

      // Clock-rollback protection: compare against the last time reported by
      // the SERVER (not the local clock), so a wrong-but-later-fixed clock can
      // never leave the customer locked out permanently.
      final serverTime = DateTime.tryParse(
        '${secureData.licenseJson?['server_time'] ?? ''}',
      );
      if (serverTime != null &&
          DateTime.now().toUtc().isBefore(
            serverTime.toUtc().subtract(const Duration(days: 1)),
          )) {
        AppLogger.w('System clock is behind the last server time — rejecting');
        return null;
      }

      await _updateSessionTracking(secureData);
      return license;
    } catch (e) {
      AppLogger.e('Error reading license lease', e);
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
  // ONLINE LEASE (signed by the license server)
  // ════════════════════════════════════════════════════════════════════

  /// Extra days the app keeps working after the lease's own expiry, so a
  /// customer who is offline for a few days isn't locked out immediately.
  static const int _leaseGraceDays = 7;

  /// Verifies a lease JWT (RS256, public key baked into the app) and turns it
  /// into a [License]. Returns null when the signature, the device binding or
  /// the lease expiry is not valid. Never throws.
  Future<License?> _parseLease(String token) async {
    try {
      if (LicenseConfig.publicKey.isEmpty) {
        AppLogger.e('LICENSE_PUBLIC_KEY not injected — cannot verify lease');
        return null;
      }

      // Only accept RS256 (blocks "alg: none" / algorithm-confusion tricks).
      final headerPart = token.split('.').first;
      final header = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(headerPart))),
      ) as Map<String, dynamic>;
      if (header['alg'] != 'RS256') {
        AppLogger.w('Lease rejected: unexpected alg ${header['alg']}');
        return null;
      }

      final jwt = JWT.verify(
        token,
        RSAPublicKey(LicenseConfig.publicKey),
        checkHeaderType: false,
        checkExpiresIn: false, // lease expiry is checked below, with grace
      );
      final p = Map<String, dynamic>.from(jwt.payload as Map);

      // Device binding: matching EITHER id is enough, so a change in one of
      // them (Windows reinstall, restored AppData...) doesn't lock the user.
      final machineGuid = await HardwareIdService.getMachineGuid();
      final installUuid = await HardwareIdService.getInstallUuid();
      final sameMachine =
          machineGuid.isNotEmpty && p['machine_guid'] == machineGuid;
      final sameInstall =
          installUuid.isNotEmpty && p['install_uuid'] == installUuid;
      if (!sameMachine && !sameInstall) {
        AppLogger.w('Lease rejected: issued for a different device');
        return null;
      }

      final leaseEnd = DateTime.fromMillisecondsSinceEpoch(
        (p['exp'] as int) * 1000,
      );
      if (DateTime.now().isAfter(
        leaseEnd.add(const Duration(days: _leaseGraceDays)),
      )) {
        AppLogger.w('Lease expired — online renewal required');
        return null;
      }

      final issued = DateTime.fromMillisecondsSinceEpoch(
        (p['iat'] as int) * 1000,
      );
      final licenseExpiryRaw = p['license_expires_at'] as String?;
      final type = LicenseType.values.firstWhere(
        (t) => t.name == p['plan'],
        orElse: () => LicenseType.basic,
      );

      // Empty feature list from the server → fall back to the plan defaults.
      var features = List<String>.from((p['features'] as List?) ?? const []);
      if (features.isEmpty) {
        final plan = LicenseConfig.licenseTypes[type.name];
        features = plan != null
            ? List<String>.from(plan['features'] as List)
            : List<String>.from(LicenseConfig.availableFeatures);
      }

      return License(
        licenseKey: '${p['license_key']}',
        deviceFingerprint: machineGuid,
        type: type,
        issueDate: issued,
        // null on the server = lifetime license. The lease itself is enforced
        // above, so this date only drives the "days remaining" display.
        expiryDate: licenseExpiryRaw != null
            ? DateTime.parse(licenseExpiryRaw)
            : issued.add(const Duration(days: 36500)),
        features: features,
        maxUsers: _getMaxUsersForType(type),
        companyName: '',
        contactEmail: '',
        hardwareId: await HardwareIdService.getHardwareId(),
      );
    } catch (e) {
      AppLogger.e('Lease verification failed: $e');
      return null;
    }
  }

  /// Verifies a lease received from the server and stores it securely.
  /// Called by OnlineLicenseService after a successful activate / checkin.
  Future<LicenseValidationResult> saveLease(
    String token, {
    String? serverTime,
  }) async {
    final license = await _parseLease(token);
    if (license == null) {
      return LicenseValidationResult.invalid(
        'تعذر التحقق من تصريح الترخيص القادم من السيرفر',
      );
    }

    final existing = await SecureLicenseStorage.read();
    final hardwareId = await HardwareIdService.getHardwareId();
    final components = await HardwareIdService.getHardwareComponents();

    final saved = await SecureLicenseStorage.write(
      SecureLicenseData(
        firstRunDate: existing?.firstRunDate ?? DateTime.now(),
        hardwareId: hardwareId,
        licenseJson: {
          'lease_token': token,
          'license_key': license.licenseKey,
          'server_time':
              serverTime ?? DateTime.now().toUtc().toIso8601String(),
        },
        lastCheckTime: DateTime.now(),
        sessionElapsedMs: existing?.sessionElapsedMs ?? 0,
        installCount: (existing?.installCount ?? 0) + 1,
        lastHardwareComponents: components.toJson(),
      ),
    );
    if (!saved) {
      return LicenseValidationResult.invalid('تعذر حفظ الترخيص على الجهاز');
    }
    return LicenseValidationResult.valid(license);
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

    // Only write to disk if at least 1 minute elapsed to avoid thrashing I/O on every feature check
    if (elapsed < 60000) return;

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
