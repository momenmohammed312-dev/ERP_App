import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/tables/notifications_table.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

part 'notifications_dao.g.dart';

@DriftAccessor(tables: [AppNotifications])
class NotificationsDao extends DatabaseAccessor<AppDatabase>
    with _$NotificationsDaoMixin {
  NotificationsDao(super.db);

  Future<List<AppNotification>> getAllNotifications() =>
      select(appNotifications).get();

  Future<List<AppNotification>> getPendingNotifications() =>
      (select(appNotifications)..where((tbl) => tbl.sent.equals(0))).get();

  Future<List<AppNotification>> getSentNotifications() =>
      (select(appNotifications)..where((tbl) => tbl.sent.equals(1))).get();

  Future<AppNotification> createNotification({
    required String title,
    required String body,
    required DateTime sendAt,
    String? entityId,
  }) async {
    final companion = AppNotificationsCompanion.insert(
      entityId: Value(entityId),
      title: title,
      body: body,
      sendAt: sendAt,
      sent: const Value(0),
    );

    final id = await into(appNotifications).insert(companion);
    return await (select(
      appNotifications,
    )..where((tbl) => tbl.id.equals(id))).getSingle();
  }

  Future<bool> markAsSent(int notificationId) async {
    final result =
        await (update(appNotifications)
              ..where((tbl) => tbl.id.equals(notificationId)))
            .write(const AppNotificationsCompanion(sent: Value(1)));
    return result > 0;
  }

  Future<int> deleteNotification(int id) =>
      (delete(appNotifications)..where((tbl) => tbl.id.equals(id))).go();

  Future<List<AppNotification>> getNotificationsDueBefore(DateTime before) =>
      (select(appNotifications)
            ..where((tbl) => tbl.sendAt.isSmallerThanValue(before))
            ..where((tbl) => tbl.sent.equals(0)))
          .get();
}
