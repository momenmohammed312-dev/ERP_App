import 'package:drift/drift.dart';
import 'invoice_table.dart';
import 'invoice_items_table.dart';
import 'product_table.dart';
import 'vegetable_shipments_table.dart';

/// جدول مرتجعات المبيعات الرئيسي
@DataClassName('SalesReturn')
class SalesReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get returnNumber => text()(); // مثال: RET-20260516-0001
  IntColumn get originalInvoiceId =>
      integer().references(Invoices, #id)(); // FK للفاتورة الأصلية
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text()();
  DateTimeColumn get returnDate => dateTime()();
  RealColumn get totalAmount => real()(); // إجمالي قيمة المرتجع
  TextColumn get returnReason =>
      text()(); // defective, wrong_item, customer_request, other
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get processedBy => text().nullable()(); // username
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// جدول أصناف مرتجعات المبيعات — يدعم المرتجع الجزئي على مستوى الصنف
/// كل سطر يرتبط بسطر الفاتورة الأصلي عبر invoiceItemId لتتبع الكمية المرتجعة تراكمياً
@DataClassName('SalesReturnItem')
class SalesReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(
    SalesReturns,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get productName => text()(); // snapshot of name
  IntColumn get quantity => integer()();
  RealColumn get unitPrice => real()();
  RealColumn get totalPrice => real()(); // quantity * unitPrice

  // === جزئي: ربط بسطر الفاتورة الأصلي ===
  IntColumn get invoiceItemId =>
      integer().nullable().references(InvoiceItems, #id)();
  RealColumn get discount => real().withDefault(const Constant(0.0))();
  RealColumn get commission => real().withDefault(const Constant(0.0))();
  IntColumn get shipmentId =>
      integer().nullable().references(VegetableShipments, #id)();
  TextColumn get returnReason =>
      text().withDefault(const Constant('customer_request'))();
}
