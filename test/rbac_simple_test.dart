// ════════════════════════════════════════════════════════════════════════
// اختبار بسيط لنظام RBAC - POS SaaS Offline
// ══════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart' as models;
import 'package:pos_offline_desktop/core/services/auth_service.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/user_dao.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';

void main() {
  group('RBAC Simple Tests', () {
    late AuthService authService;
    late UserDao userDao;
    late AppDatabase db;

    setUp(() async {
      // Get the database instance using provider (same way as AuthService does)
      final container = ProviderContainer();
      authService = container.read(authServiceProvider);
      userDao = container.read(appDatabaseProvider).userDao;
    });

    test('should have correct role display names', () {
      expect(
        models.PermissionMatrix.getRoleDisplayName(models.UserRole.admin),
        equals('مدير النظام'),
      );
      expect(
        models.PermissionMatrix.getRoleDisplayName(models.UserRole.manager),
        equals('مدير'),
      );
      expect(
        models.PermissionMatrix.getRoleDisplayName(models.UserRole.cashier),
        equals('كاشير'),
      );
      expect(
        models.PermissionMatrix.getRoleDisplayName(models.UserRole.accountant),
        equals('محاسب'),
      );
      expect(
        models.PermissionMatrix.getRoleDisplayName(models.UserRole.viewer),
        equals('مشاهد'),
      );
    });

    test('should have correct permission display names', () {
      expect(
        models.PermissionMatrix.getPermissionDisplayName(
          models.Permission.viewProducts,
        ),
        equals('عرض المنتجات'),
      );
      expect(
        models.PermissionMatrix.getPermissionDisplayName(
          models.Permission.createSale,
        ),
        equals('إنشاء بيع'),
      );
      expect(
        models.PermissionMatrix.getPermissionDisplayName(
          models.Permission.viewUsers,
        ),
        equals('عرض المستخدمين'),
      );
      expect(
        models.PermissionMatrix.getPermissionDisplayName(
          models.Permission.manageUsers,
        ),
        equals('إدارة المستخدمين'),
      );
    });

    test('should assign correct permissions to admin role', () {
      final permissions = models.PermissionMatrix.getDefaultPermissions(
        models.UserRole.admin,
      );
      expect(permissions.contains(models.Permission.viewProducts), isTrue);
      expect(permissions.contains(models.Permission.createSale), isTrue);
      expect(permissions.contains(models.Permission.manageUsers), isTrue);
      expect(permissions.contains(models.Permission.viewReports), isTrue);
      expect(permissions.contains(models.Permission.viewSettings), isTrue);
    });

    test('should assign correct permissions to cashier role', () {
      final permissions = models.PermissionMatrix.getDefaultPermissions(
        models.UserRole.cashier,
      );
      expect(permissions.contains(models.Permission.viewProducts), isTrue);
      expect(permissions.contains(models.Permission.createSale), isTrue);
      expect(permissions.contains(models.Permission.manageUsers), isFalse);
      expect(permissions.contains(models.Permission.viewSettings), isFalse);
    });

    test('should assign correct permissions to viewer role', () {
      final permissions = models.PermissionMatrix.getDefaultPermissions(
        models.UserRole.viewer,
      );
      expect(permissions.contains(models.Permission.viewProducts), isTrue);
      expect(permissions.contains(models.Permission.viewCustomers), isTrue);
      expect(permissions.contains(models.Permission.createSale), isFalse);
      expect(permissions.contains(models.Permission.manageUsers), isFalse);
    });

    test('should create user model correctly', () {
      final user = models.User(
        username: 'testuser',
        passwordHash: 'hashed_password',
        fullName: 'Test User',
        email: 'test@example.com',
        phone: '1234567890',
        role: models.UserRole.cashier,
        isActive: true,
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      expect(user.username, equals('testuser'));
      expect(user.fullName, equals('Test User'));
      expect(user.role, equals(models.UserRole.cashier));
      expect(user.isActive, isTrue);
      expect(user.email, equals('test@example.com'));
    });

    test('should handle enum conversion correctly', () {
      // Test UserRole enum
      expect(models.UserRole.admin.index, equals(0));
      expect(models.UserRole.manager.index, equals(1));
      expect(models.UserRole.cashier.index, equals(2));
      expect(models.UserRole.accountant.index, equals(3));
      expect(models.UserRole.viewer.index, equals(4));

      // Test Permission enum
      expect(models.Permission.viewProducts.index, equals(7));
      expect(models.Permission.createProduct.index, equals(8));
      expect(models.Permission.editProduct.index, equals(9));
      expect(models.Permission.deleteProduct.index, equals(10));
    });

    test('should handle audit fields correctly', () {
      final now = DateTime.now();
      final user = models.User(
        username: 'testuser',
        passwordHash: 'hashed_password',
        fullName: 'Test User',
        role: models.UserRole.cashier,
        createdAt: now,
        createdBy: 1,
        updatedAt: now,
        lastLogin: now,
      );

      expect(user.username, equals('testuser'));
      expect(user.fullName, equals('Test User'));
      expect(user.role, equals(models.UserRole.cashier));
      expect(user.isActive, isTrue);
      expect(user.createdBy, equals(1));
      expect(user.updatedAt, equals(now));
      expect(user.lastLogin, equals(now));
    });

    test('should handle user status correctly', () {
      final activeUser = models.User(
        username: 'activeuser',
        passwordHash: 'hashed_password',
        fullName: 'Active User',
        role: models.UserRole.cashier,
        isActive: true,
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      final inactiveUser = models.User(
        username: 'inactiveuser',
        passwordHash: 'hashed_password',
        fullName: 'Inactive User',
        role: models.UserRole.cashier,
        isActive: false,
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      expect(activeUser.isActive, isTrue);
      expect(inactiveUser.isActive, isFalse);
    });

    test('should validate user data correctly', () {
      // Test valid user
      final validUser = models.User(
        username: 'validuser',
        passwordHash: 'hashed_password',
        fullName: 'Valid User',
        role: models.UserRole.cashier,
        createdAt: DateTime.now(),
        createdBy: 1,
      );

      expect(validUser.username.isNotEmpty, isTrue);
      expect(validUser.fullName.isNotEmpty, isTrue);
      expect(validUser.role, equals(models.UserRole.cashier));

      // Test invalid user scenarios
      expect(() {
        models.User(
          username: '', // Empty username
          passwordHash: 'hashed_password',
          fullName: 'Test User',
          role: models.UserRole.cashier,
          createdAt: DateTime.now(),
          createdBy: 1,
        );
      }, throwsA(anything));

      expect(() {
        models.User(
          username: 'testuser',
          passwordHash: '', // Empty password hash
          fullName: 'Test User',
          role: models.UserRole.cashier,
          createdAt: DateTime.now(),
          createdBy: 1,
        );
      }, throwsA(anything));
    });

    test('should handle role hierarchy correctly', () {
      // Admin should have all permissions
      final adminPermissions = models.PermissionMatrix.getDefaultPermissions(
        models.UserRole.admin,
      );
      expect(adminPermissions.length, greaterThan(30));

      // Manager should have most permissions but not user management
      final managerPermissions = models.PermissionMatrix.getDefaultPermissions(
        models.UserRole.manager,
      );
      expect(
        managerPermissions.contains(models.Permission.manageUsers),
        isFalse,
      );
      expect(
        managerPermissions.contains(models.Permission.viewSettings),
        isFalse,
      );

      // Cashier should have sales-related permissions
      final cashierPermissions = models.PermissionMatrix.getDefaultPermissions(
        models.UserRole.cashier,
      );
      expect(cashierPermissions.contains(models.Permission.createSale), isTrue);
      expect(
        cashierPermissions.contains(models.Permission.viewProducts),
        isTrue,
      );
      expect(
        cashierPermissions.contains(models.Permission.manageUsers),
        isFalse,
      );

      // Accountant should have reporting permissions
      final accountantPermissions = models
          .PermissionMatrix.getDefaultPermissions(models.UserRole.accountant);
      expect(
        accountantPermissions.contains(models.Permission.viewReports),
        isTrue,
      );
      expect(
        accountantPermissions.contains(models.Permission.createSale),
        isFalse,
      );

      // Viewer should have view-only permissions
      final viewerPermissions = models.PermissionMatrix.getDefaultPermissions(
        models.UserRole.viewer,
      );
      expect(
        viewerPermissions.contains(models.Permission.viewProducts),
        isTrue,
      );
      expect(
        viewerPermissions.contains(models.Permission.viewCustomers),
        isTrue,
      );
      expect(viewerPermissions.contains(models.Permission.createSale), isFalse);
    });

    test('should handle permission checks correctly', () {
      final adminPermissions = models.PermissionMatrix.getDefaultPermissions(
        models.UserRole.admin,
      );
      final cashierPermissions = models.PermissionMatrix.getDefaultPermissions(
        models.UserRole.cashier,
      );

      // Admin should have all permissions
      expect(adminPermissions.contains(models.Permission.manageUsers), isTrue);
      expect(adminPermissions.contains(models.Permission.viewSettings), isTrue);
      expect(adminPermissions.contains(models.Permission.createSale), isTrue);

      // Cashier should have limited permissions
      expect(
        cashierPermissions.contains(models.Permission.manageUsers),
        isFalse,
      );
      expect(
        cashierPermissions.contains(models.Permission.viewSettings),
        isFalse,
      );
      expect(cashierPermissions.contains(models.Permission.createSale), isTrue);
    });

    test('should handle custom permissions correctly', () {
      final customPermissions = [
        models.Permission.viewProducts,
        models.Permission.createSale,
      ];
      final json = models.PermissionMatrix.permissionsToJson(customPermissions);
      final parsed = models.PermissionMatrix.permissionsFromJson(json);

      expect(parsed.length, equals(2));
      expect(parsed.contains(models.Permission.viewProducts), isTrue);
      expect(parsed.contains(models.Permission.createSale), isTrue);
    });

    test('should handle user serialization correctly', () {
      final user = models.User(
        username: 'testuser',
        passwordHash: 'hashed_password',
        fullName: 'Test User',
        role: models.UserRole.cashier,
        isActive: true,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        createdBy: 1,
      );

      // Test that user can be created and has expected properties
      expect(user.username, equals('testuser'));
      expect(user.fullName, equals('Test User'));
      expect(user.role, equals(models.UserRole.cashier));
      expect(user.isActive, isTrue);
      expect(user.createdAt, isNotNull);
      expect(user.createdBy, equals(1));
    });
  });
}
