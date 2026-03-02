import 'dart:convert';
import 'dart:io' as io;
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'license_manager.dart';
import '../core/utils/logger.dart';

/// نتيجة عملية التحقق / التفعيل من Firebase
enum FirebaseLicenseStatus {
  active,    // نشط ✅
  inactive,  // لم يُفعَّل بعد
  suspended, // موقوف ⛔
  expired,   // منتهي ⌛
  revoked,   // ملغي 🚫
  notFound,  // غير موجود
  wrongDevice, // جهاز آخر
  offline,   // لا يوجد إنترنت
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
  bool get _isWindows => io.Platform.isWindows;
  static const String _collection = 'licenses';
  static const String _cachedResultKey = 'fb_license_cache';
  static const String _lastCheckinKey  = 'fb_last_checkin';
  static const int    _checkinIntervalDays = 7;

  final LicenseManager _licenseManager = LicenseManager();
  // Lightweight placeholder for Firestore to allow offline Windows runs
  dynamic _firestore;

  // Singleton
  static final FirebaseLicenseService _instance = FirebaseLicenseService._internal();
  factory FirebaseLicenseService() => _instance;
  FirebaseLicenseService._internal();


  void _ensureFirestore() {
    // In offline Windows mode, Firestore is not available. This method is a no-op.
  }

  // Local activation for Windows (offline fallback)
  Future<FirebaseLicenseResult> _localActivation(String licenseKey) async {
    try {
      // Validate license locally using LicenseManager
      final validationResult = await _licenseManager.validateLicense(licenseKey);
      
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

  Future<FirebaseLicenseResult> performCheckinIfNeeded(String licenseKey) async {
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
      return _getCachedResult();
    }
  }

  Future<FirebaseLicenseResult> _performCheckin(String licenseKey) async {
    if (_isWindows) {
      return _getCachedResult();
    }
    try {
      _ensureFirestore();
      final machineId = await _licenseManager.generateDeviceFingerprint();

      final query = await _firestore!
          .collection(_collection)
          .where('licenseKey', isEqualTo: licenseKey)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return const FirebaseLicenseResult(
          status: FirebaseLicenseStatus.notFound,
          message: 'مفتاح الترخيص غير موجود.',
        );
      }

      final doc  = query.docs.first;
      final data = doc.data();
      final currentStatus  = data['status'] as String? ?? 'inactive';
      final savedMachineId = data['hardwareId'] as String?;
      final warnCount = (data['warningCount'] as num?)?.toInt() ?? 0;

      // تحقق من الجهاز
      if (savedMachineId != null && savedMachineId != machineId) {
        await _saveCheckinCache('wrongDevice', 0);
        return const FirebaseLicenseResult(
          status: FirebaseLicenseStatus.wrongDevice,
          message: 'هذا الجهاز غير مرتبط بهذا الترخيص.',
        );
      }

      if (currentStatus == 'suspended') {
        final reason = data['suspendedReason'] as String? ?? 'تم الإيقاف';
        await _saveCheckinCache('suspended', warnCount);
        return FirebaseLicenseResult(
          status: FirebaseLicenseStatus.suspended,
          message: reason,
          warningCount: warnCount,
          suspendedReason: reason,
        );
      }

      if (currentStatus == 'revoked') {
        await _saveCheckinCache('revoked', 0);
        return const FirebaseLicenseResult(
          status: FirebaseLicenseStatus.revoked,
          message: 'تم إلغاء هذا الترخيص.',
        );
      }

      // تحقق من التحذيرات (warning فقط، ليس suspended)
      // إذا warningCount زاد، نُظهر تحذيراً لكن نسمح بالعمل
      if (currentStatus == 'active' && warnCount > 0) {
        // تحديث lastCheckin
        await (_firestore?.collection(_collection).doc(doc.id).update({
          'lastCheckin': DateTime.now(),
        }) ?? Future.value(null));
        await _saveCheckinCache('active_warned', warnCount);
        AppLogger.w('License has $warnCount warning(s)');
        return FirebaseLicenseResult(
          status: FirebaseLicenseStatus.active, // لا يزال مسموحاً
          message: 'تحذير: تم إرسال $warnCount تحذير/ات من المزود',
          warningCount: warnCount,
        );
      }

      // كل شيء تمام → تحديث lastCheckin
      await (_firestore?.collection(_collection).doc(doc.id).update({
        'lastCheckin': DateTime.now(),
      }) ?? Future.value(null));
      await _saveCheckinCache('active', 0);

      return FirebaseLicenseResult(
        status: FirebaseLicenseStatus.active,
        message: 'الترخيص نشط ✅',
        expiresAt: _parseTimestamp(data['expiresAt']),
      );
    } catch (e) {
      AppLogger.e('Firebase checkin error: $e');
      // إذا offline، استخدم الـ cache
      return _getCachedResult();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Local Cache — لتجنب الحاجة للإنترنت في كل تشغيل
  // ════════════════════════════════════════════════════════════════════════

  Future<bool> _needsCheckin() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckinStr = prefs.getString(_lastCheckinKey);
    if (lastCheckinStr == null) return true;

    final lastCheckin = DateTime.tryParse(lastCheckinStr);
    if (lastCheckin == null) return true;

    final daysSince = DateTime.now().difference(lastCheckin).inDays;
    return daysSince >= _checkinIntervalDays;
  }

  Future<void> _saveCheckinCache(String status, int warnCount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckinKey, DateTime.now().toIso8601String());
    await prefs.setString(_cachedResultKey, jsonEncode({
      'status': status,
      'warningCount': warnCount,
      'cachedAt': DateTime.now().toIso8601String(),
    }));
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

  DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// مسح الـ cache (عند تغيير المفتاح أو الخروج)
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedResultKey);
    await prefs.remove(_lastCheckinKey);
  }
}
