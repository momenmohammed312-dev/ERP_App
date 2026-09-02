import 'dart:math';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../database/tables/vegetable_shipments_table.dart';
import 'accounting_service.dart';
import 'audit_log_service.dart';
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

  InvoiceItemParams({
    required this.productId,
    required this.quantity,
    required this.price,
    this.ctn,
    this.discount = 0,
    this.commission = 0,
    this.unitCostAtTime,
    this.shipmentId,
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
  }) async {
    final actualInvoiceNumber = invoiceNumber ?? 'INV${DateTime.now().millisecondsSinceEpoch}';
    final rand = Random.secure();

    return _db.transaction(() async {
      final invoiceId = await _db.invoiceDao.insertInvoice(
        InvoicesCompanion(
          invoiceNumber: Value(actualInvoiceNumber),
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
          date: Value(DateTime.now()),
          shipmentId: Value(primaryShipmentId),
        ),
      );

      // Track supplier commission totals per shipment for ledger entries.
      final supplierCommissions = <int, _SupplierCommissionAccumulator>{};
      double cogsAmount = 0;

      for (final item in items) {
        final product = await _db.productDao.getProductById(item.productId);

        if (product == null) {
          throw Exception('المنتج غير موجود (ID: ${item.productId})');
        }

        final unitCost = item.unitCostAtTime ?? product.costPrice ?? 0;
        if (unitCost > 0) cogsAmount += unitCost * item.quantity;

        final newQty = product.quantity - item.quantity;
        await _db.productDao.updateProduct(
          ProductsCompanion(
            id: Value(product.id),
            name: Value(product.name),
            quantity: Value(newQty < 0 ? 0 : newQty),
            price: Value(product.price),
            unit: Value(product.unit),
            category: Value(product.category),
            barcode: Value(product.barcode),
            cartonQuantity: Value(product.cartonQuantity),
            cartonPrice: Value(product.cartonPrice),
            status: Value(product.status),
          ),
        );

        // Auto-calculate commission for commission-based shipments.
        var itemCommission = item.commission;
        if (item.shipmentId != null && itemCommission == 0) {
          final shipment = await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment != null &&
              shipment.pricingMode == ShipmentPricingMode.commission &&
              shipment.commissionPercentage != null) {
            itemCommission = ShipmentPricingService.calculateCommission(
              item.price * item.quantity,
              shipment.commissionPercentage!,
            );
          }
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
          ),
        );

        // Update shipment barnika counts.
        if (item.shipmentId != null) {
          final shipment = await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment == null) {
            throw Exception('الشحنة #${item.shipmentId} غير موجودة');
          }

          final newSold = shipment.barnikaSoldCount + item.quantity;
          final newRemaining = shipment.barnikaRemainingCount - item.quantity;
          if (newRemaining < 0) {
            throw Exception(
              'الشحنة #${item.shipmentId} لا تحتوي على كمية كافية '
              '(متبقي: ${shipment.barnikaRemainingCount}, مطلوب: ${item.quantity})',
            );
          }

          await _db.vegetableShipmentDao.updateShipment(
            shipment.copyWith(
              barnikaSoldCount: newSold,
              barnikaRemainingCount: newRemaining,
            ),
          );

          // Accumulate supplier commission for ledger entry.
          if (itemCommission > 0) {
            supplierCommissions.putIfAbsent(
              item.shipmentId!,
              () => _SupplierCommissionAccumulator(shipment.supplierId),
            ).add(item.price * item.quantity, itemCommission);
          }
        }
      }

      if (splitPayments != null) {
        for (final sp in splitPayments) {
          await _db.invoicePaymentsDao.insertPayment(
            InvoicePaymentsCompanion.insert(
              invoiceId: invoiceId,
              paymentMethod: sp.method,
              amount: sp.amount,
            ),
          );
        }
      }

      final desc = ledgerDescription ?? 'بيع #$actualInvoiceNumber';

      if (customerId != null && customerId != 'cash' && customerId.isNotEmpty) {
        final ledgerIdSale = '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_sale';
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: ledgerIdSale,
            entityType: 'Customer',
            refId: customerId,
            date: DateTime.now(),
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
              date: DateTime.now(),
              description: 'دفع #$actualInvoiceNumber',
              debit: const Value(0.0),
              credit: Value(paidAmount),
              origin: 'payment',
              paymentMethod: Value(paymentMethod),
              receiptNumber: Value('INV$invoiceId'),
            ),
          );
        }
      }

      // Create supplier ledger entries for commission-based shipments.
      for (final entry in supplierCommissions.entries) {
        final acc = entry.value;
        final supplierDue = acc.sellAmount - acc.commissionAmount;
        final ledgerIdSupplier =
            '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_supplier';
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: ledgerIdSupplier,
            entityType: 'Supplier',
            refId: acc.supplierId,
            date: DateTime.now(),
            description: 'عمولة بيع #$actualInvoiceNumber',
            debit: Value(supplierDue),
            credit: const Value(0.0),
            origin: 'sale',
            receiptNumber: Value('INV$invoiceId'),
          ),
        );
      }

      // ── Headless Accounting: Journal entries (Phase 2) ──
      // Additive, inside same transaction — failure rolls back whole invoice.
      try {
        final accounting = AccountingService(_db);
        Future<String> accId(String code) async {
          final a = await _db.accountsDao.getByCode(code);
          if (a == null) throw Exception('Account $code not found — v57 migration missing');
          return a.id;
        }

        final cashId = await accId('1000');
        final bankId = await accId('1010');
        final arId = await accId('1100');
        final revenueId = await accId('4000');
        final cogsId = await accId('5000');
        final inventoryId = await accId('1200');

        final isCashSale = customerId == null || customerId == 'cash' || customerId.isEmpty;
        final cashOrBankId = paymentMethod == 'cash' ? cashId : bankId;
        final now = DateTime.now();

        if (isCashSale) {
          await accounting.postSale(
            sourceId: invoiceId.toString(),
            date: now,
            description: 'بيع كاش #$actualInvoiceNumber',
            revenueAmount: totalAmount,
            revenueAccountId: revenueId,
            debitAccountId: cashOrBankId,
          );
        } else {
          await accounting.postSale(
            sourceId: invoiceId.toString(),
            date: now,
            description: desc,
            revenueAmount: totalAmount,
            revenueAccountId: revenueId,
            debitAccountId: arId,
          );
          if (paidAmount > 0) {
            await accounting.postCustomerPayment(
              sourceId: '${invoiceId}_pay',
              date: now,
              amount: paidAmount,
              cashOrBankAccountId: cashOrBankId,
              arAccountId: arId,
            );
          }
        }

        if (cogsAmount > 0) {
          await accounting.postSaleCogs(
            sourceId: invoiceId.toString(),
            date: now,
            cogsAmount: cogsAmount,
            cogsAccountId: cogsId,
            inventoryAccountId: inventoryId,
          );
        } else if (items.isNotEmpty) {
          await AuditService.log(
            db: _db,
            action: 'UNRESOLVED_COST',
            tableName: 'invoice_items',
            recordId: invoiceId,
            details: 'no cost available for COGS posting invoice $actualInvoiceNumber — profit may be understated',
          );
        }
        // Supplier commission journal is global (per user answer) but deferred to Phase 3
        // to keep Phase 2 minimal and avoid 3-line entry complexity. Ledger commission remains.
      } catch (e) {
        // Any accounting failure must abort the whole invoice per §24
        rethrow;
      }

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
  }) async {
    final original = await getInvoiceById(invoiceId);
    if (original == null) throw Exception('الفاتورة غير موجودة');
    if (original.status == 'voided') {
      throw Exception('لا يمكن تعديل فاتورة ملغاة');
    }

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

      // 1a. Reverse original stock + shipment counts.
      for (final item in originalItems) {
        final product = await _db.productDao.getProductById(item.productId);
        if (product != null) {
          await _db.productDao.updateProduct(
            product.copyWith(quantity: product.quantity + item.quantity),
          );
        }
        if (item.shipmentId != null) {
          final shipment =
              await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment != null) {
            await _db.vegetableShipmentDao.updateShipment(
              shipment.copyWith(
                barnikaSoldCount:
                    (shipment.barnikaSoldCount - item.quantity).clamp(0, 1 << 62),
                barnikaRemainingCount:
                    shipment.barnikaRemainingCount + item.quantity,
              ),
            );
          }
        }
      }

      // 1b. Reverse original ledger rows + line items for this invoice.
      await _db.ledgerDao
          .deleteTransactionsByReceiptNumber('INV$invoiceId');
      await _db.invoiceDao.deleteInvoiceItemsByInvoice(invoiceId);

      // 2a. Re-apply edited items.
      final supplierCommissions = <int, _SupplierCommissionAccumulator>{};
      double cogsAmountEdit = 0;
      for (final item in items) {
        final product = await _db.productDao.getProductById(item.productId);
        if (product == null) {
          throw Exception('المنتج غير موجود (ID: ${item.productId})');
        }

        final unitCost = item.unitCostAtTime ?? product.costPrice ?? 0;
        if (unitCost > 0) cogsAmountEdit += unitCost * item.quantity;

        final newQty = product.quantity - item.quantity;
        await _db.productDao.updateProduct(
          product.copyWith(quantity: newQty < 0 ? 0 : newQty),
        );

        var itemCommission = item.commission;
        if (item.shipmentId != null && itemCommission == 0) {
          final shipment =
              await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment != null &&
              shipment.pricingMode == ShipmentPricingMode.commission &&
              shipment.commissionPercentage != null) {
            itemCommission = ShipmentPricingService.calculateCommission(
              item.price * item.quantity,
              shipment.commissionPercentage!,
            );
          }
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
          ),
        );

        if (item.shipmentId != null) {
          final shipment =
              await _db.vegetableShipmentDao.getById(item.shipmentId!);
          if (shipment == null) {
            throw Exception('الشحنة #${item.shipmentId} غير موجودة');
          }
          final newSold = shipment.barnikaSoldCount + item.quantity;
          final newRemaining = shipment.barnikaRemainingCount - item.quantity;
          if (newRemaining < 0) {
            throw Exception(
              'الشحنة #${item.shipmentId} لا تحتوي على كمية كافية '
              '(متبقي: ${shipment.barnikaRemainingCount}, مطلوب: ${item.quantity})',
            );
          }
          await _db.vegetableShipmentDao.updateShipment(
            shipment.copyWith(
              barnikaSoldCount: newSold,
              barnikaRemainingCount: newRemaining,
            ),
          );
          if (itemCommission > 0) {
            supplierCommissions
                .putIfAbsent(
                  item.shipmentId!,
                  () => _SupplierCommissionAccumulator(shipment.supplierId),
                )
                .add(item.price * item.quantity, itemCommission);
          }
        }
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
          shipmentId: Value(primaryShipmentId),
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
            date: DateTime.now(),
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
              date: DateTime.now(),
              description: 'دفع #$actualInvoiceNumber',
              debit: const Value(0.0),
              credit: Value(paidAmount),
              origin: 'payment',
              paymentMethod: Value(paymentMethod),
              receiptNumber: Value('INV$invoiceId'),
            ),
          );
        }
      }

      // 2d. Supplier commission ledger entries.
      for (final entry in supplierCommissions.entries) {
        final acc = entry.value;
        final supplierDue = acc.sellAmount - acc.commissionAmount;
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id:
                '${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(999999)}_supplier',
            entityType: 'Supplier',
            refId: acc.supplierId,
            date: DateTime.now(),
            description: 'عمولة بيع #$actualInvoiceNumber',
            debit: Value(supplierDue),
            credit: const Value(0.0),
            origin: 'sale',
            receiptNumber: Value('INV$invoiceId'),
          ),
        );
      }

      // ── Headless Accounting: reverse old + post new (Phase 2) ──
      try {
        final accounting = AccountingService(_db);
        // Reverse any existing journal entries for this invoice (idempotent)
        for (final key in ['sale:INV$invoiceId', 'sale_cogs:INV$invoiceId', 'customer_payment:${invoiceId}_pay']) {
          final existing = await _db.journalDao.getByPostingKey(key);
          if (existing != null && existing.status != 'reversed') {
            await _db.journalDao.reverseEntry(originalEntryId: existing.id);
          }
        }
        Future<String> accId(String code) async {
          final a = await _db.accountsDao.getByCode(code);
          if (a == null) throw Exception('Account $code not found');
          return a.id;
        }

        final cashId = await accId('1000');
        final bankId = await accId('1010');
        final arId = await accId('1100');
        final revenueId = await accId('4000');
        final cogsId = await accId('5000');
        final inventoryId = await accId('1200');

        final isCashSale = customerId == null || customerId == 'cash' || customerId.isEmpty;
        final cashOrBankId = paymentMethod == 'cash' ? cashId : bankId;
        final now = DateTime.now();
        final desc2 = 'بيع #$actualInvoiceNumber';

        if (isCashSale) {
          await accounting.postSale(
            sourceId: invoiceId.toString(),
            date: now,
            description: 'بيع كاش #$actualInvoiceNumber',
            revenueAmount: totalAmount,
            revenueAccountId: revenueId,
            debitAccountId: cashOrBankId,
          );
        } else {
          await accounting.postSale(
            sourceId: invoiceId.toString(),
            date: now,
            description: desc2,
            revenueAmount: totalAmount,
            revenueAccountId: revenueId,
            debitAccountId: arId,
          );
          if (paidAmount > 0) {
            await accounting.postCustomerPayment(
              sourceId: '${invoiceId}_pay',
              date: now,
              amount: paidAmount,
              cashOrBankAccountId: cashOrBankId,
              arAccountId: arId,
            );
          }
        }

        if (cogsAmountEdit > 0) {
          await accounting.postSaleCogs(
            sourceId: invoiceId.toString(),
            date: now,
            cogsAmount: cogsAmountEdit,
            cogsAccountId: cogsId,
            inventoryAccountId: inventoryId,
          );
        } else if (items.isNotEmpty) {
          await AuditService.log(
            db: _db,
            action: 'UNRESOLVED_COST',
            tableName: 'invoice_items',
            recordId: invoiceId,
            details: 'no cost available for COGS posting invoice $actualInvoiceNumber (edit)',
          );
        }
      } catch (e) {
        rethrow;
      }

      final updated = await getInvoiceById(invoiceId);
      if (updated == null) throw Exception('فشل في تحديث الفاتورة');
      return updated;
    });
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

/// Accumulates sell amount and commission for a single supplier across
/// multiple invoice items from the same shipment (or different shipments
/// of the same supplier).
class _SupplierCommissionAccumulator {
  final String supplierId;
  double sellAmount = 0;
  double commissionAmount = 0;

  _SupplierCommissionAccumulator(this.supplierId);

  void add(double sell, double commission) {
    sellAmount += sell;
    commissionAmount += commission;
  }
}
