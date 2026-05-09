import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/enhanced_purchase_tables.dart';

part 'enhanced_purchase_dao.g.dart';

@DriftAccessor(
  tables: [
    EnhancedSuppliers,
    EnhancedPurchases,
    EnhancedPurchaseItems,
    SupplierPayments,
  ],
)
class EnhancedPurchaseDao extends DatabaseAccessor<AppDatabase>
    with _$EnhancedPurchaseDaoMixin {
  EnhancedPurchaseDao(super.db);

  // Enhanced Suppliers operations
  Future<List<EnhancedSupplier>> getAllSuppliers() =>
      select(db.enhancedSuppliers).get();

  Stream<List<EnhancedSupplier>> watchAllSuppliers() =>
      select(db.enhancedSuppliers).watch();

  Future<EnhancedSupplier?> getSupplierById(int id) => (select(
    db.enhancedSuppliers,
  )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<void> insertSupplier(EnhancedSuppliersCompanion supplier) =>
      into(db.enhancedSuppliers).insert(supplier);

  Future<void> updateSupplier(EnhancedSupplier supplier) =>
      update(db.enhancedSuppliers).replace(supplier);

  Future<void> deleteSupplier(int id) =>
      (delete(db.enhancedSuppliers)..where((tbl) => tbl.id.equals(id))).go();

  // Enhanced Purchases operations
  Future<List<EnhancedPurchase>> getAllPurchases() =>
      select(db.enhancedPurchases).get();

  Stream<List<EnhancedPurchase>> watchAllPurchases() =>
      select(db.enhancedPurchases).watch();

  Future<List<EnhancedPurchase>> getPurchasesBySupplier(int supplierId) =>
      (select(
        db.enhancedPurchases,
      )..where((tbl) => tbl.supplierId.equals(supplierId))).get();

  Future<List<EnhancedPurchase>> getPurchasesByDateRange(
    DateTime start,
    DateTime end,
  ) {
    return (select(db.enhancedPurchases)
          ..where(
            (tbl) => tbl.purchaseDate.isBetween(Constant(start), Constant(end)),
          )
          ..orderBy([
            (tbl) => OrderingTerm(
              expression: tbl.purchaseDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  Future<EnhancedPurchase?> getPurchaseById(int id) => (select(
    db.enhancedPurchases,
  )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<void> insertPurchase(EnhancedPurchasesCompanion purchase) =>
      into(db.enhancedPurchases).insert(purchase);

  Future<void> updatePurchase(EnhancedPurchase purchase) =>
      update(db.enhancedPurchases).replace(purchase);

  Future<void> deletePurchase(int id) =>
      (delete(db.enhancedPurchases)..where((tbl) => tbl.id.equals(id))).go();

  // Enhanced Purchase Items operations
  Future<List<EnhancedPurchaseItem>> getItemsByPurchase(int purchaseId) =>
      (select(
        db.enhancedPurchaseItems,
      )..where((tbl) => tbl.purchaseId.equals(purchaseId))).get();

  Future<List<(EnhancedPurchaseItem, Product?)>> getItemsWithProductsByPurchase(
    int purchaseId,
  ) {
    final query = select(db.enhancedPurchaseItems).join([
      leftOuterJoin(
        db.products,
        db.products.id.equalsExp(db.enhancedPurchaseItems.productId),
      ),
    ])..where(db.enhancedPurchaseItems.purchaseId.equals(purchaseId));

    return query.get().then((rows) {
      return rows.map((row) {
        return (
          row.readTable(db.enhancedPurchaseItems),
          row.readTableOrNull(db.products),
        );
      }).toList();
    });
  }

  Future<void> insertPurchaseItem(EnhancedPurchaseItemsCompanion item) =>
      into(db.enhancedPurchaseItems).insert(item);

  Future<void> insertPurchaseItems(
    List<EnhancedPurchaseItemsCompanion> items,
  ) => batch((batch) {
    for (final item in items) {
      batch.insert(db.enhancedPurchaseItems, item);
    }
  });

  Future<void> deletePurchaseItemsByPurchase(int purchaseId) => (delete(
    db.enhancedPurchaseItems,
  )..where((tbl) => tbl.purchaseId.equals(purchaseId))).go();

  // Supplier Payments operations
  Future<List<SupplierPayment>> getPaymentsBySupplier(int supplierId) =>
      (select(
        db.supplierPayments,
      )..where((tbl) => tbl.supplierId.equals(supplierId))).get();

  Future<void> insertPayment(SupplierPaymentsCompanion payment) =>
      into(db.supplierPayments).insert(payment);

  // Statistics and reporting
  Future<double> getTotalPurchasesByDateRange(DateTime start, DateTime end) {
    final query = selectOnly(db.enhancedPurchases)
      ..addColumns([db.enhancedPurchases.totalAmount.sum()])
      ..where(
        db.enhancedPurchases.purchaseDate.isBetween(
          Constant(start),
          Constant(end),
        ),
      );

    return query.getSingle().then(
      (result) => result.read(db.enhancedPurchases.totalAmount.sum()) ?? 0.0,
    );
  }

  Future<double> getTotalCreditPurchases() {
    final query = selectOnly(db.enhancedPurchases)
      ..addColumns([db.enhancedPurchases.totalAmount.sum()])
      ..where(db.enhancedPurchases.isCreditPurchase.equals(true));

    return query.getSingle().then(
      (result) => result.read(db.enhancedPurchases.totalAmount.sum()) ?? 0.0,
    );
  }

  Future<double> getTotalCashPurchases() {
    final query = selectOnly(db.enhancedPurchases)
      ..addColumns([db.enhancedPurchases.totalAmount.sum()])
      ..where(db.enhancedPurchases.isCreditPurchase.equals(false));

    return query.getSingle().then(
      (result) => result.read(db.enhancedPurchases.totalAmount.sum()) ?? 0.0,
    );
  }

  Future<List<EnhancedSupplier>> getTopSuppliersByBalance(int limit) {
    return (select(db.enhancedSuppliers)
          ..where((tbl) => tbl.currentBalance.isBiggerThan(const Constant(0)))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.currentBalance)])
          ..limit(limit))
        .get();
  }

  Stream<double> watchTotalSupplierDues() {
    final query = selectOnly(db.enhancedSuppliers)
      ..addColumns([db.enhancedSuppliers.currentBalance.sum()])
      ..where(
        db.enhancedSuppliers.currentBalance.isBiggerThan(const Constant(0)),
      );

    return query.watchSingle().map(
      (result) => result.read(db.enhancedSuppliers.currentBalance.sum()) ?? 0.0,
    );
  }

  // Complete purchase creation with items and inventory updates
  Future<int> createCompletePurchase({
    required String purchaseNumber,
    required int supplierId,
    required String supplierName,
    required String supplierPhone,
    required DateTime purchaseDate,
    required double subtotal,
    required double totalAmount,
    required bool isCreditPurchase,
    required double previousBalance,
    required double paidAmount,
    required double remainingAmount,
    required String paymentMethod,
    String? notes,
    required List<EnhancedPurchaseItemsCompanion> items,
  }) async {
    return transaction(() async {
      // Insert purchase
      final purchaseId = await into(db.enhancedPurchases).insert(
        EnhancedPurchasesCompanion.insert(
          purchaseNumber: purchaseNumber,
          supplierId: supplierId,
          supplierName: supplierName,
          supplierPhone: supplierPhone,
          purchaseDate: purchaseDate,
          subtotal: subtotal,
          totalAmount: totalAmount,
          isCreditPurchase: Value(isCreditPurchase),
          previousBalance: Value(previousBalance),
          paidAmount: Value(paidAmount),
          remainingAmount: Value(remainingAmount),
          paymentMethod: paymentMethod,
          notes: Value(notes),
        ),
      );

      // Insert purchase items
      for (final item in items) {
        await into(
          db.enhancedPurchaseItems,
        ).insert(item.copyWith(purchaseId: Value(purchaseId)));

        // Update product stock (increase for purchases)
        final currentProduct = await (select(
          db.products,
        )..where((tbl) => tbl.id.equals(item.productId.value))).getSingle();
        await update(db.products).replace(
          currentProduct.copyWith(
            quantity: currentProduct.quantity + item.quantity.value,
          ),
        );
      }

      // Update supplier balance if credit purchase
      if (isCreditPurchase) {
        final supplier = await getSupplierById(supplierId);
        if (supplier != null) {
          await update(db.enhancedSuppliers).replace(
            supplier.copyWith(
              currentBalance: remainingAmount,
              updatedAt: DateTime.now(),
            ),
          );
        }
      }

      // Record payment if partial or cash
      if (paidAmount > 0) {
        await into(db.supplierPayments).insert(
          SupplierPaymentsCompanion.insert(
            supplierId: supplierId,
            purchaseId: Value(purchaseId),
            paymentNumber: 'PAY-${DateTime.now().millisecondsSinceEpoch}',
            paymentDate: DateTime.now(),
            amount: paidAmount,
            paymentMethod: paymentMethod == 'cash' ? 'cash' : 'bank_transfer',
          ),
        );
      }

      return purchaseId;
    });
  }
}
