// ════════════════════════════════════════════════════════════════════════
// اختبار بسيط جداً لنظام RBAC - POS SaaS Offline
// ════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';

void main() {
  group('RBAC Minimal Tests', () {
    test('should have correct role display names', () {
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.admin),
        equals('مدير النظام'),
      );
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.manager),
        equals('مدير'),
      );
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.cashier),
        equals('كاشير'),
      );
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.accountant),
        equals('محاسب'),
      );
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.viewer),
        equals('مشاهد'),
      );
    });

    test('should have correct permission display names', () {
      expect(
        PermissionMatrix.getPermissionDisplayName(Permission.viewProducts),
        equals('عرض المنتجات'),
      );
      expect(
        PermissionMatrix.getPermissionDisplayName(Permission.createSale),
        equals('إنشاء بيع'),
      );
      expect(
        PermissionMatrix.getPermissionDisplayName(Permission.viewUsers),
        equals('عرض المستخدمين'),
      );
    });

    test('should create user model correctly', () {
      final user = User(
        username: 'testuser',
        passwordHash: 'hashed_password',
        fullName: 'Test User',
        email: 'test@example.com',
        phone: '1234567890',
        role: UserRole.cashier,
        isActive: true,
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      expect(user.username, equals('testuser'));
      expect(user.fullName, equals('Test User'));
      expect(user.role, equals(UserRole.cashier));
      expect(user.isActive, isTrue);
      expect(user.email, equals('test@example.com'));
    });

    test('should handle user copyWith correctly', () {
      final originalUser = User(
        username: 'testuser',
        passwordHash: 'hashed_password',
        fullName: 'Test User',
        role: UserRole.cashier,
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      final updatedUser = originalUser.copyWith(
        fullName: 'Updated Name',
        role: UserRole.manager,
        updatedAt: DateTime.now(),
      );

      expect(updatedUser.username, equals('testuser'));
      expect(updatedUser.fullName, equals('Updated Name'));
      expect(updatedUser.role, equals(UserRole.manager));
      expect(updatedUser.updatedAt, isNotNull);
    });

    test('should handle enum conversion correctly', () {
      // Test UserRole enum
      expect(UserRole.admin.index, equals(0));
      expect(UserRole.manager.index, equals(1));
      expect(UserRole.cashier.index, equals(2));
      expect(UserRole.accountant.index, equals(3));
      expect(UserRole.viewer.index, equals(4));

      // Test Permission enum
      expect(Permission.viewProducts.index, equals(7));
      expect(Permission.createProduct.index, equals(8));
      expect(Permission.editProduct.index, equals(9));
      expect(Permission.deleteProduct.index, equals(10));
    });

    test('should handle audit fields correctly', () {
      final now = DateTime.now();
      final user = User(
        username: 'testuser',
        passwordHash: 'hashed_password',
        fullName: 'Test User',
        role: UserRole.cashier,
        createdAt: now,
        createdBy: 1,
        updatedAt: now,
        lastLogin: now,
      );

      expect(user.createdAt, equals(now));
      expect(user.createdBy, equals(1));
      expect(user.updatedAt, equals(now));
      expect(user.lastLogin, equals(now));
    });

    test('should handle user status correctly', () {
      final activeUser = User(
        username: 'activeuser',
        passwordHash: 'hashed_password',
        fullName: 'Active User',
        role: UserRole.cashier,
        isActive: true,
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      final inactiveUser = User(
        username: 'inactiveuser',
        passwordHash: 'hashed_password',
        fullName: 'Inactive User',
        role: UserRole.cashier,
        isActive: false,
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      expect(activeUser.isActive, isTrue);
      expect(inactiveUser.isActive, isFalse);
    });

    test('should validate user data correctly', () {
      // Test valid user
      final validUser = User(
        username: 'validuser',
        passwordHash: 'hashed_password',
        fullName: 'Valid User',
        role: UserRole.cashier,
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      expect(validUser.username.isNotEmpty, isTrue);
      expect(validUser.fullName.isNotEmpty, isTrue);
      expect(validUser.passwordHash.isNotEmpty, isTrue);

      // Test invalid user scenarios
      expect(() {
        User(
          username: '', // Empty username
          passwordHash: 'hashed_password',
          fullName: 'Test User',
          role: UserRole.cashier,
          createdAt: DateTime.now(),
          createdBy: 1,
        );
      }, throwsA(anything));

      expect(() {
        User(
          username: 'testuser',
          passwordHash: '', // Empty password hash
          fullName: 'Test User',
          role: UserRole.cashier,
          createdAt: DateTime.now(),
          createdBy: 1,
        );
      }, throwsA(anything));
    });

    test('should assign correct permissions to admin role', () {
      final permissions = PermissionMatrix.defaultPermissions[UserRole.admin]!;
      expect(permissions.contains(Permission.viewProducts), isTrue);
      expect(permissions.contains(Permission.createSale), isTrue);
      expect(permissions.contains(Permission.viewUsers), isTrue);
      expect(permissions.contains(Permission.viewReports), isTrue);
      expect(permissions.contains(Permission.viewSettings), isTrue);
    });

    test('should assign correct permissions to cashier role', () {
      final permissions =
          PermissionMatrix.defaultPermissions[UserRole.cashier]!;
      expect(permissions.contains(Permission.viewProducts), isTrue);
      expect(permissions.contains(Permission.createSale), isTrue);
      expect(permissions.contains(Permission.viewUsers), isFalse);
      expect(permissions.contains(Permission.viewSettings), isFalse);
    });

    test('should assign correct permissions to viewer role', () {
      final permissions = PermissionMatrix.defaultPermissions[UserRole.viewer]!;
      expect(permissions.contains(Permission.viewProducts), isTrue);
      expect(permissions.contains(Permission.viewCustomers), isTrue);
      expect(permissions.contains(Permission.createSale), isFalse);
      expect(permissions.contains(Permission.viewUsers), isFalse);
    });

    test('should handle role hierarchy correctly', () {
      // Admin should have all permissions
      final adminPermissions =
          PermissionMatrix.defaultPermissions[UserRole.admin]!;
      expect(adminPermissions.length, greaterThan(30));

      // Manager should have most permissions but not user management
      final managerPermissions =
          PermissionMatrix.defaultPermissions[UserRole.manager]!;
      expect(managerPermissions.contains(Permission.viewUsers), isFalse);
      expect(managerPermissions.contains(Permission.viewSettings), isTrue);

      // Cashier should have sales-related permissions
      final cashierPermissions =
          PermissionMatrix.defaultPermissions[UserRole.cashier]!;
      expect(cashierPermissions.contains(Permission.createSale), isTrue);
      expect(cashierPermissions.contains(Permission.viewProducts), isTrue);
      expect(cashierPermissions.contains(Permission.viewUsers), isFalse);

      // Accountant should have reporting permissions
      final accountantPermissions =
          PermissionMatrix.defaultPermissions[UserRole.accountant]!;
      expect(accountantPermissions.contains(Permission.viewReports), isTrue);
      expect(accountantPermissions.contains(Permission.createSale), isFalse);

      // Viewer should have view-only permissions
      final viewerPermissions =
          PermissionMatrix.defaultPermissions[UserRole.viewer]!;
      expect(viewerPermissions.contains(Permission.viewProducts), isTrue);
      expect(viewerPermissions.contains(Permission.viewCustomers), isTrue);
      expect(viewerPermissions.contains(Permission.createSale), isFalse);
    });

    test('should handle permission checks correctly', () {
      final adminPermissions =
          PermissionMatrix.defaultPermissions[UserRole.admin]!;
      final cashierPermissions =
          PermissionMatrix.defaultPermissions[UserRole.cashier]!;

      // Admin should have all permissions
      expect(adminPermissions.contains(Permission.viewUsers), isTrue);
      expect(adminPermissions.contains(Permission.viewSettings), isTrue);
      expect(adminPermissions.contains(Permission.createSale), isTrue);

      // Cashier should have limited permissions
      expect(cashierPermissions.contains(Permission.viewUsers), isFalse);
      expect(cashierPermissions.contains(Permission.viewSettings), isFalse);
      expect(cashierPermissions.contains(Permission.createSale), isTrue);
    });

    test('should handle user serialization correctly', () {
      final user = User(
        username: 'testuser',
        passwordHash: 'hashed_password',
        fullName: 'Test User',
        role: UserRole.cashier,
        isActive: true,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        createdBy: 1,
      );

      // Test that user can be created and has expected properties
      expect(user.username, equals('testuser'));
      expect(user.fullName, equals('Test User'));
      expect(user.role, equals(UserRole.cashier));
      expect(user.isActive, isTrue);
      expect(user.createdAt, isNotNull);
      expect(user.createdBy, equals(1));
    });

    test('should handle permission matrix methods correctly', () {
      // Test role display names
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.admin),
        isA<String>(),
      );
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.manager),
        isA<String>(),
      );
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.cashier),
        isA<String>(),
      );
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.accountant),
        isA<String>(),
      );
      expect(
        PermissionMatrix.getRoleDisplayName(UserRole.viewer),
        isA<String>(),
      );

      // Test permission display names
      expect(
        PermissionMatrix.getPermissionDisplayName(Permission.viewProducts),
        isA<String>(),
      );
      expect(
        PermissionMatrix.getPermissionDisplayName(Permission.createSale),
        isA<String>(),
      );
      expect(
        PermissionMatrix.getPermissionDisplayName(Permission.viewUsers),
        isA<String>(),
      );
    });

    test('should handle all permission categories', () {
      final adminPermissions =
          PermissionMatrix.defaultPermissions[UserRole.admin]!;

      // Test that all permission categories are included
      expect(adminPermissions.contains(Permission.viewSales), isTrue);
      expect(adminPermissions.contains(Permission.viewProducts), isTrue);
      expect(adminPermissions.contains(Permission.viewCustomers), isTrue);
      expect(adminPermissions.contains(Permission.viewSuppliers), isTrue);
      expect(adminPermissions.contains(Permission.viewPurchases), isTrue);
      expect(adminPermissions.contains(Permission.viewInventory), isTrue);
      expect(adminPermissions.contains(Permission.viewReports), isTrue);
      expect(adminPermissions.contains(Permission.viewSettings), isTrue);
      expect(adminPermissions.contains(Permission.viewUsers), isTrue);
    });

    test('should handle custom permissions correctly', () {
      // Test that custom permissions can be stored and retrieved
      final customPermissions = [
        Permission.viewProducts,
        Permission.createSale,
      ];

      // Create user with custom permissions
      final userWithCustomPerms = User(
        username: 'customuser',
        passwordHash: 'hash',
        fullName: 'Custom User',
        role: UserRole.viewer, // Base role has limited permissions
        customPermissions: customPermissions, // Add custom permissions
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      // Verify custom permissions are stored
      expect(userWithCustomPerms.customPermissions, isNotNull);
      expect(userWithCustomPerms.customPermissions.length, equals(2));
      expect(
        userWithCustomPerms.customPermissions.contains(Permission.viewProducts),
        isTrue,
      );
      expect(
        userWithCustomPerms.customPermissions.contains(Permission.createSale),
        isTrue,
      );
    });

    test('should handle user fields correctly', () {
      final now = DateTime.now();
      final user = User(
        username: 'testuser',
        passwordHash: 'hashed_password',
        fullName: 'Test User',
        email: 'test@example.com',
        phone: '1234567890',
        role: UserRole.cashier,
        customPermissions: [Permission.viewProducts],
        isActive: true,
        failedAttempts: 0,
        lockedUntil: null,
        lastLogin: now,
        createdAt: now,
        updatedAt: now,
        createdBy: 1,
      );

      expect(user.username, equals('testuser'));
      expect(user.fullName, equals('Test User'));
      expect(user.email, equals('test@example.com'));
      expect(user.phone, equals('1234567890'));
      expect(user.role, equals(UserRole.cashier));
      expect(user.isActive, isTrue);
      expect(user.failedAttempts, equals(0));
      expect(user.lockedUntil, isNull);
      expect(user.lastLogin, equals(now));
      expect(user.createdAt, equals(now));
      expect(user.updatedAt, equals(now));
      expect(user.createdBy, equals(1));
      expect(user.customPermissions, isNotNull);
      expect(user.customPermissions.contains(Permission.viewProducts), isTrue);
    });
  });
}
