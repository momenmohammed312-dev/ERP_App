import 'package:drift/drift.dart';

/// ملخص شهري مستورد من الورق: تأخير/إضافي/إذن/غياب — منفصل عن سجلات الحضور اليومية
/// period = '2026-08' , lateHours/extra/overtime منفصلة
@DataClassName('MonthlyAttendanceSummary')
class MonthlyAttendanceSummaryTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get staffId => text()(); // STAFFxxxx
  TextColumn get period => text()(); // '2026-08'
  RealColumn get lateHours => real().withDefault(const Constant(0))(); // ساعات تأخير إجمالي
  RealColumn get overtimeHours => real().withDefault(const Constant(0))(); // ساعات إضافي
  RealColumn get excusedHours => real().withDefault(const Constant(0))(); // ساعات إذن منفصلة
  IntColumn get absentDays => integer().withDefault(const Constant(0))(); // أيام غياب
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [{staffId, period}];
}
