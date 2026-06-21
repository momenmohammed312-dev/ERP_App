import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';
import '../models/user_model.dart';
import '../provider/app_database_provider.dart';
import '../provider/auth_provider.dart';

class AuthService {
  final AppDatabase _db;
  final Ref _ref;

  AuthService(this._db, this._ref);

  Future<User?> login(String username, String password) async {
    try {
      final appUser = await _db.userDao.authenticate(username, password);
      if (appUser != null) {
        // Map AppUser to User model
        final user = _mapAppUserToUser(appUser);

        // Update auth state via provider
        await _ref.read(authProvider.notifier).login(user);

        await _db.userDao.updateLastLogin(appUser.id);
        return user;
      }
      return null;
    } catch (e) {
      debugPrint('Auth error: $e');
      return null;
    }
  }

  Future<void> logout() async {
    await _ref.read(authProvider.notifier).logout();
  }

  bool isLoggedIn() {
    return _ref.read(authProvider) != null;
  }

  UserRole? getCurrentRole() {
    return _ref.read(authProvider)?.role;
  }

  int? getCurrentUserId() {
    return _ref.read(authProvider)?.id;
  }

  User? get currentUser => _ref.read(authProvider);

  User? getCurrentUser() {
    return _ref.read(authProvider);
  }

  // Add changePassword method
  Future<bool> changePassword(
    int userId,
    String oldPassword,
    String newPassword,
  ) async {
    final appUser = await _db.userDao.getUserById(userId);
    if (appUser == null) return false;

    // Verify old password
    final verified = await _db.userDao.authenticate(
      appUser.username,
      oldPassword,
    );
    if (verified == null) return false;

    // Update password
    await _db.userDao.changePassword(userId, newPassword);
    return true;
  }

  /// Helper to map drift AppUser to our custom User model
  User _mapAppUserToUser(AppUser appUser) {
    // Map string role to UserRole enum
    UserRole role;
    switch (appUser.role.toLowerCase()) {
      case 'admin':
        role = UserRole.admin;
        break;
      case 'manager':
        role = UserRole.manager;
        break;
      case 'cashier':
        role = UserRole.cashier;
        break;
      case 'accountant':
        role = UserRole.accountant;
        break;
      case 'viewer':
        role = UserRole.viewer;
        break;
      default:
        role = UserRole.viewer;
    }

    List<Permission> customPerms = <Permission>[];
    if (appUser.customPermissions != null && appUser.customPermissions!.isNotEmpty) {
      try {
        final jsonList = jsonDecode(appUser.customPermissions!) as List;
        customPerms = jsonList
            .map((e) => Permission.values.firstWhere(
                  (p) => p.name == e,
                  orElse: () => Permission.viewSales,
                ))
            .toList();
      } catch (e) {
        debugPrint('Error parsing custom permissions: $e');
      }
    }

    return User(
      id: appUser.id,
      username: appUser.username,
      passwordHash: appUser.password,
      fullName: appUser.fullName,
      role: role,
      isActive: appUser.isActive,
      lastLogin: appUser.lastLogin,
      createdAt: appUser.createdAt,
      customPermissions: customPerms,
    );
  }
}

/// Provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AuthService(db, ref);
});
