import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../database/app_database.dart';
import '../provider/app_database_provider.dart';
import '../services/settings_service.dart';

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
  late final Future<void> _initFuture;

  AuthNotifier(this._storage, this._db) : super(null) {
    _initFuture = _loadUser();
  }

  /// Wait until initial Remember Me restoration has completed.
  Future<void> ensureInitialized() => _initFuture;

  Future<void> _loadUser() async {
    try {
      final rememberMe = await SettingsService.getRememberMe();
      if (!rememberMe) {
        await _clearPersistedSession();
        state = null;
        return;
      }

      String? rawJson;
      try {
        rawJson = await _storage.read(key: _userKey);
      } catch (e) {
        debugPrint('Secure storage read fallback: $e');
      }
      rawJson ??= await SettingsService.getRememberedUserJson();

      if (rawJson == null || rawJson.isEmpty) {
        state = null;
        return;
      }

      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      final restored = User.fromJson(decoded);

      // Virtual MO2 Super Admin session
      if (restored.id == -1) {
        state = restored;
        return;
      }

      if (restored.id == null) {
        await _clearPersistedSession();
        state = null;
        return;
      }

      // Confirm user still exists and is active in local DB.
      final appUser = await _db.userDao.getUserById(restored.id!);
      if (appUser == null || !appUser.isActive) {
        await _clearPersistedSession();
        state = null;
        return;
      }

      state = restored;
    } catch (e) {
      debugPrint('Error loading remembered user: $e');
      state = null;
    }
  }

  Future<void> login(User user, {bool rememberMe = false}) async {
    state = user;
    await SettingsService.setLastUsername(user.username);
    await SettingsService.setRememberMe(rememberMe);

    if (rememberMe) {
      final encoded = jsonEncode(user.toJson());
      await SettingsService.setRememberedUserJson(encoded);
      try {
        await _storage.write(key: _userKey, value: encoded);
        if (user.id != null) {
          await _storage.write(key: _userIdKey, value: user.id.toString());
        }
      } catch (e) {
        debugPrint('Secure storage write fallback: $e');
      }
    } else {
      await _clearPersistedSession();
    }
  }

  Future<void> logout() async {
    state = null;
    await SettingsService.setRememberMe(false);
    await _clearPersistedSession();
  }

  /// Update the current user state (e.g., after password change or profile update)
  Future<void> updateUser(User user) async {
    state = user;
    final rememberMe = await SettingsService.getRememberMe();
    if (rememberMe) {
      final encoded = jsonEncode(user.toJson());
      await SettingsService.setRememberedUserJson(encoded);
      try {
        await _storage.write(key: _userKey, value: encoded);
      } catch (e) {
        debugPrint('Secure storage update fallback: $e');
      }
    }
  }

  Future<void> _clearPersistedSession() async {
    await SettingsService.setRememberedUserJson(null);
    try {
      await _storage.delete(key: _userKey);
      await _storage.delete(key: _userIdKey);
    } catch (e) {
      debugPrint('Error clearing storage: $e');
    }
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
