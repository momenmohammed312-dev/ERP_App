import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

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

  /// Identity normalization shared by UI guards and import reconciliation.
  /// Names: trimmed, inner whitespace collapsed, case-insensitive.
  /// Phones: digits only (strips spaces, dashes, leading trunk/plus).
  /// Empty values never match anything.
  static String normalizeSupplierName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static String normalizeSupplierPhone(String? phone) {
    if (phone == null) return '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.replaceFirst(RegExp(r'^0+'), '');
  }

  /// Finds existing suppliers that collide with a candidate identity.
  /// Match rule (conservative, no auto-merge anywhere):
  /// - same normalized name AND
  /// - (both phones empty OR equal normalized phones).
  /// Pass [excludeId] when editing so a row never conflicts with itself.
  /// Returns every colliding row; callers must surface the conflict and let
  /// a human decide (use existing vs. edit) — never merge silently.
  Future<List<Supplier>> findDuplicateSuppliers({
    required String name,
    String? phone,
    String? excludeId,
  }) async {
    final wantName = normalizeSupplierName(name);
    if (wantName.isEmpty) return const [];
    final wantPhone = normalizeSupplierPhone(phone);
    final rows = await (select(suppliers)
          ..where((tbl) => excludeId == null
              ? const Constant(true)
              : tbl.id.isNotIn([excludeId])))
        .get();
    return rows.where((s) {
      if (normalizeSupplierName(s.name) != wantName) return false;
      final havePhone = normalizeSupplierPhone(s.phone);
      if (wantPhone.isEmpty || havePhone.isEmpty) return true;
      return wantPhone == havePhone;
    }).toList();
  }

  /// Stream of suppliers for the list UI. 'all' | 'active' | 'inactive'.
  /// Debt filtering stays with the balance-aware widgets (needs ledger).
  Stream<List<Supplier>> watchSuppliersByStatus(String filter) {
    final query = select(suppliers)
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    switch (filter) {
      case 'inactive':
        query.where((t) => t.status.equals('Inactive'));
      case 'all':
        break;
      case 'active':
      default:
        query.where((t) => t.status.equals('Active'));
    }
    return query.watch();
  }

  /// Suppliers (active only) that currently carry a non-zero ledger balance.
  /// Raw HAVING query: drift's joined-select API in this version exposes no
  /// `having`, so the debt filter lives in SQL next to its sibling
  /// aggregate in [watchTotalSuppliersDues].
  Stream<List<Supplier>> watchSuppliersWithDebt() {
    final query = customSelect(
      'SELECT s.* FROM suppliers s '
      'LEFT JOIN ledger_transactions l ON l.ref_id = s.id AND l.entity_type = \'Supplier\' '
      'WHERE s.status = \'Active\' '
      'GROUP BY s.id '
      'HAVING ABS(s.opening_balance + SUM(COALESCE(l.credit, 0) - COALESCE(l.debit, 0))) > 0.01 '
      'ORDER BY s.name',
      readsFrom: {suppliers, db.ledgerTransactions},
    );
    return query.map((row) => suppliers.map(row.data)).watch();
  }

  Future<Supplier> insertSupplier(SuppliersCompanion supplier) async {
    final id = const Uuid().v4();
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
      "SELECT COUNT(*) as count FROM suppliers WHERE status = 'Active'",
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
