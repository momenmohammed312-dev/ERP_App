// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notifications_dao.dart';

// ignore_for_file: type=lint
mixin _$NotificationsDaoMixin on DatabaseAccessor<AppDatabase> {
  $AppNotificationsTable get appNotifications =>
      attachedDatabase.appNotifications;
  NotificationsDaoManager get managers => NotificationsDaoManager(this);
}

class NotificationsDaoManager {
  final _$NotificationsDaoMixin _db;
  NotificationsDaoManager(this._db);
  $$AppNotificationsTableTableManager get appNotifications =>
      $$AppNotificationsTableTableManager(
        _db.attachedDatabase,
        _db.appNotifications,
      );
}
