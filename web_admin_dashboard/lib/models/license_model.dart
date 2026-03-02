import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// License Status
enum LicenseStatus {
  inactive, // لم يُفعَّل بعد
  active, // نشط
  suspended, // موقوف (تحذير أو إيقاف)
  expired, // منتهي
  revoked, // ملغي
  trial, // تجريبي
}

/// Subscription Duration
enum SubscriptionDuration {
  trial, // 7 أيام تجريبي
  monthly, // شهري
  yearly, // سنوي
  lifetime, // مدى الحياة
}

/// License Record - سجل الترخيص
class LicenseRecord {
  final String id;
  final String licenseKey;
  final String clientId;
  final String clientName;
  final String packageType; // basic, standard, professional
  final SubscriptionDuration duration;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? activatedAt;
  final String? hardwareId;
  final LicenseStatus status;
  final double price;
  final String? notes;
  // ─── حقول جديدة للتحكم الأمني ───
  final DateTime? lastCheckin; // آخر تحقق أونلاين
  final int warningCount; // عدد التحذيرات المُرسلة
  final DateTime? suspendedAt; // تاريخ الإيقاف
  final String? suspendedReason; // سبب الإيقاف

  LicenseRecord({
    required this.id,
    required this.licenseKey,
    required this.clientId,
    required this.clientName,
    required this.packageType,
    required this.duration,
    required this.createdAt,
    required this.expiresAt,
    this.activatedAt,
    this.hardwareId,
    this.status = LicenseStatus.inactive,
    required this.price,
    this.notes,
    this.lastCheckin,
    this.warningCount = 0,
    this.suspendedAt,
    this.suspendedReason,
  });

