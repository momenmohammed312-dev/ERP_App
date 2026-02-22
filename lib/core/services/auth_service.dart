// ════════════════════════════════════════════════════════════════════════
// خدمة المصادقة - POS SaaS Offline
// ════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../database/app_database.dart';

class AuthService {
  static final _storage = FlutterSecureStorage();
  static const _userKey = 'current_user_id';
  static const _roleKey = 'current_user_role';

  // Cache the current user in memory
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;

  final AppDatabase _db;
  AuthService(this._db);

  Future<AppUser?> login(String username, String password) async {
    try {
      final user = await _db.userDao.authenticate(username, password);
      if (user != null) {
        await _db.userDao.updateLastLogin(user.id);
        await _storage.write(key: _userKey, value: user.id.toString());
        await _storage.write(key: _roleKey, value: user.role);
        _currentUser = user; // ← cache it
        return user;
      }
      return null;
    } catch (e) {
      debugPrint('Auth error: $e');
      return null;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _roleKey);
    _currentUser = null; // ← clear cache
  }

  Future<bool> isLoggedIn() async {
    final userId = await _storage.read(key: _userKey);
    return userId != null;
  }

  Future<String?> getCurrentRole() async => _storage.read(key: _roleKey);

  Future<int?> getCurrentUserId() async {
    final id = await _storage.read(key: _userKey);
    return id != null ? int.tryParse(id) : null;
  }

  // Add changePassword method
  Future<bool> changePassword(
    int userId,
    String oldPassword,
    String newPassword,
  ) async {
    final user = await _db.userDao.getUserById(userId);
    if (user == null) return false;

    // Verify old password
    final verified = await _db.userDao.authenticate(user.username, oldPassword);
    if (verified == null) return false;

    // Update password
    await _db.userDao.changePassword(userId, newPassword);
    return true;
  }

  bool hasPermission(String role, String requiredRole) {
    const hierarchy = {'cashier': 0, 'manager': 1, 'admin': 2};
    return (hierarchy[role] ?? 0) >= (hierarchy[requiredRole] ?? 0);
  }
}
