// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'journal_dao.dart';

// ignore_for_file: type=lint
mixin _$JournalDaoMixin on DatabaseAccessor<AppDatabase> {
  $JournalEntriesTable get journalEntries => attachedDatabase.journalEntries;
  $AccountsTable get accounts => attachedDatabase.accounts;
  $JournalLinesTable get journalLines => attachedDatabase.journalLines;
  JournalDaoManager get managers => JournalDaoManager(this);
}

class JournalDaoManager {
  final _$JournalDaoMixin _db;
  JournalDaoManager(this._db);
  $$JournalEntriesTableTableManager get journalEntries =>
      $$JournalEntriesTableTableManager(
        _db.attachedDatabase,
        _db.journalEntries,
      );
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db.attachedDatabase, _db.accounts);
  $$JournalLinesTableTableManager get journalLines =>
      $$JournalLinesTableTableManager(_db.attachedDatabase, _db.journalLines);
}
