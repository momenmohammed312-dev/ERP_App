import 'dart:convert';
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
  static const _userKey = 'current_user_json';
  static const _userIdKey = 'current_user_id';

  AuthNotifier(this._storage, AppDatabase _db) : super(null) {
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      // Restore session from secure storage (only if user previously logged in explicitly)
      final userJson = await _storage.read(key: _userKey);
      if (userJson != null) {
        state = User.fromJson(jsonDecode(userJson));
        return;
      }
      // No stored session → stay null → router redirects to /login
      state = null;
    } catch (e) {
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
