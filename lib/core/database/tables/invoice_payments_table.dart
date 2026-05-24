import 'package:drift/drift.dart';
import 'invoice_table.dart';

/// جدول مدفوعات الفاتورة — يدعم Split Payment (كاش + فيزا + آجل)
/// كل فاتورة يمكن أن يكون لها عدة سجلات دفع
class InvoicePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId =>
      integer().references(Invoices, #id, onDelete: KeyAction.cascade)();
  TextColumn get paymentMethod => text()(); // cash, visa, credit, bank
  RealColumn get amount => real()();
  DateTimeColumn get paidAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();
}
