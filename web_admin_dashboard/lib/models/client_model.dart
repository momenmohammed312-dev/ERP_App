/// Client Model - يمثل العميل (صاحب المحل)
class ClientModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String packageType; // basic, standard, professional
  final DateTime createdAt;
  final String? notes;
  final String? currentLicenseId;
  final double totalPaid;
  final bool isActive;

  ClientModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    this.address = '',
    required this.packageType,
    required this.createdAt,
    this.notes,
    this.currentLicenseId,
    this.totalPaid = 0.0,
    this.isActive = true,
  });

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      address: json['address'] as String? ?? '',
      packageType: json['packageType'] as String? ?? 'basic',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      notes: json['notes'] as String?,
      currentLicenseId: json['currentLicenseId'] as String?,
      totalPaid: (json['totalPaid'] as num?)?.toDouble() ?? 0.0,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'packageType': packageType,
      'createdAt': createdAt.toIso8601String(),
      'notes': notes,
      'currentLicenseId': currentLicenseId,
      'totalPaid': totalPaid,
      'isActive': isActive,
    };
  }

  ClientModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? packageType,
    DateTime? createdAt,
    String? notes,
    String? currentLicenseId,
    double? totalPaid,
    bool? isActive,
  }) {
    return ClientModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      packageType: packageType ?? this.packageType,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
      currentLicenseId: currentLicenseId ?? this.currentLicenseId,
      totalPaid: totalPaid ?? this.totalPaid,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Get package display name in Arabic
  String get packageDisplayName {
    switch (packageType) {
      case 'basic':
        return 'أساسي (250 ج)';
      case 'standard':
        return 'قياسي (400 ج)';
      case 'professional':
        return 'احترافي (600 ج)';
      default:
        return packageType;
    }
  }

  /// Get package price based on duration
  double getPackagePrice(String duration) {
    final basePrices = {
      'basic': 250.0,
      'standard': 400.0,
      'professional': 600.0,
    };

    final basePrice = basePrices[packageType] ?? 250.0;

    switch (duration) {
      case 'monthly':
        return basePrice;
      case 'yearly':
        return basePrice * 10; // 10 months price for yearly (2 months free)
      case 'lifetime':
        return basePrice * 24; // 2 years price for lifetime
      default:
        return basePrice;
    }
  }
}
