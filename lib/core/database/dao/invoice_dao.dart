import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_table.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_items_table.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_containers_table.dart';
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

  Future<int> insertInvoice(InvoicesCompanion invoice) async {
    final syncId = const Uuid().v4();
    final now = DateTime.now();
    final decorated = invoice.copyWith(
      syncId: Value(syncId),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    final invoiceId = await into(invoices).insert(decorated);
    await _enqueueInvoice(invoiceId, 'insert');
    return invoiceId;
  }

  Future updateInvoice(Insertable<Invoice> invoice) async {
    Insertable<Invoice> decorated = invoice;
    int? localId;
    if (invoice is InvoicesCompanion) {
      decorated = invoice.copyWith(updatedAt: Value(DateTime.now()));
      localId = invoice.id.value;
    } else if (invoice is Invoice) {
      decorated = invoice.copyWith(updatedAt: Value(DateTime.now()));
      localId = invoice.id;
    }
    await update(invoices).replace(decorated);
    if (localId != null) {
      await _enqueueInvoice(localId, 'update');
    }
  }

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

  Future insertInvoiceItem(Insertable<InvoiceItem> item) async {
    final syncId = const Uuid().v4();
    final now = DateTime.now();
    Insertable<InvoiceItem> decorated = item;
    int? invoiceLocalId;
    int? productLocalId;
    if (item is InvoiceItemsCompanion) {
      decorated = item.copyWith(
        syncId: Value(syncId),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
      invoiceLocalId = item.invoiceId.value;
      productLocalId = item.productId.value;
    } else if (item is InvoiceItem) {
      decorated = item.copyWith(
        syncId: Value(syncId),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
      invoiceLocalId = item.invoiceId;
      productLocalId = item.productId;
    }
    await into(invoiceItems).insert(decorated);
    await _enqueueInvoiceItem(syncId, invoiceLocalId, productLocalId, item);
  }

  /// Writes an invoice pulled from Supabase without re-enqueueing it for push.
  /// Looks up an existing local row by `syncId`: if found, updates it only when
  /// the remote `updatedAt` is newer than the local one (last-write-wins); if
  /// not found, inserts a new local row with the same `syncId`. `customerId` is
  /// already a UUID text column, so the remote `customer_sync_id` maps straight
  /// in — no FK remapping needed.
  Future<void> upsertInvoiceFromRemote(Map<String, dynamic> remoteRow) async {
    final syncId = remoteRow['sync_id'] as String?;
    if (syncId == null || syncId.isEmpty) return;
    final remoteUpdated =
        DateTime.tryParse(remoteRow['updated_at'] as String? ?? '');
    final existing = await (select(invoices)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingleOrNull();

    if (existing != null &&
        existing.updatedAt != null &&
        remoteUpdated != null &&
        existing.updatedAt!.isAfter(remoteUpdated)) {
      return; // local row is newer — keep it.
    }

    // Resolve the customer's display fields from the LOCAL Customers table at
    // pull time. pullNow() always pulls customers before invoices, so the
    // customer row is already local here. We deliberately do NOT read these
    // names from the remote invoice row (there is no customer_name column on
    // the Supabase invoices table) and do NOT add denormalized copies: that
    // would create a second, staler copy of the name that drifts if the
    // customer is renamed later. Fall back to null if the customer genuinely
    // isn't found — same shape as a locally-created invoice whose customer
    // was deleted there.
    String? customerName;
    String? customerContact;
    String? customerAddress;
    final custId = remoteRow['customer_sync_id'] as String?;
    if (custId != null) {
      final customer = await (select(attachedDatabase.customers)
            ..where((c) => c.id.equals(custId)))
          .getSingleOrNull();
      customerName = customer?.name;
      customerContact = customer?.phone;
      customerAddress = customer?.address;
    }

    final companion = InvoicesCompanion(
      syncId: Value(syncId),
      invoiceNumber: Value(remoteRow['invoice_number'] as String?),
      customerId: Value(custId),
      customerName: Value(customerName),
      customerContact: Value(customerContact),
      customerAddress: Value(customerAddress),
      totalAmount: Value((remoteRow['total_amount'] as num?)?.toDouble() ?? 0),
      paidAmount: Value((remoteRow['paid_amount'] as num?)?.toDouble() ?? 0),
      status: Value(remoteRow['status'] as String? ?? 'pending'),
      date: Value(DateTime.tryParse(remoteRow['invoice_date'] as String? ?? '') ?? DateTime.now().toUtc()),
      updatedAt: Value(remoteUpdated),
    );

    if (existing != null) {
      await (update(invoices)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    } else {
      await into(invoices).insert(companion);
    }
  }

  /// Writes an invoice item pulled from Supabase without re-enqueueing it for
  /// push. `InvoiceItems.invoiceId`/`productId` are LOCAL integer FKs, so the
  /// remote UUIDs (`invoice_sync_id`/`product_sync_id`) must first be resolved
  /// to local int ids. If either parent (invoice or product) has not been pulled
  /// locally yet, the row is skipped — returns `false` — rather than inserting
  /// a broken/null FK. Returns `true` when the row was written (or was a no-op
  /// because the local copy is already newer).
  Future<bool> upsertInvoiceItemFromRemote(Map<String, dynamic> remoteRow) async {
    final syncId = remoteRow['sync_id'] as String?;
    if (syncId == null || syncId.isEmpty) return false;

    // Resolve remote UUIDs -> local integer FKs.
    final invoiceSyncId = remoteRow['invoice_sync_id'] as String?;
    final productSyncId = remoteRow['product_sync_id'] as String?;
    int? invoiceLocalId;
    int? productLocalId;
    if (invoiceSyncId != null) {
      final inv = await (select(invoices)
            ..where((t) => t.syncId.equals(invoiceSyncId)))
          .getSingleOrNull();
      invoiceLocalId = inv?.id;
    }
    if (productSyncId != null) {
      final product = await (select(attachedDatabase.products)
            ..where((p) => p.syncId.equals(productSyncId)))
          .getSingleOrNull();
      productLocalId = product?.id;
    }
    if (invoiceLocalId == null || productLocalId == null) {
      return false; // parent not pulled locally yet — skip, do not guess.
    }

    final remoteUpdated =
        DateTime.tryParse(remoteRow['updated_at'] as String? ?? '');
    final existing = await (select(invoiceItems)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingleOrNull();

    if (existing != null &&
        existing.updatedAt != null &&
        remoteUpdated != null &&
        existing.updatedAt!.isAfter(remoteUpdated)) {
      return true; // local row is newer — keep it.
    }

    final companion = InvoiceItemsCompanion(
      syncId: Value(syncId),
      invoiceId: Value(invoiceLocalId),
      productId: Value(productLocalId),
      quantity: Value((remoteRow['quantity'] as num?)?.toInt() ?? 1),
      price: Value((remoteRow['price'] as num?)?.toDouble() ?? 0),
      discount: Value((remoteRow['discount'] as num?)?.toDouble() ?? 0),
      updatedAt: Value(remoteUpdated),
    );

    if (existing != null) {
      await (update(invoiceItems)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    } else {
      await into(invoiceItems).insert(companion);
    }
    return true;
  }

  /// Enqueues an invoice for sync. Only Supabase columns (snake_case) are sent;
  /// `customer_sync_id` is the customer UUID (never a local int id).
  Future<void> _enqueueInvoice(int localId, String operation) async {
    try {
      final inv = await (select(invoices)..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      final syncId = inv?.syncId;
      if (inv == null || syncId == null) return;
      await db.syncQueueDao.enqueue(
        tableName: 'invoices',
        recordSyncId: syncId,
        operation: operation,
        payload: {
          'sync_id': syncId,
          'invoice_number': inv.invoiceNumber,
          'customer_sync_id': inv.customerId,
          'total_amount': inv.totalAmount,
          'paid_amount': inv.paidAmount,
          'status': inv.status,
          'invoice_date': inv.date.toUtc().toIso8601String(),
          'updated_at': (inv.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        },
      );
    } catch (e) {
      print('Enqueue invoice ($operation) failed: $e');
    }
  }

  /// Enqueues an invoice item for sync. Resolves the parent invoice's syncId
  /// and the product's syncId from their local ids so the payload never leaks
  /// local integer ids to the server.
  Future<void> _enqueueInvoiceItem(
    String syncId,
    int? invoiceLocalId,
    int? productLocalId,
    Insertable<InvoiceItem> item,
  ) async {
    try {
      String? invoiceSyncId;
      if (invoiceLocalId != null) {
        final inv = await (select(invoices)..where((t) => t.id.equals(invoiceLocalId)))
            .getSingleOrNull();
        invoiceSyncId = inv?.syncId;
      }
      String? productSyncId;
      if (productLocalId != null) {
        final product = await (select(attachedDatabase.products)
              ..where((p) => p.id.equals(productLocalId)))
            .getSingleOrNull();
        productSyncId = product?.syncId;
      }
      if (invoiceSyncId == null || productSyncId == null) return;

      int? qty;
      double? price;
      double? discount;
      if (item is InvoiceItemsCompanion) {
        qty = item.quantity.present ? item.quantity.value : null;
        price = item.price.present ? item.price.value : null;
        discount = item.discount.present ? item.discount.value : null;
      } else if (item is InvoiceItem) {
        qty = item.quantity;
        price = item.price;
        discount = item.discount;
      }

      await db.syncQueueDao.enqueue(
        tableName: 'invoice_items',
        recordSyncId: syncId,
        operation: 'insert',
        payload: {
          'sync_id': syncId,
          'invoice_sync_id': invoiceSyncId,
          'product_sync_id': productSyncId,
          'quantity': qty,
          'price': price,
          'discount': discount,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
    } catch (e) {
      print('Enqueue invoice item failed: $e');
    }
  }

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

  Future<List<(InvoiceItem, Invoice, Product?)>> getItemsWithDetailsByShipment(
    int shipmentId,
  ) {
    final productsTable = attachedDatabase.products;
    final query = select(invoiceItems).join([
      innerJoin(invoices, invoices.id.equalsExp(invoiceItems.invoiceId)),
      leftOuterJoin(productsTable, productsTable.id.equalsExp(invoiceItems.productId)),
    ])..where(invoiceItems.shipmentId.equals(shipmentId));

    return query.map((row) {
      return (
        row.readTable(invoiceItems),
        row.readTable(invoices),
        row.readTableOrNull(productsTable),
      );
    }).get();
  }

  // === Reporting / Dashboard ===
  Future<List<Invoice>> getInvoicesByDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);

    return (select(invoices)
          ..where((t) => t.date.isBetweenValues(start, end))
          ..where((t) => t.status.equals('voided').not())
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Today's cash sales total: sum of the cash portion of non-voided invoices
  /// on [date] where the cash portion is strictly positive.
  /// Used by the day-close settlement view (vegetable flavor).
  Future<double> getTotalCashSalesForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final query = selectOnly(invoices)
      ..addColumns([invoices.cashAmount.sum()])
      ..where(invoices.date.isBetweenValues(start, end))
      ..where(invoices.status.equals('voided').not())
      ..where(invoices.cashAmount.isBiggerThanValue(0));

    final row = await query.getSingle();
    return row.read(invoices.cashAmount.sum()) ?? 0.0;
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
  /// Returns, for a given product, how many units were sold to each customer
  /// within [start]–[end]. Each sold unit counts as one برنيكه (1:1).
  /// Walk-in / cash sales (no customer) are grouped under [kWalkInCustomerId].
  Future<List<ProductSalesByCustomer>> getProductSalesByCustomer(
    int productId,
    DateTime start,
    DateTime end,
  ) async {
    final query = select(invoiceItems).join([
      innerJoin(invoices, invoices.id.equalsExp(invoiceItems.invoiceId)),
    ])
      ..where(invoiceItems.productId.equals(productId))
      ..where(invoices.date.isBetweenValues(start, end))
      ..where(invoices.status.equals('voided').not());

    final rows = await query.get();
    final Map<String, ProductSalesByCustomer> map = {};

    for (final row in rows) {
      final item = row.readTable(invoiceItems);
      final inv = row.readTable(invoices);
      final isWalkIn = inv.customerId == null;
      final cid = isWalkIn ? kWalkInCustomerId : inv.customerId!;
      final name = isWalkIn ? kWalkInCustomerName : (inv.customerName ?? '');
      final existing = map[cid];
      if (existing == null) {
        map[cid] = ProductSalesByCustomer(
          customerId: cid,
          customerName: name,
          totalQty: item.quantity,
        );
      } else {
        map[cid] = existing.copyWith(totalQty: existing.totalQty + item.quantity);
      }
    }

    return map.values.toList();
  }

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

/// Lightweight result of [InvoiceDao.getProductSalesByCustomer]:
/// how many units of a product were sold to a customer in a date range.
class ProductSalesByCustomer {
  final String customerId;
  final String customerName;
  final int totalQty;

  const ProductSalesByCustomer({
    required this.customerId,
    required this.customerName,
    required this.totalQty,
  });

  ProductSalesByCustomer copyWith({
    String? customerId,
    String? customerName,
    int? totalQty,
  }) =>
      ProductSalesByCustomer(
        customerId: customerId ?? this.customerId,
        customerName: customerName ?? this.customerName,
        totalQty: totalQty ?? this.totalQty,
      );
}
