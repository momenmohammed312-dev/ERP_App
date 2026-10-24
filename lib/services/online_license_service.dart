import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'license_manager.dart';
import 'hardware_id_service.dart';
import '../config/license_config.dart';
import '../core/utils/logger.dart';

enum OnlineLicenseStatus {
  active,
  suspended,
  expired,
  revoked,
  notFound,
  wrongDevice,
  offline,
}

class OnlineLicenseResult {
  final OnlineLicenseStatus status;
  final String message;
  final int warningCount;
  final String? suspendedReason;
  final DateTime? expiresAt;

  const OnlineLicenseResult({
    required this.status,
    required this.message,
    this.warningCount = 0,
    this.suspendedReason,
    this.expiresAt,
  });

  bool get isAllowed => status == OnlineLicenseStatus.active;
  bool get isSuspended => status == OnlineLicenseStatus.suspended;

  /// True when the SERVER explicitly refused the license (as opposed to
  /// "no internet" or a server glitch). Only these answers may lock the app.
  bool get isDefinitiveRejection =>
      status == OnlineLicenseStatus.suspended ||
      status == OnlineLicenseStatus.expired ||
      status == OnlineLicenseStatus.revoked ||
      status == OnlineLicenseStatus.notFound ||
      status == OnlineLicenseStatus.wrongDevice;
}

/// Talks to the Supabase `license_api` Edge Function.
///  - activate: first activation, binds this device and returns a signed lease
///  - checkin : renews the lease (at most once a day, never blocks offline use)
/// The lease itself is verified/stored by [LicenseManager.saveLease].
class OnlineLicenseService {
  static const String _lastCheckinKey = 'online_last_checkin';
  static const Duration _checkinInterval = Duration(days: 1);
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// Override with --dart-define=LICENSE_API_URL=...
  static const String _apiUrl = String.fromEnvironment(
    'LICENSE_API_URL',
    defaultValue: '',
  );

  /// Test seams (null in production).
  @visibleForTesting
  static http.Client? httpClientOverride;
  @visibleForTesting
  static String? apiUrlOverride;

  static String get _url => apiUrlOverride ?? _apiUrl;


  final LicenseManager _licenseManager = LicenseManager();

  static final OnlineLicenseService _instance =
      OnlineLicenseService._internal();
  factory OnlineLicenseService() => _instance;
  OnlineLicenseService._internal();

  /// First activation with a key typed by the customer.
  Future<OnlineLicenseResult> activateLicense(String licenseKey) {
    return _callLicenseApi(licenseKey, 'activate');
  }

  /// Background renewal. Skips the network when the last check-in is recent.
  Future<OnlineLicenseResult> performCheckinIfNeeded(String licenseKey) async {
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_lastCheckinKey) ?? '');
    if (last != null && DateTime.now().difference(last) < _checkinInterval) {
      return const OnlineLicenseResult(
        status: OnlineLicenseStatus.active,
        message: 'تم التحقق مؤخراً',
      );
    }
    return _callLicenseApi(licenseKey, 'checkin');
  }

  Future<OnlineLicenseResult> _callLicenseApi(
    String licenseKey,
    String action,
  ) async {
    if (_url.isEmpty) {
      AppLogger.e('LICENSE_API_URL not injected via --dart-define');
      return const OnlineLicenseResult(
        status: OnlineLicenseStatus.offline,
        message: 'خادم التراخيص غير مُعدّ في هذه النسخة.',
      );
    }

    try {
      final post = httpClientOverride?.post ?? http.post;
      final response = await post(
            Uri.parse(_url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': action,
              'license_key': licenseKey,
              'machine_guid': await HardwareIdService.getMachineGuid(),
              'install_uuid': await HardwareIdService.getInstallUuid(),
              'device_name': await HardwareIdService.getDeviceName(),
              'platform': await HardwareIdService.getPlatformName(),
              'app_version': LicenseConfig.appVersion,
            }),
          )
          .timeout(_requestTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final saved = await _licenseManager.saveLease(
          data['lease_token'] as String,
          serverTime: data['server_time'] as String?,
        );
        if (!saved.isValid) {
          return OnlineLicenseResult(
            status: OnlineLicenseStatus.offline,
            message: saved.errorMessage ?? 'تعذر حفظ الترخيص.',
          );
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _lastCheckinKey,
          DateTime.now().toIso8601String(),
        );
        return OnlineLicenseResult(
          status: OnlineLicenseStatus.active,
          message: 'تم التحقق من الترخيص بنجاح ✅',
          expiresAt: DateTime.tryParse('${data['expires_at']}'),
        );
      }

      final errorMsg = '${data['error'] ?? 'Unknown error'}';
      AppLogger.w('License API ${response.statusCode}: $errorMsg');
      final result = _mapRejection(response.statusCode, errorMsg);

      // The server explicitly refused a license we already hold (suspended,
      // expired, device removed...) → drop the lease so the NEXT launch asks
      // for activation. Never done for network errors or 5xx glitches.
      if (action == 'checkin' && result.isDefinitiveRejection) {
        await _licenseManager.deactivate();
      }
      return result;
    } catch (e) {
      // No internet / timeout / bad response: keep working on the stored
      // lease. For a first activation there is nothing to fall back to.
      AppLogger.w('License API unreachable: $e');
      return OnlineLicenseResult(
        status: OnlineLicenseStatus.offline,
        message: action == 'activate'
            ? 'تعذر الاتصال بالإنترنت. التفعيل الأول يحتاج اتصالاً بالإنترنت.'
            : 'لا يوجد اتصال بالإنترنت.',
      );
    }
  }

  /// Maps a server refusal to a status. Only 403/404 are definitive; anything
  /// else (500, malformed...) is treated as a temporary problem.
  OnlineLicenseResult _mapRejection(int code, String msg) {
    if (code != 403 && code != 404) {
      return OnlineLicenseResult(
        status: OnlineLicenseStatus.offline,
        message: 'تعذر التحقق من الترخيص حالياً. حاول لاحقاً.',
      );
    }
    final m = msg.toLowerCase();
    if (m.contains('suspended')) {
      return OnlineLicenseResult(
        status: OnlineLicenseStatus.suspended,
        message: 'تم إيقاف هذا الترخيص. تواصل مع الدعم.',
        suspendedReason: 'تم إيقاف ترخيص المنظومة من قِبل المزود.',
      );
    }
    if (m.contains('revoked')) {
      return const OnlineLicenseResult(
        status: OnlineLicenseStatus.revoked,
        message: 'تم إلغاء هذا الترخيص. تواصل مع الدعم.',
      );
    }
    if (m.contains('expired')) {
      return const OnlineLicenseResult(
        status: OnlineLicenseStatus.expired,
        message: 'انتهت صلاحية الترخيص.',
      );
    }
    if (m.contains('limit reached') || m.contains('blocked')) {
      return const OnlineLicenseResult(
        status: OnlineLicenseStatus.wrongDevice,
        message:
            'هذا الترخيص مُفعَّل على جهاز آخر. تواصل مع الدعم لنقله لهذا الجهاز.',
      );
    }
    return const OnlineLicenseResult(
      status: OnlineLicenseStatus.notFound,
      message: 'مفتاح الترخيص غير صحيح.',
    );
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckinKey);
  }
}
