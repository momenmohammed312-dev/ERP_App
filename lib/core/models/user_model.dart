// ════════════════════════════════════════════════════════════════════════
// نظام الأدوار والصلاحيات - POS SaaS Offline
// ════════════════════════════════════════════════════════════════════════

import 'dart:convert';

// ════════════════════════════════════════════════════════════════════════
// 1. التعريفات الأساسية
// ════════════════════════════════════════════════════════════════════════

enum UserRole {
  admin, // المدير - كل الصلاحيات
  manager, // مدير - معظم الصلاحيات
  cashier, // كاشير - البيع فقط
  accountant, // محاسب - التقارير والحسابات
  viewer, // مشاهد - قراءة فقط
}

enum Permission {
  // المبيعات
  viewSales,
  createSale,
  editSale,
  deleteSale,
  refundSale,
  createSales, // Added for test compatibility
  // المنتجات
  viewProducts,
  createProduct,
  editProduct,
  deleteProduct,
  adjustStock,

  // العملاء
  viewCustomers,
  createCustomer,
  editCustomer,
  deleteCustomer,
  viewCustomerBalance,

  // الموردين
  viewSuppliers,
  createSupplier,
  editSupplier,
  deleteSupplier,
  viewSupplierBalance,

  // المشتريات
  viewPurchases,
  createPurchase,
  editPurchase,
  deletePurchase,
  approvePurchase,

  // المخزون
  viewInventory,
  adjustInventory,
  transferInventory,
  conductStockTake,

  // التقارير
  viewReports,
  exportReports,
  viewFinancialReports,
  viewInventoryReports,

  // المستخدمين
  viewUsers,
  createUser,
  editUser,
  deleteUser,
  assignRoles,
  manageUsers,
  lockUser,
  unlockUser,

  // الإعدادات
  viewSettings,
  editSettings,
  manageLicense,
  viewAuditLog,

  // النسخ الاحتياطي
  createBackup,
  restoreBackup,
  deleteBackup,

  // المالية
  openDay,
  closeDay,
  viewCashDrawer,
  adjustCashDrawer,
}

// ════════════════════════════════════════════════════════════════════════
// 2. نموذج المستخدم
// ════════════════════════════════════════════════════════════════════════

class User {
  final int? id;
  final String username;
  final String passwordHash;
  final String fullName;
  final String? email;
  final String? phone;
  final UserRole role;
  final List<Permission> customPermissions;
  final bool isActive;
  final int failedAttempts;
  final DateTime? lockedUntil;
  final DateTime? lastLogin;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? createdBy;
  final int? updatedBy;

  User({
    this.id,
    required this.username,
    required this.passwordHash,
    required this.fullName,
    this.email,
    this.phone,
    required this.role,
    this.customPermissions = const [],
    this.isActive = true,
    this.failedAttempts = 0,
    this.lockedUntil,
    this.lastLogin,
    required this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  bool get isLocked {
    if (lockedUntil == null) return false;
    return DateTime.now().isBefore(lockedUntil!);
  }

  /// Check if user has specific permission
  bool hasPermission(Permission permission) {
    // Admin has all permissions
    if (role == UserRole.admin) return true;

    // Check custom permissions first
    if (customPermissions.contains(permission)) return true;

    // Check default role permissions
    final rolePermissions = PermissionMatrix.getPermissionsForRole(role);
    return rolePermissions.contains(permission);
  }

  /// Convert User to JSON
  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'passwordHash': passwordHash,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'role': role.index,
      'customPermissions': customPermissions.map((p) => p.name).toList(),
      'isActive': isActive,
      'failedAttempts': failedAttempts,
      'lockedUntil': lockedUntil?.toIso8601String(),
      'lastLogin': lastLogin?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'createdBy': createdBy,
      'updatedBy': updatedBy,
    };
  }

