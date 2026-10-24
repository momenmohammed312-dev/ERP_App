import 'package:drift/drift.dart';
import 'customer_table.dart';
import 'manufacturing_orders_table.dart';
import 'product_table.dart';

/// Customer Material Receipt — records goods delivered by a customer for manufacturing.
@DataClassName('CustomerMaterialReceipt')
class CustomerMaterialReceipts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// e.g. CMR-2026-0001
  TextColumn get receiptNumber => text().unique()();

  /// Customer who supplied the material (TEXT UUID)
  TextColumn get customerId => text().references(Customers, #id)();

  /// Optional manufacturing order this delivery was received for
  IntColumn get manufacturingOrderId =>
      integer().nullable().references(ManufacturingOrders, #id)();

  DateTimeColumn get receivedDate => dateTime().withDefault(currentDateAndTime)();

  /// 'draft' | 'received' | 'cancelled'
  TextColumn get status => text().withDefault(const Constant('received'))();

  TextColumn get notes => text().nullable()();
  TextColumn get receivedBy => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Line items on a customer material receipt.
@DataClassName('CustomerMaterialReceiptItem')
class CustomerMaterialReceiptItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get receiptId =>
      integer().references(CustomerMaterialReceipts, #id, onDelete: KeyAction.cascade)();

  /// Product catalog reference (e.g. Blank T-Shirt)
  IntColumn get productId => integer().references(Products, #id)();

  /// Gross quantity received (e.g. 310)
  RealColumn get quantityReceived => real()();

  /// Quantity rejected upon receipt inspection (e.g. 10)
  RealColumn get quantityDefectiveAtReceipt =>
      real().withDefault(const Constant(0.0))();

  /// Net accepted quantity entering custody (e.g. 300)
  RealColumn get quantityAccepted => real()();

  TextColumn get color => text().nullable()();
  TextColumn get size => text().nullable()();
  TextColumn get unit => text().nullable()();
  TextColumn get rejectionReason => text().nullable()();
  TextColumn get notes => text().nullable()();
}

/// On-hand and allocated customer-owned stock balances (separate custody bucket).
@DataClassName('CustomerStockBalance')
class CustomerStockBalances extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get customerId => text().references(Customers, #id)();
  IntColumn get productId => integer().references(Products, #id)();

  TextColumn get color => text().nullable()();
  TextColumn get size => text().nullable()();

  RealColumn get quantityOnHand => real().withDefault(const Constant(0.0))();
  RealColumn get quantityAllocated => real().withDefault(const Constant(0.0))();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Audit ledger for movements in customer-owned materials.
@DataClassName('CustomerStockMovement')
class CustomerStockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get customerId => text().references(Customers, #id)();
  IntColumn get productId => integer().references(Products, #id)();

  /// 'receipt' | 'return_defect' | 'issued_to_order' | 'delivered' | 'scrapped'
  TextColumn get movementType => text()();

  /// Positive for in, negative for out
  RealColumn get quantity => real()();

  /// 'customer_material_receipt' | 'manufacturing_order' | 'manufacturing_delivery'
  TextColumn get referenceType => text()();
  TextColumn get referenceId => text()();

  TextColumn get color => text().nullable()();
  TextColumn get size => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get performedBy => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
