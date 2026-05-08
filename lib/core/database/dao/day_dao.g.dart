// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'day_dao.dart';

// ignore_for_file: type=lint
mixin _$DayDaoMixin on DatabaseAccessor<AppDatabase> {
  $DaysTable get days => attachedDatabase.days;
  DayDaoManager get managers => DayDaoManager(this);
}

class DayDaoManager {
  final _$DayDaoMixin _db;
  DayDaoManager(this._db);
  $$DaysTableTableManager get days =>
      $$DaysTableTableManager(_db.attachedDatabase, _db.days);
}
