import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../tables/supplier_table.dart';
import '../app_database.dart';

part 'supplier_dao.g.dart';

/// Supplier status values used across the app (mirrors the `status` TEXT
/// column default 'Active'). Verified against `supplier_table.dart` and all
/// writers: only 'Active' / 'Inactive' are ever written.
abstract final class SupplierStatus {
  static const active = 'Active';
  static const inactive = 'Inactive';
}

@DriftAccessor(tables: [Suppliers])
class SupplierDao extends DatabaseAccessor<AppDatabase>
    with _$SupplierDaoMixin {
  SupplierDao(super.db);

  Future<List<Supplier>> getAllSuppliers() => select(suppliers).get();

  Future<Supplier?> getSupplierById(String id) =>
      (select(suppliers)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<List<Supplier>> getActiveSuppliers() => (select(suppliers)
        ..where((tbl) => tbl.status.equals(SupplierStatus.active))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();

  /// Watch only active suppliers, sorted by name (mirrors
  /// [CustomerDao.watchActiveCustomers]).
  Stream<List<Supplier>> watchActiveSuppliers() => (select(suppliers)
        ..where((tbl) => tbl.status.equals(SupplierStatus.active))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  /// Watch only inactive (soft-deleted) suppliers, sorted by name.
  Stream<List<Supplier>> watchInactiveSuppliers() => (select(suppliers)
        ..where((tbl) => tbl.status.equals(SupplierStatus.inactive))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();

  /// Find an active supplier by exact name. Inactive suppliers are ignored
  /// so their names can be reused (mirrors `getActiveCustomerByName`).
  Future<Supplier?> getActiveSupplierByName(String name) {
    return (select(suppliers)
          ..where(
            (t) => t.status.equals(SupplierStatus.active) & t.name.equals(name),
          ))
        .getSingleOrNull();
  }

  Future<Supplier> insertSupplier(SuppliersCompanion supplier) async {
    // Insert guard mirroring the customer active-name check: the suppliers
    // table has no UNIQUE constraint on name, and the add/edit page already
    // shows a search field (search-before-create UX), so rejecting an active
    // duplicate here fits supplier UX and prevents statement confusion.
    // Sync-by-id can still recreate the same row on another device — that
    // path keys on the stable UUID, never on name, so no false positives.
    final name = supplier.name.value;
    if (name.isNotEmpty) {
      final existing = await getActiveSupplierByName(name);
      if (existing != null) {
        throw Exception('المورد موجود بالفعل');
      }
    }
    final id = supplier.id.present ? supplier.id.value : const Uuid().v4();
    final supplierWithId = supplier.copyWith(id: Value(id));
    await into(suppliers).insert(supplierWithId);
    await _enqueueSupplier(id, 'insert');
    return await getSupplierById(id) ??
        (throw Exception('Failed to insert supplier'));
  }

  Future<bool> updateSupplier(SuppliersCompanion supplier) async {
    final result = await update(suppliers).replace(supplier);
    try {
      await _enqueueSupplier(supplier.id.value, 'update');
    } catch (e) {
      debugPrint('Enqueue supplier (update) failed: $e');
    }
    return result;
  }

  /// HARD DELETE — RETIRED. Kept only for signature compatibility: it now
  /// performs a soft delete (sets status='Inactive') instead of removing the
  /// row, so ledger/purchase history is never orphaned. New code MUST call
  /// [deactivateSupplier] directly. Evidence: all UI callers
  /// (`suppliers_widget.dart`, `add_edit_supplier_page.dart`) were switched
  /// to [deactivateSupplier]; no active caller depends on row removal.
  Future<int> deleteSupplier(String id) => deactivateSupplier(id);

  /// Soft-deactivate a supplier. History (ledger + purchases) is preserved
  /// and the row disappears from active lists. Enqueues the change so the
  /// deactivation replicates (see sync rule in [upsertFromRemote]).
  Future<int> deactivateSupplier(String id) async {
    final rows = await (update(suppliers)..where((tbl) => tbl.id.equals(id)))
        .write(
      const SuppliersCompanion(status: Value(SupplierStatus.inactive)),
    );
    await _enqueueSupplier(id, 'update');
    return rows;
  }

  /// LEDGER IS AUTHORITATIVE (B5): delegates to [LedgerDao.getSupplierBalance]
  /// (openingBalance + Σ(credit − debit)). The previous independent fold over
  /// `ledger_transactions` computed the same formula inline — any fix to the
  /// formula now happens once in `ledger_dao.dart` (owned by Agent 4).
  /// Old formula: fold(credit − debit) WITHOUT openingBalance → new delegate:
  /// ledger (WITH openingBalance). Callers see corrected balances.
  Future<double> getSupplierBalance(String id) =>
      db.ledgerDao.getSupplierBalance(id);

  /// Counts only ACTIVE suppliers (mirrors [CustomerDao.watchCustomersCount]).
  /// Previously counted every row including soft-deleted ones.
  Stream<int> watchSuppliersCount() {
    final countExp = suppliers.id.count();
    return (selectOnly(suppliers)
          ..addColumns([countExp])
          ..where(suppliers.status.equals(SupplierStatus.active)))
        .map((row) => row.read(countExp) ?? 0)
        .watchSingle();
  }

  /// LEDGER IS AUTHORITATIVE (B5): total dues across active suppliers.
  /// Delegates the per-supplier math to [LedgerDao.getSupplierBalance] and
  /// only aggregates here (SUM over active suppliers). The previous inline
  /// SQL subquery is retired — same numbers, single formula owner.
  Stream<double> watchTotalSuppliersDues() {
    return (select(suppliers)
          ..where((tbl) => tbl.status.equals(SupplierStatus.active)))
        .watch()
        .asyncMap((list) async {
      double total = 0.0;
      for (final s in list) {
        total += await db.ledgerDao.getSupplierBalance(s.id);
      }
      return total;
    });
  }

  /// Writes a supplier row pulled from Supabase without re-enqueueing it for
  /// push. Stable identity = supplier UUID `id` (same outbox/pull pattern as
  /// customers — see `sync_service.dart`).
  ///
  /// Soft-delete replication rule (same as customers/B1, adapted):
  /// the `suppliers` table has NO `updatedAt` column (checked
  /// `supplier_table.dart`: id/name/phone/address/openingBalance/createdAt/
  /// status), so timestamp ordering is impossible without a schema change.
  /// Rule is therefore monotonic-delete: a remote Inactive/Deleted status is
  /// ALWAYS applied (delete wins unconditionally); a remote Active status
  /// NEVER resurrects a locally Inactive row. Re-activation is a deliberate
  /// local admin action only.
  /// The remote flag is read opportunistically from `is_active`/`status`;
  /// absence means "unknown" → activity untouched, other fields updated.
  /// NO new columns/tables are added here. If timestamp ordering is ever
  /// wanted, the exact DDL is documented in the merge/sync report
  /// (Agent 1 owns `app_database.dart`):
  ///   ALTER TABLE suppliers ADD COLUMN updated_at INTEGER;
  /// plus a matching Supabase `suppliers.is_active` flag for push.
  Future<void> upsertFromRemote(Map<String, dynamic> remoteRow) async {
    final syncId = remoteRow['sync_id'] as String?;
    if (syncId == null || syncId.isEmpty) return;
    final existing = await getSupplierById(syncId);

    final remoteIsActive = _remoteIsActive(remoteRow);
    final companion = SuppliersCompanion(
      id: Value(syncId),
      name: Value(remoteRow['name'] as String? ?? ''),
      phone: Value(remoteRow['phone'] as String?),
      address: Value(remoteRow['address'] as String?),
      openingBalance:
          Value((remoteRow['opening_balance'] as num?)?.toDouble() ?? 0),
      status: Value(
        remoteIsActive == null
            ? (existing?.status ?? SupplierStatus.active)
            : (remoteIsActive
                ? SupplierStatus.active
                : SupplierStatus.inactive),
      ),
    );

    if (existing != null) {
      // Monotonic delete: a locally Inactive row is NEVER resurrected, no
      // matter what the remote flag says — re-activation is a deliberate
      // local admin action only. Other fields still refresh so the row stays
      // current; only the delete stands.
      if (existing.status == SupplierStatus.inactive) {
        final keepDeleted =
            companion.copyWith(status: const Value(SupplierStatus.inactive));
        await (update(suppliers)..where((t) => t.id.equals(syncId)))
            .write(keepDeleted);
        return;
      }
      await (update(suppliers)..where((t) => t.id.equals(syncId)))
          .write(companion);
    } else {
      await into(suppliers).insert(companion);
    }
  }

  bool? _remoteIsActive(Map<String, dynamic> remoteRow) {
    if (remoteRow.containsKey('is_active')) {
      final v = remoteRow['is_active'];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase();
        if (s == 'true' || s == '1') return true;
        if (s == 'false' || s == '0') return false;
      }
    }
    final status = remoteRow['status'] as String?;
    if (status != null) {
      if (status == 'Inactive' || status == 'Deleted') return false;
      if (status == 'Active') return true;
    }
    return null;
  }

  /// Enqueues a supplier for sync. Payload only contains Supabase-style
  /// snake_case columns. Failures are swallowed so the local write wins.
  Future<void> _enqueueSupplier(String syncId, String operation) async {
    try {
      final supplier = await getSupplierById(syncId);
      if (supplier == null || syncId.isEmpty) return;
      await db.syncQueueDao.enqueue(
        tableName: 'suppliers',
        recordSyncId: syncId,
        operation: operation,
        payload: {
          'sync_id': syncId,
          'name': supplier.name,
          'phone': supplier.phone,
          'address': supplier.address,
          'opening_balance': supplier.openingBalance,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('Enqueue supplier ($operation) failed: $e');
    }
  }
}
