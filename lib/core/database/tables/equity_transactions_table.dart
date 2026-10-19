import 'package:drift/drift.dart';
import 'partners_table.dart';

class EquityTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get partnerId => text().references(Partners, #id)();
  TextColumn get type => text()(); // opening_capital | capital_contribution | withdrawal | profit_allocation
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime()();
  TextColumn get description => text().nullable()();
  TextColumn get journalEntryId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
