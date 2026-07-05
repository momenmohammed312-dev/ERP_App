import 'package:drift/drift.dart';

/// Stores attendance-related configuration settings as key-value pairs
@DataClassName('AttendanceSetting')
class AttendanceSettings extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get settingKey => text().unique()();

  TextColumn get settingValue => text()();

  TextColumn get description => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}
