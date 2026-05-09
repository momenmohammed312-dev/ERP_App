import 'package:drift/drift.dart';

/// Cash Session table for managing daily cash operations
/// يتحكم في فتح وإغلاق الصندوق يومياً
class CashSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get openedBy => text().nullable()();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('closed'))(); // "open" | "closed"
  RealColumn get openingBalance => real().withDefault(const Constant(0.0))();
}
