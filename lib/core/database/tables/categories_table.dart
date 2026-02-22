import 'package:drift/drift.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get categoryName => text()();
  TextColumn get description => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(Constant(DateTime.now()))();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
