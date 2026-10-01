import 'package:drift/drift.dart';

/// جدول العهد المالية
@DataClassName('CashCustody')
class CashCustodies extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// رقم العهدة التسلسلي، مثال: CUST-000001
  TextColumn get custodyNumber => text().unique()();

  /// معرف الموظف أو الشخص المسؤول (من staff_table)
  TextColumn get staffId => text()();

  /// اسم الموظف مسجل كـ denormalized لسرعة العرض والحفاظ على السجل
  TextColumn get staffName => text()();

  /// تاريخ استلام / إنشاء العهدة
  DateTimeColumn get date => dateTime()();

  /// المبلغ الأصلي للعهدة (ثابت لا يتغير بعد الإنشاء)
  RealColumn get amount => real()();

  /// وصف أو غرض العهدة
  TextColumn get description => text().nullable()();

  /// إجمالي المصروفات المسجلة على هذه العهدة
  RealColumn get totalExpenses => real().withDefault(const Constant(0.0))();

  /// المبلغ المتبقي (amount - totalExpenses)
  RealColumn get remainingAmount => real()();

  /// حالة العهدة: 'open' | 'settled' | 'cancelled'
  TextColumn get status => text().withDefault(const Constant('open'))();

  /// تاريخ ووقت الإغلاق والتسوية
  DateTimeColumn get settledAt => dateTime().nullable()();

  /// اسم أو معرف من قام بالتسوية
  TextColumn get settledBy => text().nullable()();

  /// ملاحظات إضافية
  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// جدول مصروفات العهدة المالية
@DataClassName('CustodyExpense')
class CustodyExpenses extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ربط بالمصروف بالعهدة
  IntColumn get custodyId => integer().references(CashCustodies, #id)();

  /// تاريخ تسجيل المصروف
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();

  /// بيان أو وصف المصروف
  TextColumn get description => text().withLength(min: 1, max: 255)();

  /// قيمة المصروف
  RealColumn get amount => real()();

  /// ملاحظات إضافية
  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