  static SubscriptionDuration _parseDuration(dynamic raw) {
    if (raw is int) {
      if (raw >= 0 && raw < SubscriptionDuration.values.length) {
        return SubscriptionDuration.values[raw];
      }
      return SubscriptionDuration.monthly;
    }

    final name = raw?.toString() ?? 'monthly';
    return SubscriptionDuration.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SubscriptionDuration.monthly,
    );
  }

  static LicenseStatus _parseStatus(dynamic raw) {
    if (raw is int) {
      if (raw >= 0 && raw < LicenseStatus.values.length) {
        return LicenseStatus.values[raw];
      }
      return LicenseStatus.active;
    }

    final name = raw?.toString() ?? 'active';
    return LicenseStatus.values.firstWhere(
      (e) => e.name == name,
      orElse: () => LicenseStatus.active,
    );
  }

  static DateTime _parseDate(dynamic raw, DateTime fallback) {
    if (raw == null) return fallback;

    if (raw is DateTime) return raw;

    if (raw is Timestamp) {
      return raw.toDate();
    }

    if (raw is String) {
      return DateTime.tryParse(raw) ?? fallback;
    }

    return fallback;
  }

  factory LicenseRecord.fromJson(Map<String, dynamic> json) {
    return LicenseRecord(
      id: json['id'] as String? ?? '',
      licenseKey: json['licenseKey'] as String? ?? '',
      clientId: json['clientId'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      packageType: json['packageType'] as String? ?? 'basic',
      duration: _parseDuration(json['duration']),
      createdAt: _parseDate(json['createdAt'], DateTime.now()),
      expiresAt: _parseDate(
          json['expiresAt'], DateTime.now().add(const Duration(days: 30))),
      activatedAt: json['activatedAt'] != null
          ? _parseDate(json['activatedAt'], DateTime.now())
          : null,
      hardwareId: json['hardwareId'] as String?,
      status: _parseStatus(json['status']),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String?,
      lastCheckin: json['lastCheckin'] != null
          ? _parseDate(json['lastCheckin'], DateTime.now())
          : null,
      warningCount: (json['warningCount'] as num?)?.toInt() ?? 0,
      suspendedAt: json['suspendedAt'] != null
          ? _parseDate(json['suspendedAt'], DateTime.now())
          : null,
      suspendedReason: json['suspendedReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'licenseKey': licenseKey,
      'clientId': clientId,
      'clientName': clientName,
      'packageType': packageType,
      'duration': duration.name,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'activatedAt': activatedAt?.toIso8601String(),
      'hardwareId': hardwareId,
      'status': status.name,
      'price': price,
      'notes': notes,
      'lastCheckin': lastCheckin?.toIso8601String(),
      'warningCount': warningCount,
      'suspendedAt': suspendedAt?.toIso8601String(),
      'suspendedReason': suspendedReason,
    };
  }

  LicenseRecord copyWith({
    String? id,
    String? licenseKey,
    String? clientId,
    String? clientName,
    String? packageType,
    SubscriptionDuration? duration,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? activatedAt,
    String? hardwareId,
    LicenseStatus? status,
    double? price,
    String? notes,
    DateTime? lastCheckin,
    int? warningCount,
    DateTime? suspendedAt,
    String? suspendedReason,
  }) {
    return LicenseRecord(
      id: id ?? this.id,
      licenseKey: licenseKey ?? this.licenseKey,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      packageType: packageType ?? this.packageType,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      activatedAt: activatedAt ?? this.activatedAt,
      hardwareId: hardwareId ?? this.hardwareId,
      status: status ?? this.status,
      price: price ?? this.price,
      notes: notes ?? this.notes,
      lastCheckin: lastCheckin ?? this.lastCheckin,
      warningCount: warningCount ?? this.warningCount,
      suspendedAt: suspendedAt ?? this.suspendedAt,
      suspendedReason: suspendedReason ?? this.suspendedReason,
    );
  }

  /// Check if license is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Days remaining until expiry
  int get daysRemaining {
    final difference = expiresAt.difference(DateTime.now());
    return difference.inDays;
  }

  /// Check if license is expiring soon (within 7 days)
  bool get isExpiringSoon => daysRemaining <= 7 && daysRemaining > 0;

  /// Get status display name in Arabic
  String get statusDisplayName {
    switch (status) {
      case LicenseStatus.inactive:
        return 'غير مفعّل';
      case LicenseStatus.active:
        return 'نشط';
      case LicenseStatus.suspended:
        return 'موقوف';
      case LicenseStatus.expired:
        return 'منتهي';
      case LicenseStatus.revoked:
        return 'ملغي';
      case LicenseStatus.trial:
        return 'تجريبي';
    }
  }

  /// Get duration display name in Arabic
  String get durationDisplayName {
    switch (duration) {
      case SubscriptionDuration.trial:
        return 'تجريبي (7 أيام)';
      case SubscriptionDuration.monthly:
        return 'شهري';
      case SubscriptionDuration.yearly:
        return 'سنوي';
      case SubscriptionDuration.lifetime:
        return 'مدى الحياة';
    }
  }

  /// Get package display name in Arabic
  String get packageDisplayName {
    switch (packageType) {
      case 'basic':
        return 'أساسي';
      case 'standard':
        return 'قياسي';
      case 'professional':
        return 'احترافي';
      default:
        return packageType;
    }
  }
}

/// License Key Generator
class LicenseKeyGenerator {
  static const _uuid = Uuid();

  /// Generate a new license key
  /// Format: [PKG]-[RAND1]-[YEAR]-[RAND2]-[CHECKSUM]
  /// Example: BAS-A3F2-2026-B4C8-9D1E
  static String generateKey({
    required String packageType,
    required DateTime expiresAt,
  }) {
    // Package code
    final pkgCode = _getPackageCode(packageType);

    // Random components
    final rand1 = _uuid.v4().substring(0, 4).toUpperCase();
    final rand2 = _uuid.v4().substring(0, 4).toUpperCase();

    // Year
    final year = expiresAt.year.toString();

    // Create checksum
    final dataForChecksum = '$pkgCode$rand1$year$rand2';
    final checksum = _generateChecksum(dataForChecksum);

    return '$pkgCode-$rand1-$year-$rand2-$checksum';
  }

  /// Get package code from package type
  static String _getPackageCode(String packageType) {
    switch (packageType) {
      case 'basic':
        return 'BAS';
      case 'standard':
        return 'STD';
      case 'professional':
        return 'PRO';
      default:
        return 'BAS';
    }
  }

  /// Generate checksum for validation
  static String _generateChecksum(String data) {
    final bytes = utf8.encode(data);
    final digest = md5.convert(bytes);
    return digest.toString().substring(0, 4).toUpperCase();
  }

  /// Validate license key format
  static bool validateKeyFormat(String key) {
    // Format: XXX-XXXX-XXXX-XXXX-XXXX
    final regex =
        RegExp(r'^[A-Z]{3}-[A-Z0-9]{4}-\d{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$');
    return regex.hasMatch(key);
  }

  /// Get expiry date based on duration
  static DateTime getExpiryDate(SubscriptionDuration duration) {
    final now = DateTime.now();
    switch (duration) {
      case SubscriptionDuration.trial:
        return now.add(const Duration(days: 7));
      case SubscriptionDuration.monthly:
        return DateTime(now.year, now.month + 1, now.day);
      case SubscriptionDuration.yearly:
        return DateTime(now.year + 1, now.month, now.day);
      case SubscriptionDuration.lifetime:
        return DateTime(now.year + 99, now.month, now.day); // 99 years
    }
  }

  /// Get price based on package and duration
  static double getPrice(String packageType, SubscriptionDuration duration) {
    final basePrices = {
      'basic': 250.0,
      'standard': 400.0,
      'professional': 600.0,
    };

    final basePrice = basePrices[packageType] ?? 250.0;

    switch (duration) {
      case SubscriptionDuration.trial:
        return 0.0; // Free trial
      case SubscriptionDuration.monthly:
        return basePrice;
      case SubscriptionDuration.yearly:
        return basePrice * 10; // 10 months price (2 free)
      case SubscriptionDuration.lifetime:
        return basePrice * 24; // 2 years price
    }
  }
}
