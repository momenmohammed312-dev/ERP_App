import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

/// Sentinel customer id used to track برنيكه given out in walk-in / cash sales
/// (invoices without a selected customer).
const String kWalkInCustomerId = '__walkin__';
const String kWalkInCustomerName = 'نقدي / بدون عميل';

class CustomerContainers extends Table {
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get customerId => text()(); // non-null; uses a sentinel for walk-in sales
  IntColumn get quantityOut => integer().withDefault(const Constant(0))(); // Barnekas given out (auto + editable)
  IntColumn get quantityReturned => integer().withDefault(const Constant(0))(); // Barnekas returned (manual)
  DateTimeColumn get date => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {productId, customerId};
}
