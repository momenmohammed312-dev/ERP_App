import 'dart:math';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../database/tables/empty_barnika_tracking_table.dart';
import '../database/tables/vegetable_shipments_table.dart';
import 'invoice_number_formatter.dart';
import 'shipment_allocation_service.dart';
import 'shipment_pricing_service.dart';

class InvoiceItemParams {
  final int productId;
  final int quantity;
  final double price;
  final int? ctn;
  final double discount;
  final double commission;
  final double? unitCostAtTime;
  final int? shipmentId;
  final int? variantId;

  InvoiceItemParams({
    required this.productId,
    required this.quantity,
    required this.price,
    this.ctn,
    this.discount = 0,
    this.commission = 0,
    this.unitCostAtTime,
    this.shipmentId,
    this.variantId,
  });
}

class CreateInvoiceResult {
  final Invoice invoice;
  final int invoiceId;

  CreateInvoiceResult({required this.invoice, required this.invoiceId});
}

class InvoiceService {
  final AppDatabase _db;

  InvoiceService(this._db);

  Future<CreateInvoiceResult> createInvoice({
    required String? customerId,
    required String customerName,
    String? customerContact,
    String? customerAddress,
    required String paymentMethod,
    required double totalAmount,
    required double paidAmount,
    double cashAmount = 0,
    double cardAmount = 0,
    double creditAmount = 0,
    required String status,
    String? invoiceNumber,
    required List<InvoiceItemParams> items,
    String? ledgerDescription,
    List<SplitPaymentEntry>? splitPayments,
    int? primaryShipmentId,
    DateTime? invoiceDate,
    int? emptyBarnikaOutCount,
    int? emptyBarnikaReturnedCount,
  }) async {
    // Bug 3: no timestamp numbering. A caller-supplied value is preserved
    // as legacy; otherwise the canonical display number derives from the
    // row id (assigned below) — never generated before the insert.
    final rand = Random.secure();
    final resolvedDate = invoiceDate ?? DateTime.now();

    return _db.transaction(() async {
      final invoiceId = await _db.invoiceDao.insertInvoice(
        InvoicesCompanion(
          invoiceNumber: Value(invoiceNumber),
          customerName: Value(customerName),
          customerContact: Value(customerContact ?? ''),
          customerAddress: Value(customerAddress ?? ''),
          customerId: Value(customerId),
          paymentMethod: Value(paymentMethod),
          totalAmount: Value(totalAmount),
          paidAmount: Value(paidAmount),
          cashAmount: Value(cashAmount),
          cardAmount: Value(cardAmount),
          creditAmount: Value(creditAmount),
          status: Value(status),
          date: Value(resolvedDate),
          shipmentId: Value(primaryShipmentId),
        ),
      );

      for (final item in items) {
        final product = await _db.productDao.getProductById(item.productId);

        if (product == null) {
          throw Exception('المنتج غير موجود (ID: ${item.productId})');
        }

        // خصم المخزون: من الصنف (لون/فئة) لو متحدد، وإلا المسار القديم من الأب.
        // كمية الأب بعد بيع صنف = مجموع الأصناف (تحافظ على التقارير وتنبيه النواقص).
        await _applySaleStock(product, item.quantity, item.variantId);

        VegetableShipment? shipment;
        if (item.shipmentId != null) {
          shipment = await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment == null) {
            throw Exception('الشحنة #${item.shipmentId} غير موجودة');
          }
          if (shipment.status != VegetableShipmentStatus.open) {
            throw Exception(
              'الشحنة #${shipment.shipmentNumber} مقفولة ولا يمكن البيع منها',
            );
          }

          final available = ShipmentAllocationService.effectiveRemaining(shipment);
          if (item.quantity > available) {
            throw Exception(
              'الشحنة #${item.shipmentId} لا تحتوي على كمية كافية '
              '(متبقي: $available, مطلوب: ${item.quantity})',
            );
          }

          await _db.vegetableShipmentDao.updateShipment(
            shipment.copyWith(
              barnikaSoldCount: shipment.barnikaSoldCount + item.quantity,
              barnikaRemainingCount: available - item.quantity,
            ),
          );
        }

        // Auto-calculate commission for commission-based shipments.
        var itemCommission = item.commission;
        if (shipment != null &&
            itemCommission == 0 &&
            shipment.pricingMode == ShipmentPricingMode.commission &&
            shipment.commissionPercentage != null) {
          final netLine = max(0.0, (item.price * item.quantity) - item.discount);
          itemCommission = ShipmentPricingService.calculateCommission(
            netLine,
            shipment.commissionPercentage!,
          );
        }

        await _db.invoiceDao.insertInvoiceItem(
          InvoiceItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(item.productId),
            quantity: Value(item.quantity),
            ctn: Value(item.ctn),
            price: Value(item.price),
            discount: Value(item.discount),
            commission: Value(itemCommission),
            unitCostAtTime: Value(item.unitCostAtTime),
            shipmentId: Value(item.shipmentId),
            variantId: Value(item.variantId),
          ),
        );
      }

      if (splitPayments != null) {
        for (final sp in splitPayments) {
          await _db.invoicePaymentsDao.insertPayment(
            InvoicePaymentsCompanion.insert(
              invoiceId: invoiceId,
              paymentMethod: sp.method,
              amount: sp.amount,
              paidAt: Value(resolvedDate),
            ),
          );
        }
      }

      final canonicalNumber = formatInvoiceNumber(invoiceId);
      if (invoiceNumber == null) {
        await (_db.update(_db.invoices)
              ..where((t) => t.id.equals(invoiceId)))
            .write(InvoicesCompanion(invoiceNumber: Value(canonicalNumber)));
      }
      // Resolved display number: legacy caller value, else canonical.
      // (Wording of descriptions is Bug 2's commit; numbering only here.)
      final actualInvoiceNumber = invoiceNumber ?? canonicalNumber;

      final desc = ledgerDescription ?? 'فاتورة $actualInvoiceNumber';

      if (customerId != null && customerId != 'cash' && customerId.isNotEmpty) {
        final ledgerIdSale = '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_sale';
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: ledgerIdSale,
            entityType: 'Customer',
            refId: customerId,
            date: resolvedDate,
            description: desc,
            debit: Value(totalAmount),
            credit: const Value(0.0),
            origin: 'sale',
            paymentMethod: Value(paymentMethod),
            receiptNumber: Value('INV$invoiceId'),
          ),
        );

