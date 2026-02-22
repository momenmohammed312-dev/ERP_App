import 'package:drift/drift.dart';
import 'users_table.dart';

class UserActivityLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get action => text()(); // login, logout, create_sale, etc.
  TextColumn get description => text()(); // Human readable description
  TextColumn get entityType =>
      text().nullable()(); // Customer, Product, Invoice, etc.
  IntColumn get entityId => integer().nullable()(); // ID of the affected entity
  TextColumn get oldValue => text().nullable()(); // For updates
  TextColumn get newValue => text().nullable()(); // For updates
  TextColumn get ipAddress => text().nullable()(); // If available
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  TextColumn get sessionId => text().nullable()(); // For session tracking

  @override
  List<String> get customConstraints => [
    'CHECK (entity_type IS NULL OR entity_id IS NOT NULL)',
  ];
}