  /// Create User from JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      username: json['username'],
      passwordHash: json['passwordHash'],
      fullName: json['fullName'],
      email: json['email'],
      phone: json['phone'],
      role: UserRole.values[json['role']],
      customPermissions:
          (json['customPermissions'] as List<dynamic>?)
              ?.map((p) => Permission.values.firstWhere((e) => e.name == p))
              .toList() ??
          [],
      isActive: json['isActive'] ?? true,
      failedAttempts: json['failedAttempts'] ?? 0,
      lockedUntil: json['lockedUntil'] != null
          ? DateTime.parse(json['lockedUntil'])
          : null,
      lastLogin: json['lastLogin'] != null
          ? DateTime.parse(json['lastLogin'])
          : null,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
      createdBy: json['createdBy'],
      updatedBy: json['updatedBy'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password_hash': passwordHash,
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'role': role.toString().split('.').last,
      'custom_permissions': jsonEncode(
        customPermissions.map((p) => p.toString().split('.').last).toList(),
      ),
      'is_active': isActive ? 1 : 0,
      'failed_attempts': failedAttempts,
      'locked_until': lockedUntil?.toIso8601String(),
      'last_login': lastLogin?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'created_by': createdBy,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'],
      passwordHash: map['password_hash'],
      fullName: map['full_name'],
      email: map['email'],
      phone: map['phone'],
      role: UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == map['role'],
      ),
      customPermissions: _parsePermissions(map['custom_permissions']),
      isActive: map['is_active'] == 1,
      failedAttempts: map['failed_attempts'] ?? 0,
      lockedUntil: map['locked_until'] != null
          ? DateTime.parse(map['locked_until'])
          : null,
      lastLogin: map['last_login'] != null
          ? DateTime.parse(map['last_login'])
          : null,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : null,
      createdBy: map['created_by'],
    );
  }

  static List<Permission> _parsePermissions(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map(
            (p) => Permission.values.firstWhere(
              (e) => e.toString().split('.').last == p,
            ),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  User copyWith({
    int? id,
    String? username,
    String? passwordHash,
    String? fullName,
    String? email,
    String? phone,
    UserRole? role,
    List<Permission>? customPermissions,
    bool? isActive,
    int? failedAttempts,
    DateTime? lockedUntil,
    DateTime? lastLogin,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? createdBy,
    int? updatedBy,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      customPermissions: customPermissions ?? this.customPermissions,
      isActive: isActive ?? this.isActive,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: lockedUntil ?? this.lockedUntil,
      lastLogin: lastLogin ?? this.lastLogin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 3. مصفوفة الصلاحيات الافتراضية
// ════════════════════════════════════════════════════════════════════════

class PermissionMatrix {
  static final Map<UserRole, List<Permission>> defaultPermissions = {
    // المدير - كل الصلاحيات
    UserRole.admin: Permission.values,

    // المدير - كل شيء ما عدا إدارة المستخدمين والترخيص
    UserRole.manager: [
      // المبيعات
      Permission.viewSales,
      Permission.createSale,
      Permission.editSale,
      Permission.deleteSale,
      Permission.refundSale,

      // المنتجات
      Permission.viewProducts,
      Permission.createProduct,
      Permission.editProduct,
      Permission.deleteProduct,
      Permission.adjustStock,

      // العملاء
      Permission.viewCustomers,
      Permission.createCustomer,
      Permission.editCustomer,
      Permission.deleteCustomer,
      Permission.viewCustomerBalance,

      // الموردين
      Permission.viewSuppliers,
      Permission.createSupplier,
      Permission.editSupplier,
      Permission.deleteSupplier,
      Permission.viewSupplierBalance,

      // المشتريات
      Permission.viewPurchases,
      Permission.createPurchase,
      Permission.editPurchase,
      Permission.deletePurchase,
      Permission.approvePurchase,

      // المخزون
      Permission.viewInventory,
      Permission.adjustInventory,
      Permission.transferInventory,
      Permission.conductStockTake,

      // التقارير
      Permission.viewReports,
      Permission.exportReports,
      Permission.viewFinancialReports,
      Permission.viewInventoryReports,

      // الإعدادات
      Permission.viewSettings,
      Permission.editSettings,

      // النسخ الاحتياطي
      Permission.createBackup,
      Permission.restoreBackup,

      // المالية
      Permission.openDay,
      Permission.closeDay,
      Permission.viewCashDrawer,
      Permission.adjustCashDrawer,
    ],

    // الكاشير - البيع والعرض فقط
    UserRole.cashier: [
      Permission.viewSales,
      Permission.createSale,
      Permission.viewProducts,
      Permission.viewCustomers,
      Permission.createCustomer,
      Permission.viewInventory,
    ],

    // المحاسب - التقارير والحسابات
    UserRole.accountant: [
      Permission.viewSales,
      Permission.viewProducts,
      Permission.viewCustomers,
      Permission.viewCustomerBalance,
      Permission.viewSuppliers,
      Permission.viewSupplierBalance,
      Permission.viewPurchases,
      Permission.viewInventory,
      Permission.viewReports,
      Permission.exportReports,
      Permission.viewFinancialReports,
      Permission.viewInventoryReports,
      Permission.viewCashDrawer,
    ],

    // المشاهد - قراءة فقط
    UserRole.viewer: [
      Permission.viewSales,
      Permission.viewProducts,
      Permission.viewCustomers,
      Permission.viewSuppliers,
      Permission.viewPurchases,
      Permission.viewInventory,
      Permission.viewReports,
    ],
  };

  static List<Permission> getPermissionsForRole(UserRole role) {
    return defaultPermissions[role] ?? [];
  }

  static String getRoleDisplayName(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'المدير';
      case UserRole.manager:
        return 'مدير';
      case UserRole.cashier:
        return 'كاشير';
      case UserRole.accountant:
        return 'محاسب';
      case UserRole.viewer:
        return 'مشاهد';
    }
  }

  static String getPermissionDisplayName(Permission permission) {
    switch (permission) {
      case Permission.viewSales:
        return 'عرض المبيعات';
      case Permission.createSale:
        return 'إنشاء بيع';
      case Permission.editSale:
        return 'تعديل بيع';
      case Permission.deleteSale:
        return 'حذف بيع';
      case Permission.refundSale:
        return 'إرجاع بيع';
      case Permission.createSales:
        return 'إنشاء مبيعات';
      case Permission.viewProducts:
        return 'عرض المنتجات';
      case Permission.createProduct:
        return 'إنشاء منتج';
      case Permission.editProduct:
        return 'تعديل منتج';
      case Permission.deleteProduct:
        return 'حذف منتج';
      case Permission.adjustStock:
        return 'تعديل المخزون';
      case Permission.viewCustomers:
        return 'عرض العملاء';
      case Permission.createCustomer:
        return 'إنشاء عميل';
      case Permission.editCustomer:
        return 'تعديل عميل';
      case Permission.deleteCustomer:
        return 'حذف عميل';
      case Permission.viewCustomerBalance:
        return 'عرض رصيد العميل';
      case Permission.viewSuppliers:
        return 'عرض الموردين';
      case Permission.createSupplier:
        return 'إنشاء مورد';
      case Permission.editSupplier:
        return 'تعديل مورد';
      case Permission.deleteSupplier:
        return 'حذف مورد';
      case Permission.viewSupplierBalance:
        return 'عرض رصيد المورد';
      case Permission.viewPurchases:
        return 'عرض المشتريات';
      case Permission.createPurchase:
        return 'إنشاء شراء';
      case Permission.editPurchase:
        return 'تعديل شراء';
      case Permission.deletePurchase:
        return 'حذف شراء';
      case Permission.approvePurchase:
        return 'اعتماد شراء';
      case Permission.viewInventory:
        return 'عرض المخزون';
      case Permission.adjustInventory:
        return 'تعديل المخزون';
      case Permission.transferInventory:
        return 'نقل مخزون';
      case Permission.conductStockTake:
        return 'جرد مخزون';
      case Permission.viewReports:
        return 'عرض التقارير';
      case Permission.exportReports:
        return 'تصدير تقارير';
      case Permission.viewFinancialReports:
        return 'عرض التقارير المالية';
      case Permission.viewInventoryReports:
        return 'عرض تقارير المخزون';
      case Permission.viewUsers:
        return 'عرض المستخدمين';
      case Permission.createUser:
        return 'إنشاء مستخدم';
      case Permission.editUser:
        return 'تعديل مستخدم';
      case Permission.deleteUser:
        return 'حذف مستخدم';
      case Permission.manageUsers:
        return 'إدارة المستخدمين';
      case Permission.lockUser:
        return 'قفل المستخدم';
      case Permission.unlockUser:
        return 'فتح المستخدم';
      case Permission.assignRoles:
        return 'تعيين أدوار';
      case Permission.viewSettings:
        return 'عرض الإعدادات';
      case Permission.editSettings:
        return 'تعديل الإعدادات';
      case Permission.manageLicense:
        return 'إدارة الترخيص';
      case Permission.viewAuditLog:
        return 'عرض سجل التدقيق';
      case Permission.createBackup:
        return 'إنشاء نسخة احتياطية';
      case Permission.restoreBackup:
        return 'استعادة نسخة احتياطية';
      case Permission.deleteBackup:
        return 'حذف نسخة احتياطية';
      case Permission.openDay:
        return 'فتح يوم';
      case Permission.closeDay:
        return 'إغلاق يوم';
      case Permission.viewCashDrawer:
        return 'عرض الدرج النقدي';
      case Permission.adjustCashDrawer:
        return 'تعديل الدرج النقدي';
    }
  }

  /// تحويل قائمة الصلاحيات إلى JSON
  static String permissionsToJson(List<Permission> permissions) {
    final permissionNames = permissions.map((p) => p.name).toList();
    return jsonEncode(permissionNames);
  }

  /// تحويل JSON إلى قائمة صلاحيات
  static List<Permission> permissionsFromJson(String json) {
    final permissionNames = List<String>.from(jsonDecode(json));
    return permissionNames
        .map((name) => Permission.values.firstWhere((p) => p.name == name))
        .toList();
  }

  /// الحصول على الصلاحيات الافتراضية لدور معين
  static List<Permission> getDefaultPermissions(UserRole role) {
    return defaultPermissions[role] ?? [];
  }
}
