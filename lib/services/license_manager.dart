import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter/foundation.dart';

enum LicenseType {
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
  });

  bool get isExpired => DateTime.now().isAfter(expiryDate);
  bool get isValid => !isExpired;

  int get daysRemaining {
    if (isExpired) return 0;
    return expiryDate.difference(DateTime.now()).inDays;
  }

  String get licenseType => type.toString().split('.').last;

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
    );
  }
}

class LicenseManager {
  static const String _storageKey = 'app_license';
  static const String _secretKey = 'POS-SaaS-2026-PROD-SECURE-K3Y-F0R-L1C3NS3!';

  // Singleton
  static final LicenseManager _instance = LicenseManager._internal();
  factory LicenseManager() => _instance;
  LicenseManager._internal();

  // ════════════════════════════════════════════════════════════════════
  // توليد بصمة الجهاز (Device Fingerprinting)
  // ════════════════════════════════════════════════════════════════════

  Future<String> generateDeviceFingerprint() async {
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
      }

      // تشفير البصمة
      final bytes = utf8.encode(fingerprint);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      throw Exception('فشل في توليد بصمة الجهاز: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // توليد مفتاح ترخيص (للاستخدام من طرفك فقط)
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
      // فصل البيانات المشفرة والتوقيع
      final parts = licenseKey.split('.');
      if (parts.length != 2) {
        return LicenseValidationResult.invalid('صيغة مفتاح الترخيص غير صحيحة');
      }

      final encryptedData = parts[0];
      final providedSignature = parts[1];

      // التحقق من التوقيع
      final calculatedSignature = _generateSignature(encryptedData);
      if (calculatedSignature != providedSignature) {
        return LicenseValidationResult.invalid(
          'مفتاح الترخيص غير صحيح (توقيع خاطئ)',
        );
      }

      // فك التشفير
      final decryptedJson = _decrypt(encryptedData);
      final licenseData = jsonDecode(decryptedJson) as Map<String, dynamic>;

      // التحقق من بصمة الجهاز
      final currentFingerprint = await generateDeviceFingerprint();
      if (licenseData['device'] != currentFingerprint) {
        return LicenseValidationResult.invalid(
          'هذا الترخيص غير صالح لهذا الجهاز',
        );
      }

      // التحقق من تاريخ الانتهاء
      final expiryDate = DateTime.parse(licenseData['expiry']);
      if (DateTime.now().isAfter(expiryDate)) {
        return LicenseValidationResult.expired(
          'انتهت صلاحية الترخيص في ${_formatDate(expiryDate)}',
        );
      }

      // إنشاء كائن License
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
      );

      // حفظ الترخيص
      await _saveLicense(license);

      return LicenseValidationResult.valid(license);
    } catch (e) {
      return LicenseValidationResult.invalid('خطأ في التحقق من الترخيص: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // التحقق من الترخيص المحفوظ
  // ════════════════════════════════════════════════════════════════════

  Future<bool> isLicenseActive() async {
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

  Future<License?> getCurrentLicense() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final licenseJson = prefs.getString(_storageKey);

      if (licenseJson == null) return null;

      final data = jsonDecode(licenseJson);
      return License.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // التحقق من الميزة
  // ════════════════════════════════════════════════════════════════════

  Future<bool> hasFeature(String featureName) async {
    final license = await getCurrentLicense();
    if (license == null || !license.isValid) return false;
    return license.features.contains(featureName);
  }

  // ════════════════════════════════════════════════════════════════════
  // التحقق من عدد المستخدمين
  // ════════════════════════════════════════════════════════════════════

  Future<bool> canAddUser(int currentUserCount) async {
    final license = await getCurrentLicense();
    if (license == null || !license.isValid) return false;
    return currentUserCount < license.maxUsers;
  }

  // ════════════════════════════════════════════════════════════════════
  // إلغاء التفعيل
  // ════════════════════════════════════════════════════════════════════

  Future<void> deactivate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  // ════════════════════════════════════════════════════════════════════
  // دوال مساعدة خاصة
  // ════════════════════════════════════════════════════════════════════

  Future<void> _saveLicense(License license) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(license.toJson()));
  }

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

// ════════════════════════════════════════════════════════════════════════
// 3. نتيجة التحقق
// ════════════════════════════════════════════════════════════════════════

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
