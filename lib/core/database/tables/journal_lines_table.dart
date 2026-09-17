import 'package:drift/drift.dart';
import 'journal_entries_table.dart';
import 'accounts_table.dart';

class JournalLines extends Table {
  TextColumn get id => text()();
  TextColumn get journalEntryId => text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId => text().references(Accounts, #id)();
  RealColumn get debit => real().withDefault(const Constant(0.0))();
  RealColumn get credit => real().withDefault(const Constant(0.0))();
  TextColumn get memo => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
