import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_table.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_items_table.dart';
import '../../models/report_dtos.dart';

part 'invoice_dao.g.dart';

@DriftAccessor(tables: [Invoices, InvoiceItems])
class InvoiceDao extends DatabaseAccessor<AppDatabase> with _$InvoiceDaoMixin {
  InvoiceDao(super.db);

  // === Invoice CRUD ===
  Future<List<Invoice>> getAllInvoices() => select(invoices).get();

  Future<Invoice?> getInvoiceByNumber(String number) {
    return (select(
      invoices,
    )..where((t) => t.invoiceNumber.equals(number))).getSingleOrNull();
  }

  Stream<List<Invoice>> watchAllInvoices() => select(invoices).watch();

  Future<int> insertInvoice(InvoicesCompanion invoice) =>
      into(invoices).insert(invoice);

  Future updateInvoice(Insertable<Invoice> invoice) =>
      update(invoices).replace(invoice);

  Future deleteInvoice(Insertable<Invoice> invoice) =>
      delete(invoices).delete(invoice);

  Future<void> voidInvoice(int invoiceId, String reason, String voidedBy) async {
    return transaction(() async {
      final invoice = await (select(invoices)..where((t) => t.id.equals(invoiceId))).getSingleOrNull();
      if (invoice == null) throw Exception('Invoice not found');
      
      await (update(invoices)..where((t) => t.id.equals(invoiceId))).write(
        InvoicesCompanion(
          status: const Value('voided'),
          voidedAt: Value(DateTime.now()),
          voidReason: Value(reason),
          voidedBy: Value(voidedBy),
        ),
      );

      final items = await getItemsByInvoiceId(invoiceId);
      final productsTable = attachedDatabase.products;
      for (final item in items) {
        final product = await (select(productsTable)..where((p) => p.id.equals(item.productId))).getSingleOrNull();
        if (product != null) {
          await (update(productsTable)..where((p) => p.id.equals(product.id))).write(
            ProductsCompanion(
              quantity: Value(product.quantity + item.quantity),
            ),
          );
        }
      }
    });
  }

  // === Invoice Items ===
  Future<List<InvoiceItem>> getItemsByInvoiceId(int invoiceId) {
    return (select(
      invoiceItems,
    )..where((item) => item.invoiceId.equals(invoiceId))).get();
  }

  Future insertInvoiceItem(Insertable<InvoiceItem> item) =>
      into(invoiceItems).insert(item);

  Future deleteItemsByInvoiceId(int invoiceId) {
    return (delete(
      invoiceItems,
    )..where((item) => item.invoiceId.equals(invoiceId))).go();
  }

  // Query to get items for a specific invoice
  Future<List<InvoiceItem>> getInvoiceItems(int invoiceId) {
    return (select(
      invoiceItems,
    )..where((tbl) => tbl.invoiceId.equals(invoiceId))).get();
  }

  Future<List<(InvoiceItem, Product?)>> getItemsWithProductsByInvoice(
    int invoiceId,
  ) {
    final productsTable = attachedDatabase.products;
    final query = select(invoiceItems).join([
      leftOuterJoin(productsTable, productsTable.id.equalsExp(invoiceItems.productId)),
    ])..where(invoiceItems.invoiceId.equals(invoiceId));

    return query.map((row) {
      return (row.readTable(invoiceItems), row.readTableOrNull(productsTable));
    }).get();
  }

  // === Reporting / Dashboard ===
  Future<List<Invoice>> getInvoicesByDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);

    return (select(invoices)
          ..where((t) => t.date.isBetweenValues(start, end))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Future<List<Invoice>> getInvoicesByDateRange(DateTime start, DateTime end) {
    return (select(invoices)
          ..where((t) => t.date.isBetweenValues(start, end))
          ..where((t) => t.status.equals('voided').not())
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Future<List<Invoice>> getInvoicesByDateRangeAndType(
    DateTime start,
    DateTime end,
    List<String> types,
  ) {
    return (select(invoices)
          ..where((t) => t.date.isBetweenValues(start, end))
          ..where((t) => t.status.equals('voided').not())
          ..where((t) => t.paymentMethod.isIn(types) | t.paymentMethod.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Future<double> getTotalReceivables() async {
    final customerList = await attachedDatabase.customerDao.getAllCustomers();
    double total = 0;
    for (final customer in customerList) {
      final balance = await attachedDatabase.ledgerDao.getCustomerBalance(customer.id);
      final finalBalance = balance + customer.openingBalance;
      if (finalBalance > 0) {
        total += finalBalance;
      }
    }
    return total;
  }

  /// Search invoices by a free-text query. Matches customer name (LIKE)
  /// or invoice id when the query is numeric.
  Future<List<Invoice>> searchInvoices(String query) async {
    final q = query.trim();
    final asInt = int.tryParse(q);

    final stmt = select(invoices);

    if (asInt != null) {
      stmt.where((t) => t.id.equals(asInt));
    } else if (q.isNotEmpty) {
      stmt.where((t) => t.customerName.like('%$q%'));
    }

    return stmt.get();
  }

  // === Reporting Methods ===
  Future<List<InvoiceReportDTO>> getInvoicesWithDetails(
    DateTime start,
    DateTime end,
  ) async {
    // 1. Get filtered invoices joined with customers
    final query =
        select(invoices).join([
            leftOuterJoin(
              attachedDatabase.customers,
              attachedDatabase.customers.id.equalsExp(invoices.customerId),
            ),
          ])
          ..where(invoices.date.isBetweenValues(start, end))
          ..orderBy([
            OrderingTerm(expression: invoices.date, mode: OrderingMode.desc),
          ]);

    final rows = await query.get();
    final List<InvoiceReportDTO> reportData = [];

    for (final row in rows) {
      final invoice = row.readTable(invoices);
      final customer = row.readTableOrNull(attachedDatabase.customers);

      // Get items with product details
      final items = await getItemsWithProductsByInvoice(invoice.id);

      final productNames = items
          .map((item) {
            final product = item.$2;
            return product?.name ?? 'Unknown Product';
          })
          .join(', ');

      reportData.add(
        InvoiceReportDTO(
          id: invoice.id,
          invoiceNumber: invoice.invoiceNumber ?? invoice.id.toString(),
          date: invoice.date,
          customerName:
              customer?.name ?? invoice.customerName ?? 'Walk-in Customer',
          productNames: productNames,
          totalAmount: invoice.totalAmount,
          paidAmount: invoice.paidAmount,
          remainingAmount: invoice.totalAmount - invoice.paidAmount,
          status: invoice.status,
        ),
      );
    }
    return reportData;
  }
}
