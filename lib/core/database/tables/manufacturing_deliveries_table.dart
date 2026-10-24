import 'package:drift/drift.dart';
import 'customer_table.dart';
import 'manufacturing_orders_table.dart';
import 'product_table.dart';

/// Manufacturing Delivery (Delivery Note) — documents finished goods handed over to the customer.
@DataClassName('ManufacturingDelivery')
class ManufacturingDeliveries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// e.g. DN-2026-0001
  TextColumn get deliveryNumber => text().unique()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id)();

  TextColumn get customerId => text().references(Customers, #id)();

  DateTimeColumn get deliveryDate => dateTime().withDefault(currentDateAndTime)();

  /// 'draft' | 'delivered' | 'cancelled'
  TextColumn get status => text().withDefault(const Constant('delivered'))();

  TextColumn get deliveredBy => text().nullable()();
  TextColumn get receiverName => text().nullable()();
  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Delivery item line.
@DataClassName('ManufacturingDeliveryItem')
class ManufacturingDeliveryItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get deliveryId =>
      integer().references(ManufacturingDeliveries, #id, onDelete: KeyAction.cascade)();

  IntColumn get productId => integer().references(Products, #id)();

  RealColumn get quantity => real()();
  TextColumn get color => text().nullable()();
  TextColumn get size => text().nullable()();
  TextColumn get notes => text().nullable()();
}
