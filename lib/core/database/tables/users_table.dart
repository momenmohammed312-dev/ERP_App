import 'package:drift/drift.dart';

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
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastLogin => dateTime().nullable()();
}
