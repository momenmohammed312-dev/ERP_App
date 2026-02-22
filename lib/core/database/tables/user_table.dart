import 'package:drift/drift.dart';

enum UserRole {
  admin(0),
  manager(1),
  cashier(2),
  accountant(3),
  viewer(4);

  final int value;
  const UserRole(this.value);

  static UserRole fromInt(int? val) {
    switch (val) {
      case 0:
        return UserRole.admin;
      case 1:
        return UserRole.manager;
      case 2:
        return UserRole.cashier;
      case 3:
        return UserRole.accountant;
      case 4:
        return UserRole.viewer;
      default:
        return UserRole.viewer;
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'المدير';
      case UserRole.manager:
        return 'مدير';
      case UserRole.cashier:
        return 'كاشير';
      case UserRole.accountant:
        return 'محاسب';
      case UserRole.viewer:
        return 'مشاهد';
    }
  }
}

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().unique().withLength(min: 3, max: 50)();
  TextColumn get passwordHash =>
      text().withLength(min: 64, max: 64)(); // SHA-256 hash
  TextColumn get fullName => text().withLength(min: 2, max: 100)();
  TextColumn get email => text().nullable().withLength(max: 255)();
  TextColumn get phone => text().nullable().withLength(max: 20)();
  IntColumn get role =>
      integer().withDefault(const Constant(4))(); // UserRole.viewer.value
  TextColumn get customPermissions =>
      text().nullable()(); // JSON string of additional permissions
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  DateTimeColumn get lastLogin => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
}
