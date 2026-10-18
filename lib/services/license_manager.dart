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

List<String> _widenLegacyFeatures(List<String> raw, LicenseType type) {
  final features = <String>{...raw.map((f) => '$f'.trim()).where((f) => f.isNotEmpty)};

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
  bool get isExpired => DateTime.now().isAfter(expiryDate);

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
  /// reports 0 so the badge can never render a negative day count.
  ///
  /// A value of 0 means "less than 24 hours left OR already expired" — always
  /// read it together with [isExpired], never on its own.
  int get daysRemaining {
    if (isExpired) return 0;
    final remaining = expiryDate.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
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
        // BUG-009: resolve dashboard/issuer plan names, never throw.
        type: LicenseType.values.firstWhere(
          (e) => e.name == LicensePlans.resolveOrFallback('${licenseData['type']}'),
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
    return DateTime.now().isBefore(endsAt);
  }

  /// Reads a pre-RS256 AES license from [data] into a [License].
  ///
  /// Returns null when the payload is not in the legacy shape, cannot be
  /// decrypted with the current secret, or is not a well-formed license — the
  /// caller then falls through to the normal "no license" path.
  static License? _readLegacyLicense(SecureLicenseData data) {
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
        deviceFingerprint: '${decoded['device'] ?? ''}',
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
      legacyGraceEndsAt: DateTime.now().add(legacyGracePeriod),
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

  Future<License?> getCurrentLicense() async {
    if (LicenseConfig.isFreeVersion) {
      final data = await SecureLicenseStorage.read();
      final hardwareId = await HardwareIdService.getHardwareId();

      // FEAT-013: an app update must NOT wipe the customer's license.
      //
      // This used to call SecureLicenseStorage.clear() whenever
      // `appVersion` differed, which deleted secure_license.dat AND the paid
      // license stored inside it — so every single update cost the customer
      // their license. Worse, this branch runs for FREE_VERSION builds, so a
      // free build could destroy a paid license sitting in the same file.
      //
      // The version stamp is kept for diagnostics only: it is refreshed in
      // place, never used as a deletion trigger. `firstRunDate` is likewise
      // preserved so the 100-year window cannot be restarted by reinstalling
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
      // Recomputed on every read so a stale value can never leak across calls.
      _legacyLicenseSeen = false;
      final secureData = await SecureLicenseStorage.read();
      if (secureData != null && secureData.licenseJson != null) {
        // FEAT-014 — legacy AES bridge. `License.fromJson` below throws on a
        // pre-RS256 payload (it has no 'expiry' field), so read the legacy
        // shape first and keep the customer working during the grace window
        // instead of dropping them on the activation screen with no warning.
        if (!secureData.licenseJson!.containsKey('lease_token')) {
          final legacy = _readLegacyLicense(secureData);
          if (legacy != null) {
            _legacyLicenseSeen = true;
            // Stamp the deadline before deciding, so a legacy license that
            // has already served out its window is refused on THIS launch
            // rather than being granted a fresh 90 days.
            await _markLegacy(secureData);
            final stamped =
                (await SecureLicenseStorage.read()) ?? secureData;

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
            return null;
          }
        }
      }

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
bool _hasEveryFeature(List<String> features) =>
    features.contains('*') ||
    features.contains('all') ||
    LicenseConfig.availableFeatures.every(features.contains);

Future<bool> hasFeature(String featureName) async {
    if (LicenseConfig.isFreeVersion) return true;
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
