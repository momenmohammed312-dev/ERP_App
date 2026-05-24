import 'package:drift/drift.dart';

/// Notifications table for license expiry warnings and system alerts
/// جدول الإشعارات لتحذيرات انتهاء الترخيص والتنبيهات النظامية
class AppNotifications extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityId => text().nullable()(); // license_id or user_id
  TextColumn get title => text()();
  TextColumn get body => text()();
  DateTimeColumn get sendAt => dateTime()();
  IntColumn get sent => integer().withDefault(
    const Constant(0),
  )(); // 0=pending, 1=sent (idempotency)

  @override
  List<String> get customConstraints => [
    'CHECK(sent IN (0,1))', // Ensure sent is only 0 or 1
  ];
}
