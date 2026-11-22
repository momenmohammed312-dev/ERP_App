import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter/foundation.dart';
import '../core/utils/logger.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'hardware_id_service.dart';
import 'license_entitlement.dart';
import 'secure_license_storage.dart';

List<String> _widenLegacyFeatures(List<String> raw, LicenseType type) {
  final features = <String>{
    ...raw.map((f) => f.trim()).where((f) => f.isNotEmpty),
  };

  // Legacy catch-all markers meaning "everything".
  const catchAll = {'all', '*', 'admin'};
  if (raw.any(catchAll.contains)) {
    features.addAll(LicenseConfig.availableFeatures);
  }

  // Legacy aliases for modules that were renamed.
  const aliases = <String, List<String>>{
    'users': ['staff_management', 'attendance', 'payroll'],
    'user': ['staff_management'],
    'accounting': ['advanced_reports'],
    'export': ['backup'],
  };
  aliases.forEach((legacy, modern) {
    if (features.contains(legacy)) features.addAll(modern);
  });

  // Full-access bundles always included the add-on modules, which were open to
  // everyone pre-merge.
  if (type == LicenseType.professional ||
      type == LicenseType.enterprise ||
      type == LicenseType.free ||
      type == LicenseType.trial) {
    features.addAll(const {
      'staff_management',
      'attendance',
      'payroll',
      'custody',
      'damaged_goods',
      'manufacturing',
    });
  }

  return features.toList();
}

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

  /// Hard expiry — no grace period (owner decision, BUG-007 §5 option أ).
  ///
  /// The instant `now` passes [expiryDate] the license is expired. There used
  /// to be a 7-day grace here while [daysRemaining] counted down to the raw
  /// expiry date, so the UI showed "0 يوم" and then negative day counts for a
  /// full week while every paid feature stayed unlocked.
  bool get isExpired => LicenseManager.nowProvider().isAfter(expiryDate);

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

  /// Whole days left until [expiryDate]. Never negative: an expired license
  /// reports 0 so the badge can never render a negative day count. Also clamped
  /// to the license's total term so an accidental backward clock reset never
  /// displays thousands of days.
  ///
  /// A value of 0 means "less than 24 hours left OR already expired" — always
  /// read it together with [isExpired], never on its own.
  int get daysRemaining {
    if (isExpired) return 0;
    final totalTerm = expiryDate.difference(issueDate);
    if (totalTerm < const Duration(days: 1)) return 0;
    final remaining = expiryDate.difference(LicenseManager.nowProvider()).inDays;
    if (remaining < 0) return 0;
    final totalTermDays = totalTerm.inDays;
    if (totalTermDays > 0 && remaining > totalTermDays) {
      return totalTermDays;
    }
    return remaining;
  }

  /// Exact time left until [expiryDate], clamped to zero once expired.
  Duration get timeRemaining {
    if (isExpired) return Duration.zero;
    final remaining = expiryDate.difference(LicenseManager.nowProvider());
    return remaining.isNegative ? Duration.zero : remaining;
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
    // BUG-009: the old `firstWhere` had no `orElse`, so any plan identifier
    // outside LicenseType threw a StateError and the customer fell through to
    // "no license". Resolve through LicensePlans instead — it knows the
    // dashboard/issuer plan names (yearly, lifetime, monthly, custom) and
    // never throws.
    final planName = LicensePlans.resolveOrFallback('${json['type']}');
    if (LicensePlans.isUnknown('${json['type']}')) {
      AppLogger.w(
        'Unknown license plan "${json['type']}" — falling back to '
        '${LicensePlans.fallbackName}',
      );
    }

    return License(
      licenseKey: json['license_key'],
      deviceFingerprint: json['device'],
      type: LicenseType.values.firstWhere(
        (e) => e.name == planName,
        orElse: () => LicenseType.standard,
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
  /// Clock seam for deterministic time-based tests (defaults to real clock).
  @visibleForTesting
  static DateTime Function() nowProvider = DateTime.now;

  static const String _storageKey = 'app_license';
  static const String _secretKey = LicenseConfig.secretKey;
  static const String _firstRunKey = 'free_version_first_run';

  // Singleton
  static final LicenseManager _instance = LicenseManager._internal();
  factory LicenseManager() => _instance;
  LicenseManager._internal() {
    if (kReleaseMode) {
      try {
        LicenseConfig.assertSecretKeyConfigured();
      } catch (e) {
        AppLogger.w('Running in release mode without custom LICENSE_SECRET_KEY: $e');
      }
    }
  }

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
      if (LicenseManager.nowProvider().isAfter(expiryDate)) {
        return LicenseValidationResult.expired(
          'انتهت صلاحية الترخيص في ${_formatDate(expiryDate)}',
        );
      }

      // Build License with hardware ID
      final hardwareId = await HardwareIdService.getHardwareId();
      final license = License(
        licenseKey: licenseKey,
        deviceFingerprint: licenseData['device'],
        // BUG-009: resolve dashboard/issuer plan names, never throw.
        type: LicenseType.values.firstWhere(
          (e) =>
              e.name ==
              LicensePlans.resolveOrFallback('${licenseData['type']}'),
          orElse: () => LicenseType.standard,
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
    // Permanent free version (100 years) — always active, no license required.
    // Time-limited trials (e.g. 7 days) still go through getCurrentLicense().
    if (LicenseConfig.isPermanentFreeVersion) {
      return true;
    }

    // Paid or time-limited trial license: check validity from current license.
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

  /// Diagnostic only — records which build last touched the license file.
  ///
  /// FEAT-013: this used to trigger `SecureLicenseStorage.clear()` on every
  /// change, wiping a paying customer's license on a routine update. It is now
  /// stamped in place and never used as a deletion trigger.
  static const String _currentAppVersion = '2.3.0';

  // ════════════════════════════════════════════════════════════════════
  // LEGACY AES-LICENSE BRIDGE (FEAT-014)
  // ════════════════════════════════════════════════════════════════════

  /// How long an old pre-RS256 license keeps working after this build is
  /// installed. Owner-approved, see MADAR/bug issues/FEAT-014.
  static const Duration legacyGracePeriod = Duration(days: 90);

  /// True once a legacy license has been seen but the grace window has since
  /// passed. The UI uses this to ask for a signed document instead of showing
  /// a generic "no license" screen.
  static bool legacyGraceExpired(SecureLicenseData? data) =>
      data != null && data.isLegacyLicense && !_legacyStillGraced(data);

  static bool _legacyStillGraced(SecureLicenseData data) {
    final endsAt = data.legacyGraceEndsAt;
    if (endsAt == null) return false;
    return LicenseManager.nowProvider().isBefore(endsAt);
  }

  /// Reads a pre-RS256 AES license from [data] into a [License].
  ///
  /// Returns null when the payload is not in the legacy shape, cannot be
  /// decrypted with the current secret, or is not a well-formed license — the
  /// caller then falls through to the normal "no license" path.
  static Future<License?> _readLegacyLicense(SecureLicenseData data) async {
    final payload = data.licenseJson;
    if (payload == null) return null;

    // A signed lease already in this file is NOT a legacy license.
    if (payload.containsKey('lease_token')) return null;

    try {
      // Legacy storage kept the full license string under 'license_key'.
      final encoded = payload['license_key'];
      if (encoded is! String || !encoded.contains('.')) return null;

      final parts = encoded.split('.');
      if (parts.length != 2) return null;

      // Re-check the legacy SHA-256 signature before touching the cipher, so a
      // tampered blob is rejected without ever reaching the decryptor.
      if (_instance._generateSignature(parts[0]) != parts[1]) {
        AppLogger.w('Legacy AES license signature mismatch — rejected');
        return null;
      }

      final decoded =
          jsonDecode(_instance._decrypt(parts[0])) as Map<String, dynamic>;

      // A8: Enforce hardware fingerprint on legacy licenses so files cloned
      // to another machine are rejected even within the 90-day grace window.
      final savedDevice = '${decoded['device'] ?? ''}';
      if (savedDevice.isNotEmpty && savedDevice != 'UNBOUND') {
        final match = await HardwareIdService.isSameDeviceTolerant(savedDevice, null);
        if (!match) {
          AppLogger.w('Legacy license device mismatch: expected $savedDevice');
          return null;
        }
      }

      final typeName = '${decoded['type']}';
      if (LicensePlans.isUnknown(typeName)) {
        AppLogger.w('Unknown plan "$typeName" in legacy license');
      }
      final type = LicenseType.values.firstWhere(
        (t) => t.name == LicensePlans.resolveOrFallback(typeName),
        orElse: () => LicenseType.standard,
      );

      return License(
        licenseKey: encoded,
        deviceFingerprint: savedDevice,
        type: type,
        issueDate: DateTime.parse('${decoded['issue_date']}'),
        expiryDate: DateTime.parse('${decoded['expiry']}'),
        features: _widenLegacyFeatures(
          List<String>.from(decoded['features'] as List? ?? const []),
          type,
        ),
        maxUsers: (decoded['max_users'] as num?)?.toInt() ?? 1,
        companyName: '${decoded['company_name'] ?? ''}',
        contactEmail: '${decoded['contact_email'] ?? ''}',
        hardwareId: data.hardwareId.isEmpty ? null : data.hardwareId,
      );
    } catch (e) {
      AppLogger.w('Legacy AES license could not be read: $e');
      return null;
    }
  }

  /// Mark [data] as holding a legacy license and open the grace window.
  ///
  /// The deadline is written ONCE and never extended: if one is already
  /// recorded we keep it, so reinstalling, updating the app, or repeated
  /// launches can never restart the window.
  Future<void> _markLegacy(SecureLicenseData data) async {
    if (data.legacyGraceEndsAt != null) return;

    final stamped = data.copyWith(
      isLegacyLicense: true,
      legacyGraceEndsAt: LicenseManager.nowProvider().add(legacyGracePeriod),
    );
    await SecureLicenseStorage.write(stamped);
    AppLogger.i(
      'Legacy AES license detected — grace until '
      '${stamped.legacyGraceEndsAt!.toIso8601String()}',
    );
  }

  /// Public helper for the activation screen: "this install carries an old
  /// license that must be upgraded".
  static bool get hasLegacyLicense => _legacyLicenseSeen;
  static bool _legacyLicenseSeen = false;

  // ════════════════════════════════════════════════════════════════════
  // PAYED LICENSE: STORED LICENSE
  // ════════════════════════════════════════════════════════════════════

  /// Reads the current license and refreshes the entitlement snapshot that
  /// [LicenseEntitlement] serves from.
  ///
  /// The refresh happens here, at the one choke point every existing caller
  /// already goes through, so no call site has to remember to do it — and so
  /// the synchronous guards (router, DAO) are current by the time a write can
  /// reach them.
  Future<License?> getCurrentLicense() async {
    final license = await _readCurrentLicense();
    LicenseEntitlement.instance.update(license);
    return license;
  }

  Future<License?> _readCurrentLicense() async {
    // Recomputed on every read so a stale value can never leak across calls.
    _legacyLicenseSeen = false;
    SecureLicenseData? data;

    try {
      data = await SecureLicenseStorage.read();

      // Priority 1: Signed RS256 lease (checks paid/upgraded license BEFORE
      // falling back to free/trial so an upgraded trial install uses the paid
      // license immediately without losing data or requiring a separate build).
      final token = data?.licenseJson?['lease_token'] as String?;
      if (data != null && token != null) {
        final leaseLicense = await _parseLease(token);
        if (leaseLicense == null) {
          return LicenseConfig.isPermanentFreeVersion
              ? await _readFreeOrTrialLicense(data)
              : null;
        }

        // Clock-rollback protection: compare against the last time reported by
        // the SERVER (not the local clock), so a wrong-but-later-fixed clock can
        // never leave the customer locked out permanently.
        final serverTime = DateTime.tryParse(
          '${data.licenseJson?['server_time'] ?? ''}',
        );
        if (serverTime != null &&
            LicenseManager.nowProvider().toUtc().isBefore(
              serverTime.toUtc().subtract(const Duration(days: 1)),
            )) {
          AppLogger.w('System clock is behind the last server time — rejecting');
          return LicenseConfig.isPermanentFreeVersion
              ? await _readFreeOrTrialLicense(data)
              : null;
        }

        await _updateSessionTracking(data);
        return leaseLicense;
      }

      // Priority 2: Legacy AES-encrypted license bridge (FEAT-014).
      if (data != null && data.licenseJson != null) {
        final legacy = await _readLegacyLicense(data);
        if (legacy != null) {
          _legacyLicenseSeen = true;
          // Stamp the deadline before deciding, so a legacy license that
          // has already served out its window is refused on THIS launch
          // rather than being granted a fresh 90 days.
          await _markLegacy(data);
          final stamped = (await SecureLicenseStorage.read()) ?? data;

          if (_legacyStillGraced(stamped)) {
            AppLogger.i(
              'Serving legacy AES license until grace ends — '
              'expires ${legacy.expiryDate.toIso8601String()}',
            );
            return legacy;
          }
          AppLogger.w(
            'Legacy AES license is past its ${legacyGracePeriod.inDays}-day '
            'grace — a signed license is required',
          );
          return LicenseConfig.isPermanentFreeVersion
              ? await _readFreeOrTrialLicense(stamped)
              : null;
        }
      }
    } catch (e) {
      AppLogger.e('Error reading license lease', e);
      if (!LicenseConfig.isFreeVersion) return null;
    }

    // Priority 3: Standard licensed build with no stored license.
    if (!LicenseConfig.isFreeVersion) return null;

    // Priority 4: Permanent Free or Time-Limited Trial build.
    return _readFreeOrTrialLicense(data);
  }

  Future<License?> _readFreeOrTrialLicense(SecureLicenseData? data) async {
    final hardwareId = await HardwareIdService.getHardwareId();
    final trialDays = LicenseConfig.freeTrialDays;
    final trialMinutes = LicenseConfig.freeTrialMinutes;
    final isMinuteTrial = trialMinutes > 0;
    final trialDuration = LicenseConfig.freeTrialDuration;
    final isTimeLimited = LicenseConfig.isTimeLimitedTrial;
    final trialKey = isMinuteTrial
        ? 'TRIAL_${trialMinutes}_MIN'
        : 'TRIAL_${trialDays}_DAYS';
    final trialCompany = isMinuteTrial
        ? 'نسخة تجريبية ($trialMinutes دقيقة)'
        : 'نسخة تجريبية ($trialDays أيام)';

    // FEAT-013: an app update must NOT wipe the customer's license.
    //
    // The version stamp is kept for diagnostics only: it is refreshed in
    // place, never used as a deletion trigger. `firstRunDate` is likewise
    // preserved so the trial/free window cannot be restarted by reinstalling
    // or updating the app.
    if (data != null && data.appVersion != _currentAppVersion) {
      AppLogger.i(
        'App updated from ${data.appVersion} to $_currentAppVersion — '
        'stamping version, keeping license and firstRunDate intact',
      );
      final stamped = data.copyWith(appVersion: _currentAppVersion);
      await SecureLicenseStorage.write(stamped);
    }

    final freshData = await SecureLicenseStorage.read();

    if (freshData == null) {
      // First run — create and save fresh trial/free anchor.
      final now = LicenseManager.nowProvider();
      final currentComponents =
          await HardwareIdService.getHardwareComponents();
      final newData = SecureLicenseData(
        firstRunDate: now,
        hardwareId: hardwareId,
        lastCheckTime: now,
        appVersion: _currentAppVersion,
        lastHardwareComponents: currentComponents.toJson(),
      );
      await SecureLicenseStorage.write(newData);
      // Also save to SharedPreferences for migration
      await _saveFirstRunDate(now);
      return License(
        licenseKey: isTimeLimited ? trialKey : 'FREE_VERSION',
        deviceFingerprint: 'free',
        type: isTimeLimited ? LicenseType.trial : LicenseType.free,
        issueDate: now,
        expiryDate: now.add(trialDuration),
        features: List<String>.from(LicenseConfig.availableFeatures),
        maxUsers: 999,
        companyName: isTimeLimited ? trialCompany : 'Free Version',
        contactEmail: '',
        hardwareId: hardwareId,
      );
    }

    // Hardware binding check with grace period
    if (freshData.hardwareId.isNotEmpty) {
      final currentComponents =
          await HardwareIdService.getHardwareComponents();
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
          '(mismatch count: $newMismatchCount)',
        );

        if (newMismatchCount >= 2) {
          // Second consecutive mismatch - block
          AppLogger.e('Hardware mismatch persisted - blocking free version');
          return null;
        } else {
          // First mismatch - update counter and allow grace launch
          final updatedData = freshData.copyWith(
            hardwareMismatchCount: newMismatchCount,
            lastMismatchTime: LicenseManager.nowProvider(),
            lastHardwareComponents: currentComponents.toJson(),
          );
          await SecureLicenseStorage.write(updatedData);
          AppLogger.w(
            'First hardware mismatch - grace launch allowed, user should reactivate',
          );
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

    final now = LicenseManager.nowProvider();
    final trackedSessionMs = await _updateSessionTracking(freshData);
    final expiry = freshData.firstRunDate.add(trialDuration);

    // Never lock out on an accidental backward clock change (CMOS reset / DST).
    // Log softly only; daysRemaining handles clamping to the license term.
    if (isTimeLimited &&
        now.isBefore(
          freshData.firstRunDate.subtract(const Duration(days: 1)),
        )) {
      AppLogger.w(
        'System clock is behind trial firstRunDate — continuing without lockout',
      );
    }

    // Cumulative active usage guard for time-limited trials: expires only after
    // genuine >= trialDuration of accumulated active session time.
    var effectiveExpiry = expiry;
    if (isTimeLimited) {
      final maxTrialMs = trialDuration.inMilliseconds;
      if (trackedSessionMs >= maxTrialMs && !now.isAfter(effectiveExpiry)) {
        effectiveExpiry = now.subtract(const Duration(seconds: 1));
      }
    }

    // Always return the License object even when expired so the UI badge and
    // activation screen can clearly display "منتهي" instead of vanishing.
    return License(
      licenseKey: isTimeLimited ? trialKey : 'FREE_VERSION',
      deviceFingerprint: 'free',
      type: isTimeLimited ? LicenseType.trial : LicenseType.free,
      issueDate: freshData.firstRunDate,
      expiryDate: effectiveExpiry,
      features: List<String>.from(LicenseConfig.availableFeatures),
      maxUsers: 999,
      companyName: isTimeLimited ? trialCompany : 'Free Version',
      contactEmail: '',
      hardwareId: freshData.hardwareId,
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // FEATURE / USER CHECKS
  // ════════════════════════════════════════════════════════════════════

  /// Restores the module access a pre-RS256 customer actually had.
  ///
  /// Before the feat/online-license merge these modules were not
  /// entitlement-gated at all:
  ///
  ///   * `staff_management` sat in FeatureGuard's `bypassFeatures` list;
  ///   * `custody`, `damaged_goods` and `manufacturing` were not wrapped in a
  ///     FeatureGuard, so every licensed customer could open them.
  ///
  /// The merge replaced that with real entitlement checks keyed on the feature
  /// NAME. Licenses issued by the old generators (tools/gen_year_license.dart,
  /// tools/license_generator.dart) never carried those names — they used
  /// `users`, `admin`, `all` and a short core list — so after the merge a paying
  /// customer was silently shown "(مغلق)" on modules they had always used.
  ///
  /// This widens the stored list. Widening only — it never removes anything the
  /// license already granted — and it applies to LEGACY licenses only, so new
  /// signed leases stay strictly entitlement-driven.

  /// True when [features] grants every module — either by an explicit wildcard or
  /// by carrying the full canonical list.
  // ignore: unused_element
  bool _hasEveryFeature(List<String> features) =>
      features.contains('*') ||
      features.contains('all') ||
      LicenseConfig.availableFeatures.every(features.contains);

  Future<bool> hasFeature(String featureName) async {
    if (LicenseConfig.isPermanentFreeVersion) return true;
    final license = await getCurrentLicense();
    if (license == null || !license.isValid) return false;
    // Wildcards: '*' is the modern catch-all, 'all' is the marker the legacy
    // generators emitted. Missing 'all' here silently locked paying customers
    // out of modules they had always used.
    return license.features.contains('*') ||
        license.features.contains('all') ||
        license.features.contains(featureName);
  }

  Future<bool> canAddUser(int currentUserCount) async {
    if (LicenseConfig.isPermanentFreeVersion) return true;
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
      final header =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(headerPart))),
              )
              as Map<String, dynamic>;
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

      // Device binding: matching ANY id is enough, so a change in one of them
      // (Windows reinstall, restored AppData...) doesn't lock the user.
      // `hardware_id` is the fingerprint shown on the activation screen
      // (BUG-023): the customer reads it and the issuer signs exactly that
      // value, so offline issuance doesn't depend on the invisible SQM id.
      final machineGuid = await HardwareIdService.getMachineGuid();
      final installUuid = await HardwareIdService.getInstallUuid();
      final hardwareId = await HardwareIdService.getHardwareId();
      final sameMachine =
          machineGuid.isNotEmpty && p['machine_guid'] == machineGuid;
      final sameInstall =
          installUuid.isNotEmpty && p['install_uuid'] == installUuid;
      final sameHardware =
          hardwareId.isNotEmpty && p['hardware_id'] == hardwareId;
      if (!sameMachine && !sameInstall && !sameHardware) {
        AppLogger.w('Lease rejected: issued for a different device');
        return null;
      }

      final leaseEnd = DateTime.fromMillisecondsSinceEpoch(
        (p['exp'] as int) * 1000,
      );
      if (LicenseManager.nowProvider().isAfter(
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
        (t) => t.name == LicensePlans.resolveOrFallback('${p['plan']}'),
        orElse: () => LicenseType.standard,
      );

      // Empty feature list from the server → fall back to the plan defaults.
      var features = List<String>.from((p['features'] as List?) ?? const []);
      if (features.isEmpty) {
        final plan = LicenseConfig.licenseTypes[type.name];
        features = plan != null
            ? List<String>.from(plan['features'] as List)
            : List<String>.from(LicenseConfig.availableFeatures);
      }

      return _normalizeEntitlements(
        License(
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
          hardwareId: hardwareId,
        ),
      );
    } catch (e) {
      AppLogger.e('Lease verification failed: $e');
      return null;
    }
  }

  /// Drops entitlement names this build does not know, and refuses a lease that
  /// grants nothing runnable.
  ///
  /// Why this lives in [_parseLease] and not in the import path: the lease is a
  /// SIGNED token, so its claims cannot be rewritten before storing them. The
  /// stored token stays byte-identical to what the issuer signed; normalisation
  /// is applied every time the lease is turned into a [License], which keeps
  /// imported and server-issued leases consistent.
  ///
  /// An unknown name is not an error on its own — an issuer may legitimately
  /// name a module a given flavor has not been built with — but it is never
  /// stored, so a forged document cannot smuggle entitlement names into the
  /// app. Flavor scoping itself is enforced in `isFeatureEnabledProvider`.
  static License? _normalizeEntitlements(License license) {
    final known = license.features
        .where(LicenseConfig.availableFeatures.contains)
        .toSet();
    if (known.isEmpty) {
      AppLogger.w('Lease rejected: grants no feature this build knows');
      return null;
    }
    if (known.length != license.features.length) {
      AppLogger.w(
        'Lease: dropped ${license.features.length - known.length} unknown '
        'entitlement name(s)',
      );
    }

    return License(
      licenseKey: license.licenseKey,
      deviceFingerprint: license.deviceFingerprint,
      type: license.type,
      issueDate: license.issueDate,
      expiryDate: license.expiryDate,
      features: known.toList(),
      maxUsers: license.maxUsers,
      companyName: license.companyName,
      contactEmail: license.contactEmail,
      signature: license.signature,
      hardwareId: license.hardwareId,
    );
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
    final now = LicenseManager.nowProvider();

    final saved = await SecureLicenseStorage.write(
      SecureLicenseData(
        firstRunDate: existing?.firstRunDate ?? now,
        hardwareId: hardwareId,
        licenseJson: {
          'lease_token': token,
          'license_key': license.licenseKey,
          'server_time': serverTime ?? now.toUtc().toIso8601String(),
        },
        lastCheckTime: now,
        sessionElapsedMs: existing?.sessionElapsedMs ?? 0,
        installCount: (existing?.installCount ?? 0) + 1,
        appVersion: existing?.appVersion ?? _currentAppVersion,
        lastHardwareComponents: components.toJson(),
      ),
    );
    if (!saved) {
      return LicenseValidationResult.invalid('تعذر حفظ الترخيص على الجهاز');
    }
    LicenseEntitlement.instance.update(license);
    return LicenseValidationResult.valid(license);
  }

  // ════════════════════════════════════════════════════════════════════
  // OFFLINE LICENSE DOCUMENT IMPORT (FEAT-012)
  // ════════════════════════════════════════════════════════════════════

  /// Imports a signed license document (`.madarlicense`) with NO network call.
  ///
  /// [document] is the file content as text. Two shapes are accepted:
  ///
  ///   * the envelope — `{"madar_license_envelope":"v1","lease":"<jwt>"}`
  ///   * the bare JWT, for convenience and for the clipboard
  ///
  /// Verification is fully local: RS256 against [LicenseConfig.publicKey],
  /// then the device binding and the expiry handled by [_parseLease]. The
  /// document is stored through [saveLease], so a valid license is persisted
  /// exactly as a server-issued one would be.
  ///
  /// Never throws — malformed, foreign-device, forged and expired documents all
  /// come back as an invalid result, and a rejected import never destroys the
  /// license already on disk.
  Future<LicenseValidationResult> importLicenseDocument(String document) async {
    final token = _extractLeaseToken(document);
    if (token == null) {
      return LicenseValidationResult.invalid(
        'الملف لا يحتوي على ترخيص صالح. تأكد أنه ملف ‎.madarlicense‎ صادر من MADAR.',
      );
    }

    final license = await _parseLease(token);
    if (license == null) {
      return LicenseValidationResult.invalid(
        'تعذّر التحقق من صحة الترخيص. قد يكون الملف تالفاً، أو صادراً بخطأ، '
        'أو مخصصاً لجهاز آخر.',
      );
    }

    // serverTime is the import moment: no server is involved, so the stored
    // clock-rollback anchor is simply "now".
    return saveLease(
      token,
      serverTime: LicenseManager.nowProvider().toUtc().toIso8601String(),
    );
  }

  /// Decodes a license document's bytes, tolerating the encodings Windows
  /// tools produce: UTF-8 with BOM, UTF-16 LE/BE with BOM, or plain UTF-8.
  ///
  /// The `.madarlicense` file is signed over its exact text, so it must be
  /// decoded faithfully before [_extractLeaseToken] runs. Saving it from
  /// Notepad or PowerShell (which add a BOM / default to UTF-16) used to turn
  /// a valid document into "تعذّر التحقق من صحة الترخيص".
  static String decodeDocumentBytes(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes, 2, littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes, 2, littleEndian: false);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _decodeUtf16(
    List<int> bytes,
    int start, {
    required bool littleEndian,
  }) {
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  /// Pulls the JWT out of either document shape. Returns null when the input is
  /// not a plausible envelope at all.
  static String? _extractLeaseToken(String document) {
    var trimmed = document.trim();
    // U+FEFF is not Unicode whitespace in Dart, so `trim()` keeps it and the
    // envelope would be mistaken for a bare JWT.
    while (trimmed.startsWith('\uFEFF')) {
      trimmed = trimmed.substring(1).trim();
    }
    if (trimmed.isEmpty) return null;

    // Bare JWT fast path — avoids a JSON parse for the common case.
    if (!trimmed.startsWith('{')) {
      return trimmed.contains('.') ? trimmed : null;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final lease = decoded['lease'];
      if (lease is String && lease.contains('.')) return lease;
      return null;
    } catch (_) {
      return null;
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
    final now = LicenseManager.nowProvider();

    final data = SecureLicenseData(
      firstRunDate: existing?.firstRunDate ?? now,
      hardwareId: hardwareId,
      licenseJson: license.toJson(),
      lastCheckTime: now,
      sessionElapsedMs: existing?.sessionElapsedMs ?? 0,
      installCount: (existing?.installCount ?? 0) + 1,
      appVersion: existing?.appVersion ?? _currentAppVersion,
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

  /// Update session elapsed time tracking and return the resulting total ms.
  Future<int> _updateSessionTracking(SecureLicenseData current) async {
    final now = LicenseManager.nowProvider();
    final elapsed = now.difference(current.lastCheckTime).inMilliseconds;

    // Small backward drift (e.g. DST / minor clock adjustment <= 24h):
    // keep existing checkpoint and elapsed time untouched.
    if (elapsed < 0 && elapsed >= -86400000) {
      return current.sessionElapsedMs;
    }

    // Only write to disk if at least 1 minute elapsed to avoid thrashing I/O on every feature check.
    if (elapsed >= 0 && elapsed < 60000) {
      return current.sessionElapsedMs;
    }

    // Only accumulate reasonable forward session spans (< 24h).
    // Large forward jumps (>= 24h) or recoveries from an ahead clock (< -24h)
    // self-heal lastCheckTime cleanly without inflating sessionElapsedMs.
    final adjustedElapsed = (elapsed >= 60000 && elapsed < 86400000)
        ? current.sessionElapsedMs + elapsed
        : current.sessionElapsedMs;

    final updated = current.copyWith(
      lastCheckTime: now,
      sessionElapsedMs: adjustedElapsed,
    );

    await SecureLicenseStorage.write(updated);
    return adjustedElapsed;
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
        ),
      );
    } else {
      // Create new
      await SecureLicenseStorage.write(
        SecureLicenseData.create(
          firstRunDate: date,
          hardwareId: hwId,
          hardwareComponents: currentComponents.toJson(),
        ),
      );
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
