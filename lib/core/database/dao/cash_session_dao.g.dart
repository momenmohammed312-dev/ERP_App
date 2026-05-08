// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cash_session_dao.dart';

// ignore_for_file: type=lint
mixin _$CashSessionDaoMixin on DatabaseAccessor<AppDatabase> {
  $CashSessionsTable get cashSessions => attachedDatabase.cashSessions;
  CashSessionDaoManager get managers => CashSessionDaoManager(this);
}

class CashSessionDaoManager {
  final _$CashSessionDaoMixin _db;
  CashSessionDaoManager(this._db);
  $$CashSessionsTableTableManager get cashSessions =>
      $$CashSessionsTableTableManager(_db.attachedDatabase, _db.cashSessions);
}
