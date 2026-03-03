import 'package:drift/drift.dart';

import '../tables/notifications_table.dart';
import '../app_database.dart';

part 'notifications_dao.g.dart';

@DriftAccessor(tables: [Notifications])
class NotificationsDao extends DatabaseAccessor<AppDatabase>
    with _$NotificationsDaoMixin {
  NotificationsDao(super.db);

  Future<List<Notification>> getAllNotifications() =>
      select(notifications).get();

  Future<List<Notification>> getPendingNotifications() =>
      (select(notifications)..where((tbl) => tbl.sent.equals(0))).get();

  Future<List<Notification>> getSentNotifications() =>
      (select(notifications)..where((tbl) => tbl.sent.equals(1))).get();

  Future<Notification> createNotification({
    required String title,
    required String body,
    required DateTime sendAt,
    String? entityId,
  }) async {
    final companion = NotificationsCompanion.insert(
      entityId: Value(entityId),
      title: title,
      body: body,
      sendAt: sendAt,
      sent: const Value(0),
    );

    final id = await into(notifications).insert(companion);
    return await (select(
      notifications,
    )..where((tbl) => tbl.id.equals(id))).getSingle();
  }

  Future<bool> markAsSent(int notificationId) async {
    final result =
        await (update(notifications)
              ..where((tbl) => tbl.id.equals(notificationId)))
            .write(const NotificationsCompanion(sent: Value(1)));
    return result > 0;
  }

  Future<int> deleteNotification(int id) =>
      (delete(notifications)..where((tbl) => tbl.id.equals(id))).go();

  Future<List<Notification>> getNotificationsDueBefore(DateTime before) =>
      (select(notifications)
            ..where((tbl) => tbl.sendAt.isSmallerThanValue(before))
            ..where((tbl) => tbl.sent.equals(0)))
          .get();
}
