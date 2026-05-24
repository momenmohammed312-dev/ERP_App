import 'package:drift/drift.dart';
import 'product_table.dart';

/// جدول الهالك والتالف — يُسجِّل المنتجات التالفة أو المنتهية الصلاحية
@DataClassName('DamagedItem')
class DamagedItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get quantity => integer()();
  RealColumn get unitCost => real()(); // تكلفة الوحدة وقت التسجيل
  RealColumn get totalLoss => real()(); // إجمالي الخسارة = quantity * unitCost
  TextColumn get reason => text()(); // damaged, expired, theft, other
  DateTimeColumn get damageDate => dateTime()();
  TextColumn get notes => text().nullable()();
  TextColumn get recordedBy => text().nullable()(); // username of recorder
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
