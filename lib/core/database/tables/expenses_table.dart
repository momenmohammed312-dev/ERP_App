import 'package:drift/drift.dart';

class Expenses extends Table {
  TextColumn get id => text()(); // Primary key

  TextColumn get description =>
      text().withLength(min: 1, max: 255)(); // Expense description

  RealColumn get amount => real()(); // Expense amount

  DateTimeColumn get date =>
      dateTime().withDefault(currentDateAndTime)(); // Expense date

  TextColumn get category =>
      text().withLength(min: 1, max: 100)(); // Expense category

  TextColumn get paymentMethod =>
      text().withDefault(const Constant('cash'))(); // 'cash' | 'bank' | 'card'

  TextColumn get receiptNumber =>
      text().nullable()(); // Optional receipt/invoice number

  TextColumn get supplierId =>
      text().nullable()(); // Optional supplier reference

  TextColumn get notes => text().nullable()(); // Optional notes

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)(); // Creation timestamp

  TextColumn get userId => text().nullable()(); // Who added this expense
  TextColumn get dayId => text().nullable()(); // Which business day

  @override
  Set<Column> get primaryKey => {id};
}
