import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';

/// Provider for the SecureStorage instance
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// State notifier to manage the current user session
class AuthNotifier extends StateNotifier<User?> {
  final FlutterSecureStorage _storage;
  static const _userKey = 'current_user_json';
  static const _userIdKey = 'current_user_id';

  AuthNotifier(this._storage) : super(null) {
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final userJson = await _storage.read(key: _userKey);
      if (userJson != null) {
        state = User.fromJson(jsonDecode(userJson));
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
}

/// Provider for the AuthNotifier
final authProvider = StateNotifierProvider<AuthNotifier, User?>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return AuthNotifier(storage);
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
