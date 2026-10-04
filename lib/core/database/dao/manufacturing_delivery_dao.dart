import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_material_receipts_table.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_table.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_items_table.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_table.dart';
import 'package:pos_offline_desktop/core/database/tables/ledger_transactions_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_deliveries_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

part 'manufacturing_delivery_dao.g.dart';

/// Line item input for [ManufacturingDeliveryDao.createDelivery].
class DeliveryItemInput {
  final int productId;
  final double quantity;
  final String? color;
  final String? size;
  final String? notes;

  const DeliveryItemInput({
    required this.productId,
    required this.quantity,
    this.color,
    this.size,
    this.notes,
  });
}

/// DAO managing delivery notes and service invoicing for manufacturing-for-others orders.
@DriftAccessor(tables: [
  ManufacturingDeliveries,
  ManufacturingDeliveryItems,
  ManufacturingOrders,
  ManufacturingScraps,
  CustomerStockBalances,
  CustomerStockMovements,
  Invoices,
  InvoiceItems,
  LedgerTransactions,
  Customers,
  Products,
  BillOfMaterials,
  BomItems,
])
class ManufacturingDeliveryDao extends DatabaseAccessor<AppDatabase>
    with _$ManufacturingDeliveryDaoMixin {
  ManufacturingDeliveryDao(super.db);

  // ── Queries ──

  Future<ManufacturingDelivery?> getDeliveryById(int id) =>
      (select(manufacturingDeliveries)..where((d) => d.id.equals(id))).getSingleOrNull();

  Future<List<ManufacturingDelivery>> getDeliveriesForOrder(int orderId) =>
      (select(manufacturingDeliveries)
            ..where((d) => d.manufacturingOrderId.equals(orderId))
            ..orderBy([(d) => OrderingTerm.desc(d.deliveryDate)]))
          .get();

  Future<List<ManufacturingDeliveryItem>> getDeliveryItems(int deliveryId) =>
      (select(manufacturingDeliveryItems)..where((i) => i.deliveryId.equals(deliveryId))).get();

  /// Total delivered quantity of finished goods for a manufacturing order.
  Future<double> getTotalDeliveredQuantity(int orderId) async {
    final deliveries = await (select(manufacturingDeliveries)
          ..where((d) => d.manufacturingOrderId.equals(orderId) & d.status.equals('delivered')))
        .get();
    if (deliveries.isEmpty) return 0.0;

    final deliveryIds = deliveries.map((d) => d.id).toList();
    final items = await (select(manufacturingDeliveryItems)
          ..where((i) => i.deliveryId.isIn(deliveryIds)))
        .get();

    double total = 0.0;
    for (final item in items) {
      total += item.quantity;
    }
    return total;
  }

  // ── Sequence Number ──

  /// Generates sequence number DN-YYYY-NNNN.
  Future<String> getNextDeliveryNumber() async {
    final year = DateTime.now().year;
    final prefix = 'DN-$year-';

    final latest = await (select(manufacturingDeliveries)
          ..where((d) => d.deliveryNumber.like('$prefix%'))
          ..orderBy([(d) => OrderingTerm.desc(d.deliveryNumber)])
          ..limit(1))
        .getSingleOrNull();

    int nextNum = 1;
    if (latest != null) {
      final suffix = latest.deliveryNumber.substring(prefix.length);
      final parsed = int.tryParse(suffix);
      if (parsed != null) {
        nextNum = parsed + 1;
      }
    }
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ── Atomic Delivery Creation ──

  /// Creates a delivery note atomically for a completed manufacturing-for-others order.
  ///
  /// Enforces:
  /// 1. Order must exist, be completed, and orderType must be 'for_others' or 'mixed'.
  /// 2. Items must not be empty, quantities must be positive.
  /// 3. Quantity validation: total delivered cannot exceed producedQuantity.
  ///    If over-quantity, throws [StateError] before ANY database write (zero writes).
  /// 4. Updates order.deliveryStatus:
  ///    - 'partially_delivered' if total delivered < producedQuantity
  ///    - 'delivered' if total delivered >= producedQuantity
  /// 5. Writes customer_stock_movements with movementType = 'delivered'.
  Future<ManufacturingDelivery> createDelivery({
    required int orderId,
    required List<DeliveryItemInput> items,
    String? deliveredBy,
    String? receiverName,
    String? notes,
  }) {
    return transaction(() async {
      // 1. Validation
      if (items.isEmpty) {
        throw ArgumentError('Delivery must contain at least one item');
      }

      final order = await (select(manufacturingOrders)..where((o) => o.id.equals(orderId))).getSingleOrNull();
      if (order == null) {
        throw ArgumentError('Manufacturing order #$orderId not found');
      }

      if (order.status != ManufacturingOrderStatus.completed) {
        throw StateError(
          'Cannot create delivery for order in status "${order.status}". Order must be completed.',
        );
      }

      final type = order.orderType ?? 'internal';
      if (type != 'for_others' && type != 'mixed') {
        throw StateError(
          'Cannot create delivery note for order of type "$type". Only "for_others" and "mixed" orders support customer deliveries.',
        );
      }

      final customerId = order.customerId;
      if (customerId == null || customerId.isEmpty) {
        throw StateError('Manufacturing order #$orderId has no customer assigned');
      }

      // Check item quantities
      double deliveryTotalQuantity = 0.0;
      for (final item in items) {
        if (item.quantity <= 0) {
          throw ArgumentError.value(item.quantity, 'quantity', 'Delivery item quantity must be positive');
        }
        deliveryTotalQuantity += item.quantity;
      }

      final alreadyDelivered = await getTotalDeliveredQuantity(orderId);
      final producedQty = order.producedQuantity;
      final remainingDeliverable = producedQty - alreadyDelivered;

      if (deliveryTotalQuantity > remainingDeliverable + 1e-9) {
        throw StateError(
          'Cannot deliver $deliveryTotalQuantity units: order produced $producedQty, '
          'already delivered $alreadyDelivered, remaining available to deliver is $remainingDeliverable.',
        );
      }

      // 2. Writes (All validation passed)
      final deliveryNumber = await getNextDeliveryNumber();
      final now = DateTime.now();

      final deliveryId = await into(manufacturingDeliveries).insert(
        ManufacturingDeliveriesCompanion.insert(
          deliveryNumber: deliveryNumber,
          manufacturingOrderId: orderId,
          customerId: customerId,
          deliveryDate: Value(now),
          status: const Value('delivered'),
          deliveredBy: Value(deliveredBy),
          receiverName: Value(receiverName),
          notes: Value(notes),
          createdAt: Value(now),
        ),
      );

      for (final item in items) {
        await into(manufacturingDeliveryItems).insert(
          ManufacturingDeliveryItemsCompanion.insert(
            deliveryId: deliveryId,
            productId: item.productId,
            quantity: item.quantity,
            color: Value(item.color),
            size: Value(item.size),
            notes: Value(item.notes),
          ),
        );

        // Record customer stock movement: delivered
        await into(customerStockMovements).insert(
          CustomerStockMovementsCompanion.insert(
            customerId: customerId,
            productId: item.productId,
            movementType: 'delivered',
            quantity: item.quantity,
            color: Value(item.color),
            size: Value(item.size),
            referenceType: 'delivery_note',
            referenceId: deliveryNumber,
            notes: Value('تسليم تشغيل للغير بأمر $deliveryNumber'),
            createdAt: Value(now),
          ),
        );
      }

      // Update order deliveryStatus
      final newTotalDelivered = alreadyDelivered + deliveryTotalQuantity;
      final newStatus = (newTotalDelivered >= producedQty - 1e-9)
          ? 'delivered'
          : 'partially_delivered';

      await (update(manufacturingOrders)..where((o) => o.id.equals(orderId))).write(
        ManufacturingOrdersCompanion(
          deliveryStatus: Value(newStatus),
          updatedAt: Value(now),
        ),
      );

      return (select(manufacturingDeliveries)..where((d) => d.id.equals(deliveryId))).getSingle();
    });
  }

  // ── Service Invoicing ──

  /// Generates a service invoice for a completed manufacturing-for-others order.
  ///
  /// Enforces:
  /// 1. Order must exist, be completed, and orderType must be 'for_others' or 'mixed'.
  /// 2. Double-invoicing prevention: if order.invoiceId is already set, throws [StateError].
  /// 3. Pricing Modes:
  ///    - 'inclusive': single service line (or summary) calculated as:
  ///      deliveredQuantity * serviceUnitPrice.
  ///    - 'separate': labour service lines + factory material lines (if mixed order).
  /// 4. Compensation Handling:
  ///    - If order scrap policy is 'factory_pays_piece_value' with fault 'factory',
  ///      the compensation amount is deducted from the invoice total.
  ///    - If scrap policy is 'factory_bears_labour_only', labour is billed only on
  ///      delivered (non-scrapped) units.
  /// 5. Posts to [Invoices], [InvoiceItems], and [LedgerTransactions] so that it
  ///    seamlessly appears in the customer ledger, statement, and balance.
  /// 6. Links [manufacturing_orders.invoice_id] to the generated invoice.
  Future<Invoice> generateServiceInvoice(int orderId) {
    return transaction(() async {
      final order = await (select(manufacturingOrders)..where((o) => o.id.equals(orderId))).getSingleOrNull();
      if (order == null) {
        throw ArgumentError('Manufacturing order #$orderId not found');
      }

      if (order.status != ManufacturingOrderStatus.completed) {
        throw StateError(
          'Cannot generate invoice for order in status "${order.status}". Order must be completed.',
        );
      }

      final type = order.orderType ?? 'internal';
      if (type != 'for_others' && type != 'mixed') {
        throw StateError(
          'Cannot generate service invoice for order of type "$type". Only "for_others" and "mixed" orders support service invoicing.',
        );
      }

      if (order.invoiceId != null) {
        throw StateError(
          'Order #${order.orderNumber} is already invoiced (Invoice ID: ${order.invoiceId}). Double invoicing is prevented.',
        );
      }

      final customerId = order.customerId;
      if (customerId == null || customerId.isEmpty) {
        throw StateError('Manufacturing order #$orderId has no customer assigned');
      }

      final customer = await (select(customers)..where((c) => c.id.equals(customerId))).getSingleOrNull();
      final customerName = customer?.name ?? 'عميل تشغيل للغير';

      final deliveredQty = await getTotalDeliveredQuantity(orderId);
      final serviceUnitPrice = order.serviceUnitPrice ?? 0.0;
      final pricingMode = order.pricingMode ?? 'inclusive';

      // ── Calculate Service / Material Amounts ──
      double grossServiceTotal = 0.0;
      final invoiceLines = <InvoiceItemsCompanion>[];

      if (pricingMode == 'inclusive') {
        // Inclusive: delivered quantity * service unit price
        grossServiceTotal = double.parse((deliveredQty * serviceUnitPrice).toStringAsFixed(2));
      } else {
        // Separate: service fee on delivered goods + factory material costs for mixed orders
        grossServiceTotal = double.parse((deliveredQty * serviceUnitPrice).toStringAsFixed(2));

        if (type == 'mixed') {
          // Read factory BOM items and calculate factory materials consumed
          // In mixed orders, factory materials are lines not in customer stock balances
          final bomItemsList = await (select(bomItems)..where((b) => b.bomId.equals(order.bomId))).get();
          for (final bi in bomItemsList) {
            // Check if customer had custody balance for this material; if not, it's factory supplied
            final custBal = await (select(customerStockBalances)
                  ..where((b) => b.customerId.equals(customerId) & b.productId.equals(bi.rawMaterialProductId)))
                .getSingleOrNull();
            if (custBal == null) {
              final factoryProd = await (select(products)..where((p) => p.id.equals(bi.rawMaterialProductId))).getSingleOrNull();
              final unitPrice = factoryProd?.price ?? 0.0;
              final consumedQty = bi.quantityRequired * order.producedQuantity;
              final lineTotal = double.parse((consumedQty * unitPrice).toStringAsFixed(2));
              grossServiceTotal += lineTotal;
            }
          }
        }
      }

      // ── Calculate Scrap Compensation Deductions ──
      final scraps = await (select(manufacturingScraps)..where((s) => s.manufacturingOrderId.equals(orderId))).get();
      double totalCompensation = 0.0;
      for (final s in scraps) {
        if (s.faultParty == 'factory' && s.compensationAction == 'deducted_from_invoice') {
          totalCompensation += (s.compensationAmount ?? 0.0);
        }
      }
      totalCompensation = double.parse(totalCompensation.toStringAsFixed(2));

      // Net invoice total: cannot be less than 0
      final netInvoiceTotal = (grossServiceTotal > totalCompensation)
          ? double.parse((grossServiceTotal - totalCompensation).toStringAsFixed(2))
          : 0.0;

      final now = DateTime.now();
      final invoiceNumber = 'INV-MFG-${order.orderNumber}';

      // ── Insert Invoice ──
      final invoiceId = await into(invoices).insert(
        InvoicesCompanion.insert(
          invoiceNumber: Value(invoiceNumber),
          customerId: Value(customerId),
          customerName: Value(customerName),
          paymentMethod: const Value('credit'),
          totalAmount: Value(netInvoiceTotal),
          paidAmount: const Value(0.0),
          cashAmount: const Value(0.0),
          cardAmount: const Value(0.0),
          creditAmount: Value(netInvoiceTotal),
          status: const Value('pending'),
          date: Value(now),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // ── Insert Invoice Items ──
      // 1. Service line
      await into(invoiceItems).insert(
        InvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: order.finishedProductId,
          quantity: Value(deliveredQty.round() > 0 ? deliveredQty.round() : 1),
          price: (deliveredQty > 0)
              ? double.parse((grossServiceTotal / (deliveredQty.round() > 0 ? deliveredQty.round() : 1)).toStringAsFixed(2))
              : grossServiceTotal,
          discount: Value(totalCompensation),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // ── Insert Customer Ledger Transaction ──
      // Debit customer balance for the net invoice total
      if (netInvoiceTotal > 0) {
        final ledgerTxId = 'LEDGER_MFG_${invoiceId}_${now.millisecondsSinceEpoch}';
        await into(ledgerTransactions).insert(
          LedgerTransactionsCompanion.insert(
            id: ledgerTxId,
            entityType: 'Customer',
            refId: customerId,
            date: now,
            description: 'فاتورة تشغيل أمر تصنيع ${order.orderNumber}',
            debit: Value(netInvoiceTotal),
            credit: const Value(0.0),
            origin: 'sale',
            paymentMethod: const Value('credit'),
            receiptNumber: Value(invoiceNumber),
            createdAt: Value(now),
          ),
        );
      }

      // ── Link Manufacturing Order to Invoice ──
      await (update(manufacturingOrders)..where((o) => o.id.equals(orderId))).write(
        ManufacturingOrdersCompanion(
          invoiceId: Value(invoiceId),
          updatedAt: Value(now),
        ),
      );

      return (select(invoices)..where((i) => i.id.equals(invoiceId))).getSingle();
    });
  }
}
