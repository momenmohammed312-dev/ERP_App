import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';

class ImportResult {
  final int suppliers;
  final int customers;
  final int shipments;
  final int sales;
  final int expenses;
  final int collections;
  final int emptyBarnika;
  final List<String> errors;

  ImportResult({
    required this.suppliers,
    required this.customers,
    required this.shipments,
    required this.sales,
    required this.expenses,
    required this.collections,
    required this.emptyBarnika,
    required this.errors,
  });

  int get total =>
      suppliers + customers + shipments + sales + expenses + collections + emptyBarnika;
}

class VegetableMarketImportService {
  final AppDatabase _db;
  static const _productName = 'بارنيكة خضار';
  int? _defaultProductId;
  final _uuid = const Uuid();
  final _existingSupplierNames = <String>{};
  final _existingCustomerNames = <String>{};
  final _existingShipmentNumbers = <String>{};

  VegetableMarketImportService(this._db);

  Future<ImportResult> importFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Import file not found', filePath);
    }
    final contents = await file.readAsString();
    return _importData(json.decode(contents) as Map<String, dynamic>);
  }

  Future<ImportResult> importFromJsonString(String jsonString) async {
    return _importData(json.decode(jsonString) as Map<String, dynamic>);
  }

  Future<ImportResult> _importData(Map<String, dynamic> data) async {
    final errors = <String>[];
    var sCount = 0;
    var cCount = 0;
    var shCount = 0;
    var saCount = 0;
    var eCount = 0;
    var colCount = 0;
    var ebCount = 0;

    final allSuppliers = (data['suppliers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allCustomers = (data['customers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allShipments = (data['shipments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allSales = (data['sales'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allExpenses = (data['expenses'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allCollections = (data['collections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allEmptyBarnika =
        (data['emptyBarnikaRecords'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final names = await Future.wait([
      _existingSupplierNamesFromDb(),
      _existingCustomerNamesFromDb(),
      _existingShipmentNumbersFromDb(),
    ]);
    _existingSupplierNames.addAll(names[0]);
    _existingCustomerNames.addAll(names[1]);
    _existingShipmentNumbers.addAll(names[2]);

    _defaultProductId = await _findOrCreateProduct();

    final shipmentUuidToId = <String, int>{};
    final customerNameToId = <String, String>{};

    for (final c in allCustomers) {
      final id = c['id'] as String;
      final name = c['name'] as String;
      customerNameToId[name] = id;
    }

    await _db.transaction(() async {
      for (final s in allSuppliers) {
        try {
          await _importSupplier(s);
          sCount++;
        } catch (e) {
          errors.add('Supplier "${s['name']}": $e');
        }
      }

      for (final c in allCustomers) {
        try {
          await _importCustomer(c);
          cCount++;
        } catch (e) {
          errors.add('Customer "${c['name']}": $e');
        }
      }

      for (final s in allShipments) {
        try {
          final newId = await _importShipment(s);
          final uuid = s['id'] as String;
          shipmentUuidToId[uuid] = newId;
          shCount++;
        } catch (e) {
          errors.add('Shipment "${s['shipmentNumber']}": $e');
        }
      }

      for (final sale in allSales) {
        try {
          await _importSale(sale, shipmentUuidToId);
          saCount++;
        } catch (e) {
          errors.add('Sale "${sale['customerName']}" ${sale['date']}: $e');
        }
      }

      for (final exp in allExpenses) {
        try {
          await _importExpense(exp);
          eCount++;
        } catch (e) {
          errors.add('Expense ${exp['description']}: $e');
        }
      }

      for (final col in allCollections) {
        try {
          await _importCollection(col, customerNameToId);
          colCount++;
        } catch (e) {
          errors.add('Collection ${col['customerName']} ${col['amount']}: $e');
        }
      }

      for (final eb in allEmptyBarnika) {
        try {
          await _importEmptyBarnika(eb);
          ebCount++;
        } catch (e) {
          errors.add('EmptyBarnika ${eb['customerName']}: $e');
        }
      }
    });

    return ImportResult(
      suppliers: sCount,
      customers: cCount,
      shipments: shCount,
      sales: saCount,
      expenses: eCount,
      collections: colCount,
      emptyBarnika: ebCount,
      errors: errors,
    );
  }

  Future<Set<String>> _existingSupplierNamesFromDb() async {
    final suppliers = await _db.supplierDao.getAllSuppliers();
    return suppliers.map((s) => s.name).toSet();
  }

  Future<Set<String>> _existingCustomerNamesFromDb() async {
    final customers = await _db.customerDao.getAllCustomers();
    return customers.map((c) => c.name).toSet();
  }

  Future<Set<String>> _existingShipmentNumbersFromDb() async {
    final shipments = await _db.vegetableShipmentDao.getAll();
    return shipments.map((s) => s.shipmentNumber).toSet();
  }

  Future<int> _findOrCreateProduct() async {
    final existing = await (_db.select(_db.products)
          ..where((p) => p.name.equals(_productName)))
        .get();
    if (existing.isNotEmpty) {
      return existing.first.id;
    }
    return _db.into(_db.products).insert(ProductsCompanion.insert(
          name: _productName,
          quantity: 0,
          price: 0,
          unit: Value('بارنيكة'),
          category: Value('خضار'),
          barneka: Value(true),
        ));
  }

  Future<void> _importSupplier(Map<String, dynamic> s) async {
    final name = s['name'] as String;
    if (_existingSupplierNames.contains(name)) return;
    await _db.into(_db.suppliers).insert(SuppliersCompanion.insert(
          id: s['id'] as String,
          name: name,
          phone: Value((s['phone'] as String?)?.isNotEmpty == true ? s['phone'] as String : null),
          address:
              Value((s['address'] as String?)?.isNotEmpty == true ? s['address'] as String : null),
          status: Value(s['status'] as String? ?? 'Active'),
        ));
    _existingSupplierNames.add(name);
  }

  Future<void> _importCustomer(Map<String, dynamic> c) async {
    final name = c['name'] as String;
    if (_existingCustomerNames.contains(name)) return;
    final status = c['status'] as String? ?? 'Active';
    final notes = c['type'] as String?;
    await _db.into(_db.customers).insert(CustomersCompanion.insert(
          id: c['id'] as String,
          name: name,
          phone: Value((c['phone'] as String?)?.isNotEmpty == true ? c['phone'] as String : null),
          address:
              Value((c['address'] as String?)?.isNotEmpty == true ? c['address'] as String : null),
          status: Value(status),
          notes: Value(notes?.isNotEmpty == true ? notes : null),
        ));
    _existingCustomerNames.add(name);
  }

  Future<int> _importShipment(Map<String, dynamic> s) async {
    final shipmentNumber = s['shipmentNumber'] as String;
    if (_existingShipmentNumbers.contains(shipmentNumber)) {
      final existing = await (_db.select(_db.vegetableShipments)
            ..where((t) => t.shipmentNumber.equals(shipmentNumber)))
          .get();
      if (existing.isNotEmpty) return existing.first.id;
    }
    final pricingMode = s['pricingMode'] as String;
    final totalBarnikaCount = s['totalBarnikaCount'] as int;
    final totalCost = (s['totalCost'] as num).toDouble();
    final barnikaRemainingCount = s['barnikaRemainingCount'] as int;
    final barnikaSoldCount = s['barnikaSoldCount'] as int? ?? 0;
    final date = DateTime.parse(s['date'] as String);

    return _db.into(_db.vegetableShipments).insert(VegetableShipmentsCompanion.insert(
          supplierId: s['supplierId'] as String,
          shipmentNumber: shipmentNumber,
          pricingMode: pricingMode,
          totalBarnikaCount: totalBarnikaCount,
          totalCost: totalCost,
          barnikaRemainingCount: barnikaRemainingCount,
          date: Value(date),
          barnikaSoldCount: Value(barnikaSoldCount),
          costPricePerBarnika: Value(
              s['costPricePerBarnika'] != null ? (s['costPricePerBarnika'] as num).toDouble() : null),
          lumpSumCost: Value(
              s['lumpSumCost'] != null ? (s['lumpSumCost'] as num).toDouble() : null),
          commissionPercentage: Value(
              s['commissionPercentage'] != null ? (s['commissionPercentage'] as num).toDouble() : null),
          containerPrice: Value(
              s['containerPrice'] != null ? (s['containerPrice'] as num).toDouble() : null),
          notes: Value((s['notes'] as String?)?.isNotEmpty == true ? s['notes'] as String : null),
        ));
  }

  Future<void> _importSale(Map<String, dynamic> sale, Map<String, int> shipmentUuidToId) async {
    final productId = _defaultProductId;
    if (productId == null) throw Exception('Default product not found');

    final customerId = sale['customerId'] as String?;
    final customerName = sale['customerName'] as String;
    final date = DateTime.parse(sale['date'] as String);
    final quantity = sale['quantity'] as int;
    final pricePerUnit = (sale['pricePerUnit'] as num).toDouble();
    final totalAmount = (sale['totalAmount'] as num).toDouble();
    final paidAmount = (sale['paidAmount'] as num).toDouble();
    final cashAmount = (sale['cashAmount'] as num).toDouble();
    final creditAmount = (sale['creditAmount'] as num).toDouble();
    final discount = (sale['discount'] as num?)?.toDouble() ?? 0;
    final status = sale['status'] as String? ?? 'pending';
    final paymentMethod = sale['paymentMethod'] as String? ?? 'cash';
    final notes = sale['notes'] as String? ?? '';
    final shipmentId = sale['shipmentId'] as String?;
    final shipmentNumber = sale['shipmentNumber'] as String?;

    final shipmentIntId = shipmentId != null ? shipmentUuidToId[shipmentId] : null;
    final pricingMode = sale['pricingMode'] as String?;
    final isCommission = pricingMode == 'commission';

    final invNumber = 'IMP-${date.toIso8601String().substring(0, 10).replaceAll('-', '')}-${_uuid.v4().substring(0, 8)}';

    final invoiceId = await _db.into(_db.invoices).insert(InvoicesCompanion(
          invoiceNumber: Value(invNumber),
          customerId: Value(customerId),
          customerName: Value(customerName),
          paymentMethod: Value(paymentMethod),
          totalAmount: Value(totalAmount),
          paidAmount: Value(paidAmount),
          date: Value(date),
          status: Value(status == 'paid' ? 'paid' : 'pending'),
          cashAmount: Value(cashAmount),
          creditAmount: Value(creditAmount),
          shipmentId: Value(shipmentIntId),
        ));

    final unitCost = shipmentIntId != null && !isCommission
        ? await _unitCostForShipment(shipmentIntId)
        : null;

    await _db.into(_db.invoiceItems).insert(InvoiceItemsCompanion.insert(
          invoiceId: invoiceId,
          productId: productId,
          price: (totalAmount - discount) / (quantity > 0 ? quantity : 1),
          quantity: Value(quantity),
          discount: Value(discount),
          commission: Value(0.0),
          unitCostAtTime: Value(unitCost),
          shipmentId: Value(shipmentIntId),
        ));

    if (status == 'paid' && paidAmount > 0) {
      await _db.into(_db.invoicePayments).insert(InvoicePaymentsCompanion.insert(
            invoiceId: invoiceId,
            paymentMethod: paymentMethod,
            amount: paidAmount,
            paidAt: Value(date),
            notes: Value(notes.isNotEmpty ? notes : null),
          ));
    }

    if (isCommission && shipmentIntId != null) {
      final shipment = await _db.vegetableShipmentDao.getById(shipmentIntId);
      if (shipment != null) {
        final commPct = shipment.commissionPercentage;
        if (commPct != null && commPct > 0) {
          final commissionAmount = totalAmount * commPct / 100;
          await _db.into(_db.ledgerTransactions).insert(LedgerTransactionsCompanion.insert(
                id: _uuid.v4(),
                entityType: 'Supplier',
                refId: shipment.supplierId,
                date: date,
                description: 'عمولة بيع شحنة $shipmentNumber',
                credit: Value(commissionAmount),
                origin: 'import',
              ));
        }
      }
    }
  }

  Future<double?> _unitCostForShipment(int shipmentId) async {
    final shipment = await _db.vegetableShipmentDao.getById(shipmentId);
    return shipment?.costPricePerBarnika;
  }

  Future<void> _importExpense(Map<String, dynamic> exp) async {
    await _db.into(_db.expenses).insert(ExpensesCompanion.insert(
          id: _uuid.v4(),
          description: exp['description'] as String,
          amount: (exp['amount'] as num).toDouble(),
          category: exp['category'] as String,
          date: Value(DateTime.parse(exp['date'] as String)),
          notes: Value((exp['notes'] as String?)?.isNotEmpty == true ? exp['notes'] as String : null),
        ));
  }

  Future<void> _importCollection(
      Map<String, dynamic> col, Map<String, String> customerNameToId) async {
    final customerName = col['customerName'] as String;
    final totalAmount = (col['amount'] as num).toDouble();
    final date = DateTime.parse(col['date'] as String);
    final notes = col['notes'] as String? ?? '';

    final customerId = customerNameToId[customerName];
    if (customerId == null) {
      return;
    }

    final pendingInvoices = await (_db.select(_db.invoices)
          ..where((t) => (t.customerId.equals(customerId)) & (t.status.equals('pending')))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();

    var remainingCollection = totalAmount;
    for (final inv in pendingInvoices) {
      if (remainingCollection <= 0) break;
      final invRemaining = inv.totalAmount - inv.paidAmount;
      if (invRemaining <= 0) continue;

      final paymentAmount = remainingCollection >= invRemaining ? invRemaining : remainingCollection;

      await _db.into(_db.invoicePayments).insert(InvoicePaymentsCompanion.insert(
            invoiceId: inv.id,
            paymentMethod: 'cash',
            amount: paymentAmount,
            paidAt: Value(date),
            notes: Value(notes.isNotEmpty ? notes : null),
          ));

      final newPaid = inv.paidAmount + paymentAmount;
      final newStatus = newPaid >= inv.totalAmount ? 'paid' : 'pending';

      await (_db.update(_db.invoices)..where((t) => t.id.equals(inv.id))).write(InvoicesCompanion(
            paidAmount: Value(newPaid),
            status: Value(newStatus),
          ));

      remainingCollection -= paymentAmount;
    }

    if (remainingCollection > 0.001) {
      await _db.into(_db.ledgerTransactions).insert(LedgerTransactionsCompanion.insert(
            id: _uuid.v4(),
            entityType: 'Customer',
            refId: customerId,
            date: date,
            description: 'تحصيل $notes',
            credit: Value(remainingCollection),
            origin: 'import',
          ));
    }
  }

  Future<void> _importEmptyBarnika(Map<String, dynamic> eb) async {
    final customerId = eb['customerId'] as String;
    final dateOut = DateTime.parse(eb['dateOut'] as String);
    final quantityOut = eb['quantityOut'] as int;
    final quantityReturned = eb['quantityReturned'] as int? ?? 0;
    final status = eb['status'] as String? ?? 'out';
    final dateReturned = eb['dateReturned'] != null ? DateTime.parse(eb['dateReturned'] as String) : null;

    await _db.into(_db.emptyBarnikaTracking).insert(EmptyBarnikaTrackingCompanion.insert(
          customerId: customerId,
          dateOut: dateOut,
          quantityOut: quantityOut,
          quantityReturned: Value(quantityReturned),
          dateReturned: Value(dateReturned),
          status: Value(status),
        ));
  }
}