        if (paidAmount > 0) {
          final ledgerIdPay = '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_pay';
          await _db.ledgerDao.insertTransaction(
            LedgerTransactionsCompanion.insert(
              id: ledgerIdPay,
              entityType: 'Customer',
              refId: customerId,
              date: resolvedDate,
              description: 'سداد $actualInvoiceNumber',
              debit: const Value(0.0),
              credit: Value(paidAmount),
              origin: 'payment',
              paymentMethod: Value(paymentMethod),
              receiptNumber: Value('INV$invoiceId'),
            ),
          );
        }
      }

      // Atomically record empty barnika custody & immediate returns linked to this sale.
      await _applyEmptyBarnikaForInvoice(
        invoiceId: invoiceId,
        customerId: customerId,
        resolvedDate: resolvedDate,
        items: items,
        emptyBarnikaOutCount: emptyBarnikaOutCount,
        emptyBarnikaReturnedCount: emptyBarnikaReturnedCount,
      );

      final invoice = await (_db.select(_db.invoices)
          ..where((t) => t.id.equals(invoiceId)))
          .getSingleOrNull();
      if (invoice == null) {
        throw Exception('فشل في حفظ الفاتورة رقم $actualInvoiceNumber');
      }

      return CreateInvoiceResult(invoice: invoice, invoiceId: invoiceId);
    });
  }

  Future<void> deleteInvoice(Insertable<Invoice> invoice) async {
    await _db.invoiceDao.deleteInvoice(invoice);
  }

  /// خصم مخزون سطر بيع: من الصنف (لون/فئة) لو متحدد، وإلا من الأب مباشرة.
  /// إذا خُصم من صنف، تُحدَّث كمية الأب تلقائيًا لتساوي مجموع أصنافه.
  Future<void> _applySaleStock(
    Product product,
    int quantity,
    int? variantId,
  ) async {
    if (variantId == null) {
      final variants = await _db.productVariantDao.getVariantsByProduct(
        product.id,
      );
      if (variants.isNotEmpty) {
        throw Exception(
          'المنتج «${product.name}» له أصناف (ألوان/فئات) — اختر الصنف أولًا',
        );
      }
      final newQty = product.quantity - quantity;
      await _db.productDao.updateProduct(
        product.copyWith(quantity: newQty < 0 ? 0 : newQty),
      );
      return;
    }
    final variant = await _db.productVariantDao.getVariantById(variantId);
    if (variant == null || variant.status == 'Deleted') {
      throw Exception('الصنف (اللون/الفئة) غير موجود');
    }
    if (variant.productId != product.id) {
      throw Exception('الصنف «${variant.name}» لا يتبع المنتج «${product.name}»');
    }
    if (variant.quantity < quantity) {
      throw Exception(
        'الكمية غير كافية للصنف «${variant.name}» من «${product.name}» '
        '(متاح: ${variant.quantity}, مطلوب: $quantity)',
      );
    }
    await _db.productVariantDao.updateVariantQuantity(
      variant.id,
      variant.quantity - quantity,
    );
    // كمية الأب = مجموع الأصناف (التقارير وتنبيه النواقص تفضل سليمة).
    final total = await _db.productVariantDao.getTotalQuantityByProduct(
      product.id,
    );
    await _db.productDao.updateProduct(
      product.copyWith(quantity: total),
    );
  }

  /// إرجاع مخزون سطر بيع ملغى: إلى الصنف لو متحدد، وإلا للأب.
  /// إذا أُرجع لصنف، تُحدَّث كمية الأب تلقائيًا لتساوي مجموع أصنافه.
  Future<void> _restoreSaleStock(
    int productId,
    int quantity,
    int? variantId,
  ) async {
    if (variantId != null) {
      final variant = await _db.productVariantDao.getVariantById(variantId);
      if (variant != null) {
        await _db.productVariantDao.updateVariantQuantity(
          variant.id,
          variant.quantity + quantity,
        );
        final total = await _db.productVariantDao.getTotalQuantityByProduct(
          productId,
        );
        final product = await _db.productDao.getProductById(productId);
        if (product != null) {
          await _db.productDao.updateProduct(
            product.copyWith(quantity: total),
          );
        }
        return;
      }
      // الصنف اتحذف نهائيًا بعد البيع — نرجع الكمية للأب مباشرة عشان ماتضيعش.
    }
    final product = await _db.productDao.getProductById(productId);
    if (product != null) {
      await _db.productDao.updateProduct(
        product.copyWith(quantity: product.quantity + quantity),
      );
    }
  }

  /// Atomically edits an existing invoice while preserving its id and number.
  ///
  /// Strategy (mirrors [createInvoice] to avoid fragile delta math):
  /// 1. Reverse the original impact: restore stock, reverse shipment counts,
  ///    delete the original ledger rows + line items for this invoice.
  /// 2. Re-apply the edited items: decrement stock, insert items, update
  ///    shipment counts/commission, update the invoice totals row, and write
  ///    fresh ledger rows (sale + payment + supplier commission).
  ///
  /// Everything runs inside a single Drift transaction so it either fully
  /// succeeds or fully rolls back — no partial/corrupted state.
  Future<Invoice> editInvoice({
    required int invoiceId,
    required String? customerId,
    required String customerName,
    String? customerContact,
    String? customerAddress,
    required String paymentMethod,
    required double totalAmount,
    required double paidAmount,
    double cashAmount = 0,
    double cardAmount = 0,
    double creditAmount = 0,
    required String status,
    required List<InvoiceItemParams> items,
    int? primaryShipmentId,
    DateTime? invoiceDate,
    int? emptyBarnikaOutCount,
    int? emptyBarnikaReturnedCount,
  }) async {
    final original = await getInvoiceById(invoiceId);
    if (original == null) throw Exception('الفاتورة غير موجودة');
    if (original.status == 'voided') {
      throw Exception('لا يمكن تعديل فاتورة ملغاة');
    }
    final resolvedDate = invoiceDate ?? original.date;

    // Guard: do not edit an invoice that already has returns — that would
    // double-count stock/ledger. User must reverse the return first.
    final returns = await _db.salesReturnsDao.getReturnsForInvoice(invoiceId);
    if (returns.isNotEmpty) {
      throw Exception('لا يمكن تعديل فاتورة عليها مرتجعات مسجلة');
    }

    final actualInvoiceNumber = original.invoiceNumber ?? 'INV$invoiceId';
    final rand = Random.secure();

    return _db.transaction(() async {
      final originalItems = await _db.invoiceDao.getItemsByInvoiceId(invoiceId);
      final existingBarnikas =
          await _db.emptyBarnikaTrackingDao.getByInvoiceId(invoiceId);
      final prevBarnikaReturned = existingBarnikas.fold<int>(
        0,
        (s, e) => s + e.quantityReturned,
      );
      final hadBarnikaRow = existingBarnikas.isNotEmpty;

      // 1a. Reverse original stock + shipment counts.
      for (final item in originalItems) {
        await _restoreSaleStock(item.productId, item.quantity, item.variantId);
        if (item.shipmentId != null) {
          final shipment =
              await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment != null) {
            if (shipment.status == VegetableShipmentStatus.closed) {
              throw Exception(
                'الشحنة #${shipment.shipmentNumber} مقفولة ولا يمكن تعديل فواتيرها',
              );
            }
            final restoredSold =
                (shipment.barnikaSoldCount - item.quantity).clamp(0, 1 << 30);
            final restoredRemaining = (shipment.totalBarnikaCount -
                    restoredSold -
                    shipment.toppingCount)
                .clamp(0, 1 << 30);
            await _db.vegetableShipmentDao.updateShipment(
              shipment.copyWith(
                barnikaSoldCount: restoredSold,
                barnikaRemainingCount: restoredRemaining,
              ),
            );
          }
        }
      }

      // 1b. Reverse original ledger rows, line items, and linked empty barnikas.
      await _db.emptyBarnikaTrackingDao.deleteByInvoiceId(invoiceId);
      await _db.ledgerDao
          .deleteTransactionsByReceiptNumber('INV$invoiceId');
      await _db.invoiceDao.deleteInvoiceItemsByInvoice(invoiceId);

      // 2a. Re-apply edited items.
      for (final item in items) {
        final product = await _db.productDao.getProductById(item.productId);
        if (product == null) {
          throw Exception('المنتج غير موجود (ID: ${item.productId})');
        }

        await _applySaleStock(product, item.quantity, item.variantId);

        VegetableShipment? shipment;
        if (item.shipmentId != null) {
          shipment = await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment == null) {
            throw Exception('الشحنة #${item.shipmentId} غير موجودة');
          }
          if (shipment.status != VegetableShipmentStatus.open) {
            throw Exception(
              'الشحنة #${shipment.shipmentNumber} مقفولة ولا يمكن البيع منها',
            );
          }

          final available = ShipmentAllocationService.effectiveRemaining(shipment);
          if (item.quantity > available) {
            throw Exception(
              'الشحنة #${item.shipmentId} لا تحتوي على كمية كافية '
              '(متبقي: $available, مطلوب: ${item.quantity})',
            );
          }
          await _db.vegetableShipmentDao.updateShipment(
            shipment.copyWith(
              barnikaSoldCount: shipment.barnikaSoldCount + item.quantity,
              barnikaRemainingCount: available - item.quantity,
            ),
          );
        }

        var itemCommission = item.commission;
        if (shipment != null &&
            itemCommission == 0 &&
            shipment.pricingMode == ShipmentPricingMode.commission &&
            shipment.commissionPercentage != null) {
          final netLine = max(0.0, (item.price * item.quantity) - item.discount);
          itemCommission = ShipmentPricingService.calculateCommission(
            netLine,
            shipment.commissionPercentage!,
          );
        }

        await _db.invoiceDao.insertInvoiceItem(
          InvoiceItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(item.productId),
            quantity: Value(item.quantity),
            ctn: Value(item.ctn),
            price: Value(item.price),
            discount: Value(item.discount),
            commission: Value(itemCommission),
            unitCostAtTime: Value(item.unitCostAtTime),
            shipmentId: Value(item.shipmentId),
            variantId: Value(item.variantId),
          ),
        );
      }

      // 2b. Update invoice header totals.
      await _db.invoiceDao.updateInvoice(
        InvoicesCompanion(
          id: Value(invoiceId),
          invoiceNumber: Value(actualInvoiceNumber),
          customerId: Value(customerId),
          customerName: Value(customerName),
          customerContact: Value(customerContact ?? ''),
          customerAddress: Value(customerAddress ?? ''),
          paymentMethod: Value(paymentMethod),
          totalAmount: Value(totalAmount),
          paidAmount: Value(paidAmount),
          cashAmount: Value(cashAmount),
          cardAmount: Value(cardAmount),
          creditAmount: Value(creditAmount),
          status: Value(status),
          date: Value(resolvedDate),
          shipmentId: Value(primaryShipmentId),
        ),
      );

      // 2b-2. مزامنة تاريخ المدفوعات وحركات المخزون مع تاريخ الفاتورة المعدل
      await (_db.update(_db.invoicePayments)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .write(InvoicePaymentsCompanion(paidAt: Value(resolvedDate)));

      await (_db.update(_db.inventoryMovements)
            ..where((t) {
              var expr = t.reference.equals(invoiceId.toString()) |
                  t.reference.equals('INV$invoiceId');
              if (actualInvoiceNumber.isNotEmpty) {
                expr = expr | t.reference.equals(actualInvoiceNumber);
              }
              return expr;
            }))
          .write(
            InventoryMovementsCompanion(
              movementDate: Value(resolvedDate),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // 2c. Fresh ledger rows for a credit customer.
      final desc = 'بيع #$actualInvoiceNumber';
      if (customerId != null &&
          customerId != 'cash' &&
          customerId.isNotEmpty) {
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id:
                '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_sale',
            entityType: 'Customer',
            refId: customerId,
            date: resolvedDate,
            description: desc,
            debit: Value(totalAmount),
            credit: const Value(0.0),
            origin: 'sale',
            paymentMethod: Value(paymentMethod),
            receiptNumber: Value('INV$invoiceId'),
          ),
        );

        if (paidAmount > 0) {
          await _db.ledgerDao.insertTransaction(
            LedgerTransactionsCompanion.insert(
              id:
                  '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_pay',
              entityType: 'Customer',
              refId: customerId,
              date: resolvedDate,
              description: 'سداد $actualInvoiceNumber',
              debit: const Value(0.0),
              credit: Value(paidAmount),
              origin: 'payment',
              paymentMethod: Value(paymentMethod),
              receiptNumber: Value('INV$invoiceId'),
            ),
          );
        }
      }

      // 2d. Re-apply invoice-linked empty barnika custody.
      if (emptyBarnikaOutCount != null ||
          emptyBarnikaReturnedCount != null ||
          hadBarnikaRow ||
          items.any((i) => i.shipmentId != null)) {
        final shipmentQty = items
            .where((i) => i.shipmentId != null)
            .fold<int>(0, (s, i) => s + i.quantity);
        final nextOut = emptyBarnikaOutCount ?? shipmentQty;
        final nextReturned = emptyBarnikaReturnedCount ??
            (hadBarnikaRow ? min(prevBarnikaReturned, nextOut) : 0);
        await _applyEmptyBarnikaForInvoice(
          invoiceId: invoiceId,
          customerId: customerId,
          resolvedDate: resolvedDate,
          items: items,
          emptyBarnikaOutCount: nextOut,
          emptyBarnikaReturnedCount: nextReturned,
        );
      }

      final updated = await getInvoiceById(invoiceId);
      if (updated == null) throw Exception('فشل في تحديث الفاتورة');
      return updated;
    });
  }

  /// Records outgoing empty barnika custody and immediate returns atomically
  /// inside the invoice transaction.
  Future<void> _applyEmptyBarnikaForInvoice({
    required int invoiceId,
    required String? customerId,
    required DateTime resolvedDate,
    required List<InvoiceItemParams> items,
    required int? emptyBarnikaOutCount,
    required int? emptyBarnikaReturnedCount,
  }) async {
    final hasCustomer =
        customerId != null && customerId != 'cash' && customerId.isNotEmpty;
    final shipmentQty = items
        .where((i) => i.shipmentId != null)
        .fold<int>(0, (sum, i) => sum + i.quantity);

    final outCount = emptyBarnikaOutCount ?? (hasCustomer ? shipmentQty : 0);
    final returnedCount = emptyBarnikaReturnedCount ?? 0;

    if (outCount < 0 || returnedCount < 0) {
      throw ArgumentError('عدد البرانيك لا يمكن أن يكون سالباً');
    }
    if ((outCount > 0 || returnedCount > 0) && !hasCustomer) {
      throw ArgumentError(
        'يجب تحديد العميل لتسجيل عهدة أو استلام البرانيك الفارغة',
      );
    }
    if (!hasCustomer) return;

    if (outCount > 0) {
      final appliedOnCurrent = min(returnedCount, outCount);
      final excessReturned = returnedCount - appliedOnCurrent;
      final custodyStatus = appliedOnCurrent <= 0
          ? EmptyBarnikaStatus.outstanding
          : (appliedOnCurrent >= outCount
              ? EmptyBarnikaStatus.returned
              : EmptyBarnikaStatus.partial);

      await _db.emptyBarnikaTrackingDao.insertRecord(
        EmptyBarnikaTrackingCompanion.insert(
          customerId: customerId,
          dateOut: resolvedDate,
          quantityOut: outCount,
          quantityReturned: Value(appliedOnCurrent),
          dateReturned: Value(appliedOnCurrent > 0 ? resolvedDate : null),
          status: Value(custodyStatus),
          invoiceId: Value(invoiceId),
        ),
      );

      if (excessReturned > 0) {
        await _db.emptyBarnikaTrackingDao.recordCustomerReturnFifo(
          customerId: customerId,
          quantityReturned: excessReturned,
          dateReturned: resolvedDate,
        );
      }
    } else if (returnedCount > 0) {
      await _db.emptyBarnikaTrackingDao.recordCustomerReturnFifo(
        customerId: customerId,
        quantityReturned: returnedCount,
        dateReturned: resolvedDate,
      );
    }
  }

  Future<void> voidInvoice(int invoiceId, String reason, String voidedBy) async {
    await _db.invoiceDao.voidInvoice(invoiceId, reason, voidedBy);
  }

  Future<void> updateInvoice(Insertable<Invoice> invoice) async {
    await _db.invoiceDao.updateInvoice(invoice);
  }

  Future<Invoice?> getInvoiceById(int id) async {
    final invoices = await (_db.select(_db.invoices)..where((t) => t.id.equals(id))).get();
    return invoices.isNotEmpty ? invoices.first : null;
  }
}

class SplitPaymentEntry {
  final String method;
  final double amount;

  SplitPaymentEntry({required this.method, required this.amount});
}
