import 'package:drift/drift.dart';

import 'tables.dart';

@DataClassName('Sale')
class Sales extends Table {
  TextColumn get id => text()(); // UUID primary key
  TextColumn get employeeId => text()(); // Foreign key to Employees
  IntColumn get invoiceId => integer().nullable().references(
    Invoices,
    #id,
  )(); // Foreign key to Invoices
  RealColumn get total => real().withDefault(const Constant(0.0))();
  DateTimeColumn get date => dateTime()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get status => text().nullable().withDefault(
    const Constant('completed'),
  )(); // completed, pending, cancelled
  DateTimeColumn get createdAt =>
      dateTime().nullable().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
