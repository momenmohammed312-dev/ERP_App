import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'dart:convert';
import '../app_database.dart';
import '../tables/users_table.dart';

part 'user_dao.g.dart';

@DriftAccessor(tables: [Users])
class UserDao extends DatabaseAccessor<AppDatabase> with _$UserDaoMixin {
  UserDao(super.db);

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  Future<AppUser?> authenticate(String username, String password) =>
      (select(db.users)..where(
            (u) =>
                u.username.equals(username) &
                u.password.equals(_hashPassword(password)) &
                u.isActive.equals(true),
          ))
          .getSingleOrNull();

  Future<AppUser?> getUserById(int id) =>
      (select(db.users)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<AppUser?> getUserByUsername(String username) => (select(
    db.users,
  )..where((u) => u.username.equals(username))).getSingleOrNull();

  Stream<List<AppUser>> watchAllUsers() => select(db.users).watch();

  Future<int> createUser(
    String username,
    String password,
    String role,
    String fullName,
  ) => into(db.users).insert(
    UsersCompanion(
      username: Value(username),
      password: Value(_hashPassword(password)),
      role: Value(role),
      fullName: Value(fullName),
    ),
  );

  Future<bool> updateUser(AppUser user) => update(db.users).replace(user);

  Future<void> updateLastLogin(int userId) =>
      (update(db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(lastLogin: Value(DateTime.now())),
      );

  Future<void> changePassword(int userId, String newPassword) =>
      (update(db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(password: Value(_hashPassword(newPassword))),
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
