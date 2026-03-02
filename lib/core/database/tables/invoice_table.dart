import 'package:drift/drift.dart';

class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()(); // Primary key

  TextColumn get invoiceNumber => text().nullable().withLength(max: 255)();
  TextColumn get customerId =>
      text().nullable()(); // Link to customer table for credit customers
  TextColumn get customerName => text().nullable().withLength(max: 255)();
  TextColumn get customerContact => text().nullable()();
  TextColumn get customerAddress => text().nullable()();
  TextColumn get paymentMethod =>
      text().nullable()(); // 'cash' | 'credit' | 'visa' | 'bank' - مهم جداً
  RealColumn get totalAmount => real().withDefault(const Constant(0))();
  RealColumn get paidAmount =>
      real().withDefault(const Constant(0))(); // Track partial payments
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // 'pending' | 'paid' | 'partial'

  // primaryKey is defined by autoIncrement() on 'id'
}
