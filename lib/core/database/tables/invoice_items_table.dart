import 'package:drift/drift.dart';
import 'invoice_table.dart';
import 'product_table.dart';

class InvoiceItems extends Table {
  IntColumn get id => integer().autoIncrement()(); // Primary key

  IntColumn get invoiceId =>
      integer().references(Invoices, #id)(); // FK to Invoices
  IntColumn get productId =>
      integer().references(Products, #id)(); // FK to Products

  IntColumn get quantity => integer().withDefault(const Constant(1))();
  IntColumn get ctn => integer().nullable()();
  RealColumn get price => real()();
  RealColumn get discount => real().withDefault(const Constant(0))(); // Discount per line
  RealColumn get commission => real().withDefault(const Constant(0))(); // Commission per line
  RealColumn get unitCostAtTime => real().nullable()(); // Snapshot of costPrice at time of sale
}
