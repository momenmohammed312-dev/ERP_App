// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_activity_dao.dart';

// ignore_for_file: type=lint
mixin _$UserActivityDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $UserActivityLogTable get userActivityLog => attachedDatabase.userActivityLog;
  UserActivityDaoManager get managers => UserActivityDaoManager(this);
}

class UserActivityDaoManager {
  final _$UserActivityDaoMixin _db;
  UserActivityDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$UserActivityLogTableTableManager get userActivityLog =>
      $$UserActivityLogTableTableManager(
        _db.attachedDatabase,
        _db.userActivityLog,
      );
}
