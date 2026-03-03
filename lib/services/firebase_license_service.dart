import 'dart:convert';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'license_manager.dart';
import '../core/utils/logger.dart';

/// نتيجة عملية التحقق / التفعيل من Firebase
enum FirebaseLicenseStatus {
  active, // نشط ✅
  inactive, // لم يُفعَّل بعد
  suspended, // موقوف ⛔
  expired, // منتهي ⌛
  revoked, // ملغي 🚫
  notFound, // غير موجود
  wrongDevice, // جهاز آخر
  offline, // لا يوجد إنترنت
}

class FirebaseLicenseResult {
  final FirebaseLicenseStatus status;
  final String message;
  final int warningCount;
  final String? suspendedReason;
  final DateTime? expiresAt;

  const FirebaseLicenseResult({
    required this.status,
    required this.message,
    this.warningCount = 0,
    this.suspendedReason,
    this.expiresAt,
  });

  bool get isAllowed => status == FirebaseLicenseStatus.active;
  bool get isSuspended => status == FirebaseLicenseStatus.suspended;
}

/// ════════════════════════════════════════════════════════════════════════
/// Firebase License Service
/// يتولى:
///  1. التفعيل الأول (Online Activation) — يسجّل الجهاز في Firestore
///  2. الـ 7-day Checkin — يتحقق أن المفتاح لا يزال نشطاً
///  3. Cache محلي — يحتفظ بنتيجة آخر تحقق لـ offline use
/// ════════════════════════════════════════════════════════════════════════
class FirebaseLicenseService {
  bool get _isWindows => Platform.isWindows;
  static const String _cachedResultKey = 'fb_license_cache';
  static const String _lastCheckinKey = 'fb_last_checkin';

  final LicenseManager _licenseManager = LicenseManager();

  // Singleton
  static final FirebaseLicenseService _instance =
      FirebaseLicenseService._internal();
  factory FirebaseLicenseService() => _instance;
  FirebaseLicenseService._internal();

  // Local activation for Windows (offline fallback)
  Future<FirebaseLicenseResult> _localActivation(String licenseKey) async {
    try {
      // Validate license locally using LicenseManager
      final validationResult = await _licenseManager.validateLicense(
        licenseKey,
      );

      if (validationResult.isValid) {
        // Save to cache as active
        await _saveCheckinCache('active', 0);
        AppLogger.i('License activated locally on Windows: $licenseKey');
        return FirebaseLicenseResult(
          status: FirebaseLicenseStatus.active,
          message: 'تم تفعيل الترخيص محلياً! 🎉 (وضع الويندوز)',
          expiresAt: validationResult.license?.expiryDate,
        );
      } else {
        return FirebaseLicenseResult(
          status: FirebaseLicenseStatus.notFound,
          message: 'مفتاح الترخيص غير صحيح.',
        );
      }
    } catch (e) {
      AppLogger.e('Local activation error: $e');
      return const FirebaseLicenseResult(
        status: FirebaseLicenseStatus.offline,
        message: 'خطأ في التفعيل المحلي.',
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // التفعيل الأول (Online Activation)
  // ════════════════════════════════════════════════════════════════════════

  /// يُستدعى عندما يُدخل العميل المفتاح لأول مرة
  Future<FirebaseLicenseResult> activateLicense(String licenseKey) async {
    // Always use local licensing since Firebase removed for Windows compatibility
    return _localActivation(licenseKey);
  }

  // ════════════════════════════════════════════════════════════════════════
  // الـ 7-Day Checkin
  // يُستدعى عند تشغيل التطبيق — إذا مضت 7 أيام منذ آخر تحقق
  // ════════════════════════════════════════════════════════════════════════

  Future<FirebaseLicenseResult> performCheckinIfNeeded(
    String licenseKey,
  ) async {
    // Always use local checkin since Firebase removed for Windows compatibility
    return _localCheckin(licenseKey);
  }

  // Local checkin for Windows (offline fallback)
  Future<FirebaseLicenseResult> _localCheckin(String licenseKey) async {
    try {
      // Check if license is still valid locally
      final isActive = await _licenseManager.isLicenseActive();
      if (isActive) {
        // Update cache timestamp
        await _saveCheckinCache('active', 0);
        return FirebaseLicenseResult(
          status: FirebaseLicenseStatus.active,
          message: 'يعمل محلياً على الويندوز ✅',
        );
      } else {
        return const FirebaseLicenseResult(
          status: FirebaseLicenseStatus.expired,
          message: 'انتهت صلاحية الترخيص.',
        );
      }
    } catch (e) {
      AppLogger.e('Local checkin error: $e');
      // إذا offline، استخدم الـ cache
      return _getCachedResult();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Local Cache — لتجنب الحاجة للإنترنت في كل تشغيل
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _saveCheckinCache(String status, int warnCount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckinKey, DateTime.now().toIso8601String());
    await prefs.setString(
      _cachedResultKey,
      jsonEncode({
        'status': status,
        'warningCount': warnCount,
        'cachedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<FirebaseLicenseResult> _getCachedResult() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheStr = prefs.getString(_cachedResultKey);
      if (cacheStr == null) {
        return const FirebaseLicenseResult(
          status: FirebaseLicenseStatus.offline,
          message: 'لا يوجد اتصال بالإنترنت ولا توجد بيانات مخزنة.',
        );
      }

      final cache = jsonDecode(cacheStr) as Map<String, dynamic>;
      final status = cache['status'] as String? ?? 'offline';
      final warnCount = (cache['warningCount'] as num?)?.toInt() ?? 0;

      if (status == 'active' || status == 'active_warned') {
        return FirebaseLicenseResult(
          status: FirebaseLicenseStatus.active,
          message: 'يعمل بدون إنترنت (آخر تحقق: ${_daysAgoText()})',
          warningCount: warnCount,
        );
      }

      if (status == 'suspended') {
        return FirebaseLicenseResult(
          status: FirebaseLicenseStatus.suspended,
          message: 'الترخيص موقوف.',
          warningCount: warnCount,
        );
      }

      return const FirebaseLicenseResult(
        status: FirebaseLicenseStatus.offline,
        message: 'لا يوجد اتصال بالإنترنت.',
      );
    } catch (e) {
      return const FirebaseLicenseResult(
        status: FirebaseLicenseStatus.offline,
        message: 'لا يوجد اتصال بالإنترنت.',
      );
    }
  }

  /// Returns how many days since last checkin (sync, uses cached value)
  String _daysAgoText() {
    return 'سابقاً';
  }

  /// مسح الـ cache (عند تغيير المفتاح أو الخروج)
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedResultKey);
    await prefs.remove(_lastCheckinKey);
  }
}
