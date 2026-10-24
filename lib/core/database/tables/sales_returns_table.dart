import 'package:drift/drift.dart';
import 'invoice_table.dart';
import 'invoice_items_table.dart';
import 'product_table.dart';
import 'product_variants_table.dart';
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

  // === v78: فصل المرتجع عن الاسترداد ===
  /// كام فلوس اتسترد فعلاً (مجموع return_refunds السارية). فارق عن totalAmount
  /// لأن العميل ممكن ياخد المرتجع رصيد بدل فلوس.
  RealColumn get refundedAmount => real().withDefault(const Constant(0.0))();

  /// 'pending' | 'partially_refunded' | 'refunded' | 'credited'
  TextColumn get settlementStatus =>
      text().withDefault(const Constant('pending'))();

  /// كام رجع للمخزون فعلاً — التالف لا يرجع (restockCondition).
  RealColumn get restockedAmount => real().withDefault(const Constant(0.0))();

  TextColumn get syncId => text().nullable()();
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

  /// صنف المنتج (لون/مقاس/فئة) إن وجد.
  IntColumn get variantId =>
      integer().nullable().references(ProductVariants, #id)();

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

  // === v78 ===
  /// حالة الصنف المرتجع: 'sellable' (يعود للمخزون) | 'damaged' (تالف،
  /// بيروح جدول التالف مش المخزون) | 'supplier' (هيتبعت للمورد).
  TextColumn get restockCondition =>
      text().withDefault(const Constant('sellable'))();

  /// الكمية اللي رجعت للمخزون فعلياً — أقل من [quantity] لو الصنف تالف.
  IntColumn get restockedQty => integer().withDefault(const Constant(0))();

  TextColumn get syncId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
