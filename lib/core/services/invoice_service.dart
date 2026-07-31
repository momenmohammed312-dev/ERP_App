import 'dart:math';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../database/tables/vegetable_shipments_table.dart';
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

      for (final item in items) {
        final product = await _db.productDao.getProductById(item.productId);

        if (product == null) {
          throw Exception('المنتج غير موجود (ID: ${item.productId})');
        }

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
