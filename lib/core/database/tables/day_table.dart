import 'package:drift/drift.dart';

class Days extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  BoolColumn get isOpen => boolean().withDefault(const Constant(false))();
  RealColumn get openingBalance => real().withDefault(const Constant(0.0))();
  RealColumn get closingBalance => real().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get openedBy => text().nullable()();
  TextColumn get closedBy => text().nullable()();
  DateTimeColumn get reopenedAt => dateTime().nullable()();
  TextColumn get reopenedBy => text().nullable()();
}
