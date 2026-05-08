import 'package:drift/drift.dart';

@DataClassName('AppUser')
enum UserRole { admin(0), manager(1), cashier(2), accountant(3), viewer(4); final int value; const UserRole(this.value); static UserRole fromInt(int? val) { switch (val) { case 0: return UserRole.admin; case 1: return UserRole.manager; case 2: return UserRole.cashier; case 3: return UserRole.accountant; default: return UserRole.viewer; } } }

@DataClassName('AppUser')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().unique()();
  TextColumn get password => text()(); // hashed
  TextColumn get role => text().withDefault(const Constant('cashier'))();
  // roles: admin, manager, cashier
  TextColumn get fullName => text()();
  TextColumn get employeeId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  TextColumn get customPermissions => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastLogin => dateTime().nullable()();
}
