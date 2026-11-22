import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/consumption_record.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_material_receipts_table.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

part 'customer_material_receipt_dao.g.dart';

/// DTO for a receipt item line input to [CustomerMaterialReceiptDao.receiveCustomerMaterial].
class ReceiptItemInput {
  final int productId;
  final double quantityReceived;
  final double quantityDefectiveAtReceipt;
  final String? color;
  final String? size;
  final String? unit;
  final String? rejectionReason;
  final String? notes;

  const ReceiptItemInput({
    required this.productId,
    required this.quantityReceived,
    this.quantityDefectiveAtReceipt = 0.0,
    this.color,
    this.size,
    this.unit,
    this.rejectionReason,
    this.notes,
  });

  double get quantityAccepted => quantityReceived - quantityDefectiveAtReceipt;
}

@DriftAccessor(tables: [
  CustomerMaterialReceipts,
  CustomerMaterialReceiptItems,
  CustomerStockBalances,
  CustomerStockMovements,
  Customers,
  Products,
  ManufacturingOrders,
  ConsumptionRecords,
])
class CustomerMaterialReceiptDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerMaterialReceiptDaoMixin {
  CustomerMaterialReceiptDao(super.db);

  // ── Queries & Watchers ──

  Future<List<CustomerMaterialReceipt>> getAllReceipts() =>
      (select(customerMaterialReceipts)..orderBy([(r) => OrderingTerm.desc(r.receivedDate)])).get();

  Stream<List<CustomerMaterialReceipt>> watchAllReceipts() =>
      (select(customerMaterialReceipts)..orderBy([(r) => OrderingTerm.desc(r.receivedDate)])).watch();

