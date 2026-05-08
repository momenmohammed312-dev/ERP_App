import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../database/app_database.dart';
import '../provider/app_database_provider.dart';

/// Provider for the SecureStorage instance
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// State notifier to manage the current user session
class AuthNotifier extends StateNotifier<User?> {
  final FlutterSecureStorage _storage;
  final AppDatabase _db;
  static const _userKey = 'current_user_json';
  static const _userIdKey = 'current_user_id';

  AuthNotifier(this._storage, this._db) : super(null) {
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      // Try to load from secure storage first (for returning users)
      final userJson = await _storage.read(key: _userKey);
      if (userJson != null) {
        state = User.fromJson(jsonDecode(userJson));
        return;
      }

      // On desktop platforms (Windows/macOS/Linux) and not web/mobile,
      // automatically log in as the admin user (single-user offline mode)
      if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
        final adminAppUser = await _db.userDao.getUserByUsername('admin');
        if (adminAppUser != null) {
          final user = _mapAppUserToUser(adminAppUser);
          state = user;
          // Persist to secure storage so we don't hit DB every launch
          await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
          await _storage.write(key: _userIdKey, value: user.id.toString());
          return;
        }
      }
    } catch (e) {
      // If error loading user, default to null (logged out)
      state = null;
    }
  }

  Future<void> login(User user) async {
    state = user;
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    await _storage.write(key: _userIdKey, value: user.id.toString());
  }

  Future<void> logout() async {
    state = null;
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _userIdKey);
  }

  /// Update the current user state (e.g., after password change or profile update)
  Future<void> updateUser(User user) async {
    state = user;
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  // Helper method to map AppUser (from DB) to User (app model)
  User _mapAppUserToUser(AppUser appUser) {
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

    return User(
      id: appUser.id,
      username: appUser.username,
      passwordHash: appUser.password,
      fullName: appUser.fullName,
      role: role,
      isActive: appUser.isActive,
      lastLogin: appUser.lastLogin,
      createdAt: appUser.createdAt,
      // Optional fields
      email: null,
      phone: null,
      customPermissions: const [],
      failedAttempts: 0,
      lockedUntil: null,
      updatedAt: null,
      createdBy: null,
      updatedBy: null,
    );
  }
}

/// Provider for the AuthNotifier
final authProvider = StateNotifierProvider<AuthNotifier, User?>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final db = ref.watch(appDatabaseProvider);
  return AuthNotifier(storage, db);
});

/// Synchonous provider for current user ID (for easier access)
final currentUserIdProvider = Provider<int?>((ref) {
  return ref.watch(authProvider)?.id;
});

/// Synchonous provider for current user role
final currentUserRoleProvider = Provider<UserRole?>((ref) {
  return ref.watch(authProvider)?.role;
});

/// Provider to check if anyone is logged in
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider) != null;
});
