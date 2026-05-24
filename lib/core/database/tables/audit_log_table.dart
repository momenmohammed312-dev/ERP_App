import 'package:drift/drift.dart';

@DataClassName('AuditLogData')
class AuditLog extends Table {
  TextColumn get id => text()();
  IntColumn get userId => integer().nullable()();
  TextColumn get action => text()();
  TextColumn get tableNameField => text()();
  IntColumn get recordId => integer().nullable()();
  TextColumn get details => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get ipAddress => text().nullable()();
  TextColumn get oldValue => text().nullable()(); // JSON snapshot before change
  TextColumn get newValue => text().nullable()(); // JSON snapshot after change

  @override
  Set<Column> get primaryKey => {id};
}