  Future<CustomerMaterialReceipt?> getReceiptById(int id) =>
      (select(customerMaterialReceipts)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<List<CustomerMaterialReceiptItem>> getItemsForReceipt(int receiptId) =>
      (select(customerMaterialReceiptItems)..where((i) => i.receiptId.equals(receiptId))).get();

  Stream<List<CustomerMaterialReceiptItem>> watchItemsForReceipt(int receiptId) =>
      (select(customerMaterialReceiptItems)..where((i) => i.receiptId.equals(receiptId))).watch();

  // ── Customer Custody Balance Read Helpers ──

  /// Current balance row for a specific customer, product and optional color/size.
  Future<CustomerStockBalance?> getCustomerBalance({
    required String customerId,
    required int productId,
    String? color,
    String? size,
  }) {
    final query = select(customerStockBalances)
      ..where((b) =>
          b.customerId.equals(customerId) &
          b.productId.equals(productId) &
          (color != null ? b.color.equals(color) : b.color.isNull()) &
          (size != null ? b.size.equals(size) : b.size.isNull()));
    return query.getSingleOrNull();
  }

  /// Available on-hand quantity for a customer product (ignoring color/size or specific).
  Future<double> getCustomerAvailableQuantity({
    required String customerId,
    required int productId,
    String? color,
    String? size,
  }) async {
    final row = await getCustomerBalance(
      customerId: customerId,
      productId: productId,
      color: color,
      size: size,
    );
    return row?.quantityOnHand ?? 0.0;
  }

  /// Total rolling custody balances for a customer across all products.
  Future<List<CustomerStockBalance>> getAllBalancesForCustomer(String customerId) =>
      (select(customerStockBalances)..where((b) => b.customerId.equals(customerId))).get();

  Stream<List<CustomerStockBalance>> watchAllBalancesForCustomer(String customerId) =>
      (select(customerStockBalances)..where((b) => b.customerId.equals(customerId))).watch();

  // ── Sequence Number Generator ──

  /// Generates the next CMR-YYYY-NNNN sequence number.
  Future<String> getNextReceiptNumber() async {
    final year = DateTime.now().year;
    final prefix = 'CMR-$year-';

    final latest = await (select(customerMaterialReceipts)
          ..where((r) => r.receiptNumber.like('$prefix%'))
          ..orderBy([(r) => OrderingTerm.desc(r.receiptNumber)])
          ..limit(1))
        .getSingleOrNull();

    int nextNum = 1;
    if (latest != null) {
      final suffix = latest.receiptNumber.substring(prefix.length);
      final parsed = int.tryParse(suffix);
      if (parsed != null) {
        nextNum = parsed + 1;
      }
    }
    return '$prefix${nextNum.toString().padLeft(4, '0')}';
  }

  // ── Atomic Receipt Mutation ──

  /// Receives customer material into custody atomically.
  ///
  /// Enforces:
  /// 1. Customer must exist in the customers table.
  /// 2. Items must not be empty.
  /// 3. For every item, quantityReceived > 0, quantityDefectiveAtReceipt >= 0,
  ///    and quantityReceived >= quantityDefectiveAtReceipt (before ANY write).
  /// 4. Generates CMR-YYYY-NNNN sequence number.
  /// 5. Writes header and line items.
  /// 6. If defective > 0: inserts customer_stock_movements type 'return_defect'.
  ///    (Defective quantity is NEVER added to custody balance).
  /// 7. For accepted quantity > 0: upserts customer_stock_balances (quantityOnHand += accepted)
  ///    and writes customer_stock_movements type 'receipt'.
  /// 8. Products.quantity and inventory_movements are NEVER touched.
  Future<CustomerMaterialReceipt> receiveCustomerMaterial({
    required String customerId,
    required List<ReceiptItemInput> items,
    int? manufacturingOrderId,
    DateTime? receivedDate,
    String? receivedBy,
    String? notes,
  }) {
    return transaction(() async {
      // 1. Validation before ANY write
      if (items.isEmpty) {
        throw ArgumentError('Receipt must contain at least one item');
      }

      final customer = await (select(db.customers)..where((c) => c.id.equals(customerId))).getSingleOrNull();
      if (customer == null) {
        throw ArgumentError('Customer #$customerId not found');
      }

      for (final item in items) {
        if (item.quantityReceived <= 0) {
          throw ArgumentError('quantityReceived must be > 0 for product #${item.productId}');
        }
        if (item.quantityDefectiveAtReceipt < 0) {
          throw ArgumentError('quantityDefectiveAtReceipt cannot be negative');
        }
        if (item.quantityDefectiveAtReceipt > item.quantityReceived) {
          throw ArgumentError(
            'Defective quantity (${item.quantityDefectiveAtReceipt}) cannot exceed received quantity (${item.quantityReceived}) for product #${item.productId}',
          );
        }
        final product = await (select(db.products)..where((p) => p.id.equals(item.productId))).getSingleOrNull();
        if (product == null) {
          throw ArgumentError('Product #${item.productId} not found');
        }
      }

      // 2. Generate sequence number & insert header
      final receiptNumber = await getNextReceiptNumber();
      final now = receivedDate ?? DateTime.now();

      final receiptId = await into(customerMaterialReceipts).insert(
        CustomerMaterialReceiptsCompanion.insert(
          receiptNumber: receiptNumber,
          customerId: customerId,
          manufacturingOrderId: Value(manufacturingOrderId),
          receivedDate: Value(now),
          status: const Value('received'),
          notes: Value(notes),
          receivedBy: Value(receivedBy),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // 3. Insert items and update custody ledger / balance
      for (final item in items) {
        await into(customerMaterialReceiptItems).insert(
          CustomerMaterialReceiptItemsCompanion.insert(
            receiptId: receiptId,
            productId: item.productId,
            quantityReceived: item.quantityReceived,
            quantityDefectiveAtReceipt: Value(item.quantityDefectiveAtReceipt),
            quantityAccepted: item.quantityAccepted,
            color: Value(item.color),
            size: Value(item.size),
            unit: Value(item.unit),
            rejectionReason: Value(item.rejectionReason),
            notes: Value(item.notes),
          ),
        );

        // Record immediate return for defective pieces inspected at receipt
        if (item.quantityDefectiveAtReceipt > 0) {
          await into(customerStockMovements).insert(
            CustomerStockMovementsCompanion.insert(
              customerId: customerId,
              productId: item.productId,
              movementType: 'return_defect',
              quantity: -item.quantityDefectiveAtReceipt,
              referenceType: 'customer_material_receipt',
              referenceId: receiptNumber,
              color: Value(item.color),
              size: Value(item.size),
              notes: Value(item.rejectionReason ?? 'تالف عند الاستلام — تم الرد للعميل'),
              performedBy: Value(receivedBy),
              createdAt: Value(now),
            ),
          );
        }

        // Accepted quantity enters custody balance
        if (item.quantityAccepted > 0) {
          final existingBalance = await getCustomerBalance(
            customerId: customerId,
            productId: item.productId,
            color: item.color,
            size: item.size,
          );

          if (existingBalance == null) {
            await into(customerStockBalances).insert(
              CustomerStockBalancesCompanion.insert(
                customerId: customerId,
                productId: item.productId,
                color: Value(item.color),
                size: Value(item.size),
                quantityOnHand: Value(item.quantityAccepted),
                quantityAllocated: const Value(0.0),
                updatedAt: Value(now),
              ),
            );
          } else {
            final updatedQty = existingBalance.quantityOnHand + item.quantityAccepted;
            await (update(customerStockBalances)..where((b) => b.id.equals(existingBalance.id))).write(
              CustomerStockBalancesCompanion(
                quantityOnHand: Value(updatedQty),
                updatedAt: Value(now),
              ),
            );
          }

          // Record receipt movement into custody ledger
          await into(customerStockMovements).insert(
            CustomerStockMovementsCompanion.insert(
              customerId: customerId,
              productId: item.productId,
              movementType: 'receipt',
              quantity: item.quantityAccepted,
              referenceType: 'customer_material_receipt',
              referenceId: receiptNumber,
              color: Value(item.color),
              size: Value(item.size),
              notes: Value(item.notes ?? 'استلام بضاعة عميل للتشغيل'),
              performedBy: Value(receivedBy),
              createdAt: Value(now),
            ),
          );
        }
      }

      return (await getReceiptById(receiptId))!;
    });
  }

  /// FEAT-039 D-02: Returns unused customer-owned materials from an order back
  /// into the customer's custody balance in the warehouse.
  ///
  /// Records a positive `return_excess` movement on `manufacturing_order`,
  /// increments `CustomerStockBalances.quantityOnHand`, and reconciles
  /// `ConsumptionRecords.actualQty` downward (D-03) if `consumed + returnedExcess`
  /// would otherwise exceed `totalIssued`.
  Future<CustomerStockMovement> returnExcessFromOrder({
    required int orderId,
    required int productId,
    required double quantity,
    String? color,
    String? size,
    String? notes,
    String? performedBy,
  }) {
    return transaction(() async {
      if (quantity <= 0) {
        throw ArgumentError.value(quantity, 'quantity', 'Quantity must be > 0');
      }

      final order = await (select(db.manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
      if (order == null) {
        throw ArgumentError('ManufacturingOrder #$orderId not found');
      }
      final customerId = order.customerId;
      if (customerId == null || customerId.trim().isEmpty) {
        throw ArgumentError('Order #$orderId has no customerId associated');
      }
      if ((order.orderType ?? 'internal') == 'internal') {
        throw StateError('Internal orders do not hold customer custody materials');
      }

      final product = await (select(db.products)
            ..where((p) => p.id.equals(productId)))
          .getSingleOrNull();
      if (product == null) {
        throw ArgumentError('Product #$productId not found');
      }

      final orderRefs = <String>{order.orderNumber, order.id.toString()}.toList();
      final orderMoves = await (select(customerStockMovements)
            ..where(
              (m) =>
                  m.referenceType.equals('manufacturing_order') &
                  m.referenceId.isIn(orderRefs) &
                  m.productId.equals(productId),
            ))
          .get();

      double totalIssued = 0.0;
      double totalAlreadyReturned = 0.0;
      for (final m in orderMoves) {
        if (m.movementType == 'issued_to_order' ||
            m.movementType == 'manufacturing_consumption') {
          totalIssued += m.quantity.abs();
        } else if (m.movementType == 'return_excess') {
          totalAlreadyReturned += m.quantity.abs();
        }
      }

      if (totalIssued <= 0 ||
          totalAlreadyReturned + quantity > totalIssued + 0.001) {
        throw StateError(
          'لا يمكن إرجاع $quantity من ${product.name}: المصروف للأمر '
          '($totalIssued) والمرتجع سابقاً ($totalAlreadyReturned) لا يسمحان بهذا القدر',
        );
      }

      final now = DateTime.now();
      final effectiveColor =
          color ?? (order.inputProductId == productId ? order.inputColor : null);
      final effectiveSize =
          size ?? (order.inputProductId == productId ? order.inputSize : null);

      final existingBalance = await getCustomerBalance(
        customerId: customerId,
        productId: productId,
        color: effectiveColor,
        size: effectiveSize,
      );
      if (existingBalance == null) {
        await into(customerStockBalances).insert(
          CustomerStockBalancesCompanion.insert(
            customerId: customerId,
            productId: productId,
            color: Value(effectiveColor),
            size: Value(effectiveSize),
            quantityOnHand: Value(quantity),
            quantityAllocated: const Value(0.0),
            updatedAt: Value(now),
          ),
        );
      } else {
        await (update(customerStockBalances)
              ..where((b) => b.id.equals(existingBalance.id)))
            .write(
          CustomerStockBalancesCompanion(
            quantityOnHand: Value(existingBalance.quantityOnHand + quantity),
            updatedAt: Value(now),
          ),
        );
      }

      final moveId = await into(customerStockMovements).insert(
        CustomerStockMovementsCompanion.insert(
          customerId: customerId,
          productId: productId,
          color: Value(effectiveColor),
          size: Value(effectiveSize),
          movementType: 'return_excess',
          quantity: quantity,
          referenceType: 'manufacturing_order',
          referenceId: order.orderNumber,
          notes: Value(
            notes ?? 'إرجاع فائض خامات من أمر ${order.orderNumber} لعهدة العميل',
          ),
          performedBy: Value(performedBy),
          createdAt: Value(now),
        ),
      );

      // D-03 automatic reconciliation: trim analytical actualQty (newest first)
      // when returning excess reduces net consumption below previously recorded actuals.
      final consumptionRows = await (select(db.consumptionRecords)
            ..where(
              (c) =>
                  c.manufacturingOrderId.equals(orderId) &
                  c.materialProductId.equals(productId) &
                  c.ownershipType.equals('customer_owned'),
            )
            ..orderBy([(c) => OrderingTerm.desc(c.id)]))
          .get();
      final totalConsumed = consumptionRows.fold<double>(
        0.0,
        (s, r) => s + (r.actualQty ?? 0.0),
      );
      var overlap =
          (totalConsumed + totalAlreadyReturned + quantity) - totalIssued;
      if (overlap > 0.001) {
        for (final row in consumptionRows) {
          if (overlap <= 0.0001) break;
          final curr = row.actualQty ?? 0.0;
          if (curr <= 0) continue;
          final deduct = curr >= overlap ? overlap : curr;
          final nextQty = double.parse((curr - deduct).toStringAsFixed(6));
          await (update(db.consumptionRecords)
                ..where((t) => t.id.equals(row.id)))
              .write(ConsumptionRecordsCompanion(actualQty: Value(nextQty)));
          overlap -= deduct;
        }
      }

      return (select(customerStockMovements)..where((m) => m.id.equals(moveId)))
          .getSingle();
    });
  }

  /// FEAT-039 D-02: Physically hands back excess customer-owned raw material
  /// from custody balance (`quantityOnHand - quantityAllocated`) to the customer.
  ///
  /// Records a negative `return_custody` movement under
  /// `referenceType == 'customer_custody_return'` so order-level custody
  /// reconciliation remains untouched.
  Future<CustomerStockMovement> returnCustodyToCustomer({
    required String customerId,
    required int productId,
    required double quantity,
    String? color,
    String? size,
    String? referenceId,
    String? notes,
    String? performedBy,
  }) {
    return transaction(() async {
      if (quantity <= 0) {
        throw ArgumentError.value(quantity, 'quantity', 'Quantity must be > 0');
      }

      final customer = await (select(db.customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingleOrNull();
      if (customer == null) {
        throw ArgumentError('Customer #$customerId not found');
      }

      final product = await (select(db.products)
            ..where((p) => p.id.equals(productId)))
          .getSingleOrNull();
      if (product == null) {
        throw ArgumentError('Product #$productId not found');
      }

      final balance = await getCustomerBalance(
        customerId: customerId,
        productId: productId,
        color: color,
        size: size,
      );
      final available = balance != null
          ? (balance.quantityOnHand - balance.quantityAllocated)
          : 0.0;
      if (balance == null || available < quantity - 0.001) {
        throw StateError(
          'الرصيد المتاح للرد للعميل من ${product.name} غير كافٍ: '
          'المطلوب $quantity، المتاح غير المحجوز $available',
        );
      }

      final now = DateTime.now();
      final rawNext = balance.quantityOnHand - quantity;
      final nextOnHand = rawNext < 0 && rawNext > -0.001 ? 0.0 : rawNext;

      await (update(customerStockBalances)
            ..where((b) => b.id.equals(balance.id)))
          .write(
        CustomerStockBalancesCompanion(
          quantityOnHand: Value(nextOnHand),
          updatedAt: Value(now),
        ),
      );

      final moveId = await into(customerStockMovements).insert(
        CustomerStockMovementsCompanion.insert(
          customerId: customerId,
          productId: productId,
          color: Value(color),
          size: Value(size),
          movementType: 'return_custody',
          quantity: -quantity,
          referenceType: 'customer_custody_return',
          referenceId: referenceId ?? 'RET-${now.millisecondsSinceEpoch}',
          notes: Value(notes ?? 'رد خامات فائضة من العهدة للعميل'),
          performedBy: Value(performedBy),
          createdAt: Value(now),
        ),
      );

      return (select(customerStockMovements)..where((m) => m.id.equals(moveId)))
          .getSingle();
    });
  }
}
