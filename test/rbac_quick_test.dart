// ════════════════════════════════════════════════════════════════════════
// اختبار سريع لنظام RBAC - POS SaaS Offline
// ════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';

void main() {
  group('RBAC Quick Tests', () {
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
        PermissionMatrix.getPermissionDisplayName(Permission.createSales),
        equals('إنشاء مبيعات'),
      );
      expect(
        PermissionMatrix.getPermissionDisplayName(Permission.manageUsers),
        equals('إدارة المستخدمين'),
      );
    });

    test('should assign correct permissions to admin role', () {
      final permissions = PermissionMatrix.getDefaultPermissions(
        UserRole.admin,
      );
      expect(permissions.contains(Permission.viewProducts), isTrue);
      expect(permissions.contains(Permission.createSales), isTrue);
      expect(permissions.contains(Permission.manageUsers), isTrue);
      expect(permissions.contains(Permission.viewReports), isTrue);
      expect(permissions.contains(Permission.viewSettings), isTrue);
    });

    test('should assign correct permissions to cashier role', () {
      final permissions = PermissionMatrix.getDefaultPermissions(
        UserRole.cashier,
      );
      expect(permissions.contains(Permission.viewProducts), isTrue);
      expect(permissions.contains(Permission.createSales), isTrue);
      expect(permissions.contains(Permission.manageUsers), isFalse);
      expect(permissions.contains(Permission.viewSettings), isFalse);
    });

    test('should assign correct permissions to viewer role', () {
      final permissions = PermissionMatrix.getDefaultPermissions(
        UserRole.viewer,
      );
      expect(permissions.contains(Permission.viewProducts), isTrue);
      expect(permissions.contains(Permission.viewCustomers), isTrue);
      expect(permissions.contains(Permission.createSales), isFalse);
      expect(permissions.contains(Permission.manageUsers), isFalse);
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

    test('should serialize user to JSON correctly', () {
      final user = User(
        username: 'testuser',
        passwordHash: 'hashed_password',
        fullName: 'Test User',
        role: UserRole.cashier,
        isActive: true,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        createdBy: 1,
      );

      final json = user.toJson();
      expect(json['username'], equals('testuser'));
      expect(json['fullName'], equals('Test User'));
      expect(json['role'], equals(2)); // UserRole.cashier index
      expect(json['isActive'], isTrue);
    });

    test('should deserialize user from JSON correctly', () {
      final json = {
        'username': 'testuser',
        'passwordHash': 'hashed_password',
        'fullName': 'Test User',
        'role': 2, // UserRole.cashier
        'isActive': true,
        'createdAt': '2024-01-01T00:00:00.000Z',
        'createdBy': 1,
      };

      final user = User.fromJson(json);
      expect(user.username, equals('testuser'));
      expect(user.fullName, equals('Test User'));
      expect(user.role, equals(UserRole.cashier));
      expect(user.isActive, isTrue);
    });

    test('should handle custom permissions correctly', () {
      final customPermissions = [
        Permission.viewProducts,
        Permission.createSales,
      ];
      final json = PermissionMatrix.permissionsToJson(customPermissions);
      final parsed = PermissionMatrix.permissionsFromJson(json);

      expect(parsed.length, equals(2));
      expect(parsed.contains(Permission.viewProducts), isTrue);
      expect(parsed.contains(Permission.createSales), isTrue);
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

    test('should handle role hierarchy correctly', () {
      // Admin should have all permissions
      final adminPermissions = PermissionMatrix.getDefaultPermissions(
        UserRole.admin,
      );
      expect(adminPermissions.length, greaterThan(30));

      // Manager should have most permissions but not user management
      final managerPermissions = PermissionMatrix.getDefaultPermissions(
        UserRole.manager,
      );
      expect(managerPermissions.contains(Permission.manageUsers), isFalse);
      expect(managerPermissions.contains(Permission.viewSettings), isFalse);

      // Cashier should have sales-related permissions
      final cashierPermissions = PermissionMatrix.getDefaultPermissions(
        UserRole.cashier,
      );
      expect(cashierPermissions.contains(Permission.createSales), isTrue);
      expect(cashierPermissions.contains(Permission.viewProducts), isTrue);
      expect(cashierPermissions.contains(Permission.manageUsers), isFalse);

      // Accountant should have reporting permissions
      final accountantPermissions = PermissionMatrix.getDefaultPermissions(
        UserRole.accountant,
      );
      expect(accountantPermissions.contains(Permission.viewReports), isTrue);
      expect(accountantPermissions.contains(Permission.createSales), isFalse);

      // Viewer should have view-only permissions
      final viewerPermissions = PermissionMatrix.getDefaultPermissions(
        UserRole.viewer,
      );
      expect(viewerPermissions.contains(Permission.viewProducts), isTrue);
      expect(viewerPermissions.contains(Permission.viewCustomers), isTrue);
      expect(viewerPermissions.contains(Permission.createSales), isFalse);
    });

    test('should handle permission checks correctly', () {
      final adminPermissions = PermissionMatrix.getDefaultPermissions(
        UserRole.admin,
      );
      final cashierPermissions = PermissionMatrix.getDefaultPermissions(
        UserRole.cashier,
      );

      // Admin should have all permissions
      expect(adminPermissions.contains(Permission.manageUsers), isTrue);
      expect(adminPermissions.contains(Permission.viewSettings), isTrue);
      expect(adminPermissions.contains(Permission.createSales), isTrue);

      // Cashier should have limited permissions
      expect(cashierPermissions.contains(Permission.manageUsers), isFalse);
      expect(cashierPermissions.contains(Permission.viewSettings), isFalse);
      expect(cashierPermissions.contains(Permission.createSales), isTrue);
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

      final lockedUser = User(
        username: 'lockeduser',
        passwordHash: 'hashed_password',
        fullName: 'Locked User',
        role: UserRole.cashier,
        isActive: true,
        lockedUntil: DateTime.now().add(Duration(hours: 1)),
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
      expect(activeUser.isLocked, isFalse);

      expect(lockedUser.isActive, isTrue);
      expect(lockedUser.isLocked, isTrue);

      expect(inactiveUser.isActive, isFalse);
      expect(inactiveUser.isLocked, isFalse);
    });
  });
}
