import 'package:drift/drift.dart';

class JournalEntries extends Table {
  TextColumn get id => text()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get postingDate => dateTime().withDefault(currentDateAndTime)();
  TextColumn get description => text()();
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text()();
  TextColumn get postingKey => text()();
  TextColumn get status => text().withDefault(const Constant('posted'))();
  TextColumn get reversalOfId => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
