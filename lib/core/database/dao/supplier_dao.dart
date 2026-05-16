import 'package:drift/drift.dart';

import '../tables/supplier_table.dart';
import '../app_database.dart';

part 'supplier_dao.g.dart';

@DriftAccessor(tables: [Suppliers])
class SupplierDao extends DatabaseAccessor<AppDatabase>
    with _$SupplierDaoMixin {
  SupplierDao(super.db);

  Future<List<Supplier>> getAllSuppliers() => select(suppliers).get();

  Future<Supplier?> getSupplierById(String id) =>
      (select(suppliers)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<List<Supplier>> getActiveSuppliers() =>
      (select(suppliers)..where((tbl) => tbl.status.equals('Active'))).get();

  Future<Supplier> insertSupplier(SuppliersCompanion supplier) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final supplierWithId = supplier.copyWith(id: Value(id));
    await into(suppliers).insert(supplierWithId);
    return await getSupplierById(id) ??
        (throw Exception('Failed to insert supplier'));
  }

  Future<bool> updateSupplier(SuppliersCompanion supplier) =>
      update(suppliers).replace(supplier);

  Future<int> deleteSupplier(String id) =>
      (delete(suppliers)..where((tbl) => tbl.id.equals(id))).go();

  Future<int> deactivateSupplier(String id) =>
      (update(suppliers)..where((tbl) => tbl.id.equals(id))).write(
        SuppliersCompanion(status: const Value('Inactive')),
      );

  Future<double> getSupplierBalance(String id) async {
    final transactions =
        await (select(db.ledgerTransactions)..where(
              (tbl) => tbl.entityType.equals('Supplier') & tbl.refId.equals(id),
            ))
            .get();

    return transactions.fold<double>(0.0, (sum, transaction) {
      return sum + transaction.credit - transaction.debit;
    });
  }

  Stream<int> watchSuppliersCount() {
    return customSelect(
      'SELECT COUNT(*) as count FROM suppliers',
      readsFrom: {suppliers},
    ).map((row) => row.readNullable<int>('count') ?? 0).watchSingle();
  }

  Stream<double> watchTotalSuppliersDues() {
    return customSelect(
      '''SELECT SUM(
        COALESCE(
          (SELECT SUM(credit - debit) 
           FROM ledger_transactions 
           WHERE entity_type = 'Supplier' 
           AND ref_id = suppliers.id), 
          0.0
        )
      ) as total_dues 
      FROM suppliers 
      WHERE status = 'Active' ''',
      readsFrom: {suppliers, db.ledgerTransactions},
    ).map((row) => row.readNullable<double>('total_dues') ?? 0.0).watchSingle();
  }
}
