// database/dao/customer_dao.dart
import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_table.dart';
import '../app_database.dart';
import 'package:flutter/foundation.dart';

part 'customer_dao.g.dart';

@DriftAccessor(tables: [Customers])
class CustomerDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerDaoMixin {
  CustomerDao(super.db);

  // ===== READ =====

  /// Get all active customers sorted by name
  Future<List<Customer>> getAllActiveCustomers() {
    return (select(customers)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  /// Watch all customers (Legacy method kept for compatibility, updated to sort)
  Stream<List<Customer>> watchAllCustomers() {
    return (select(
      customers,
    )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  }

  /// Get all customers (Legacy method)
  Future<List<Customer>> getAllCustomers() => select(customers).get();

  /// Get customer by ID
  Future<Customer?> getCustomerById(String id) {
    return (select(customers)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Search customers by name or phone
  Future<List<Customer>> searchCustomers(String query) {
    final searchTerm = '%${query.toLowerCase()}%';
    return (select(customers)..where(
          (t) =>
              t.isActive.equals(true) &
              (t.name.lower().like(searchTerm) | t.phone.like(searchTerm)),
        ))
        .get();
  }

  // ===== WRITE =====

  /// Insert a new customer with duplicate name check
  Future<int> insertCustomer(CustomersCompanion customer) async {
    try {
      // Check for duplicate name
      final existing = await (select(
        customers,
      )..where((t) => t.name.equals(customer.name.value))).getSingleOrNull();

      if (existing != null) {
        throw Exception('العميل موجود بالفعل');
      }

      // Insert customer directly - database will handle createdAt with default value
      await into(customers).insert(customer);
      // Queue the new customer for sync. Customers.id IS the UUID.
      await _enqueueCustomer(customer.id.value, 'insert');
      // Drift insert returns rowId (int) for auto-increment, or 0/void for custom primary keys?
      // Since ID is String (UUID) and provided in companion, standard insert returns success indication if rowid usage is standard.
      // But for customized primary key tables, better to treat as void or just return success.
      return 1;
    } catch (e) {
      debugPrint('❌ Error inserting customer: $e');
      rethrow;
    }
  }

  /// Update an existing customer
  Future<bool> updateCustomer(CustomersCompanion customer) async {
    try {
      // Update customer; bump updatedAt for sync. createdAt is left untouched
      // to avoid datatype issues on the legacy timestamp column.
      final updated = customer.copyWith(
        createdAt: const Value.absent(),
        updatedAt: Value(DateTime.now()),
      );

      // We need to match by ID. The companion should have the ID set.
      // If companion doesn't rely on 'id' column for where clause automatically in replace, we might need explicit where.
      // 'replace' usually uses the primary key from the object.
      // However, CustomersCompanion might not hold the primary key value in a way replace uses if it's not a data class.
      // Let's safe-guard by using update(..).replace(...) which relies on the primary key being present.

      final result = await update(customers).replace(updated);
      // Queue the change for sync.
      await _enqueueCustomer(customer.id.value, 'update');
      debugPrint('✅ Customer updated');
      return result;
    } catch (e) {
      debugPrint('❌ Error updating customer: $e');
      rethrow;
    }
  }

  /// Writes a customer row pulled from Supabase without re-enqueueing it for
  /// push. `Customers.id` IS the UUID, so the remote `sync_id` maps directly to
  /// the local `id` (there is no separate local integer id on this table).
  /// Looks up the existing row by `id` first: if found, updates it only when
  /// the remote `updatedAt` is newer than the local one (last-write-wins); if
  /// not found, inserts a new local row with the same `id`.
  Future<void> upsertFromRemote(Map<String, dynamic> remoteRow) async {
    final syncId = remoteRow['sync_id'] as String?;
    if (syncId == null || syncId.isEmpty) return;
    final remoteUpdated =
        DateTime.tryParse(remoteRow['updated_at'] as String? ?? '');
    final existing = await getCustomerById(syncId);

    if (existing != null &&
        existing.updatedAt != null &&
        remoteUpdated != null &&
        existing.updatedAt!.isAfter(remoteUpdated)) {
      // Local row is newer — last-write-wins: do not overwrite.
      return;
    }

    final companion = CustomersCompanion(
      id: Value(syncId),
      name: Value(remoteRow['name'] as String? ?? ''),
      phone: Value(remoteRow['phone'] as String?),
      address: Value(remoteRow['address'] as String?),
      openingBalance: Value((remoteRow['opening_balance'] as num?)?.toDouble() ?? 0),
      updatedAt: Value(remoteUpdated),
    );

    if (existing != null) {
      await (update(customers)..where((t) => t.id.equals(syncId)))
          .write(companion);
    } else {
      await into(customers).insert(companion);
    }
  }

  /// Enqueues a customer for sync. Payload only contains Supabase columns
  /// (snake_case). Failures are swallowed so the local write always wins.
  Future<void> _enqueueCustomer(String syncId, String operation) async {
    try {
      final customer = await getCustomerById(syncId);
      if (customer == null || syncId.isEmpty) return;
      await db.syncQueueDao.enqueue(
        tableName: 'customers',
        recordSyncId: syncId,
        operation: operation,
        payload: {
          'sync_id': syncId,
          'name': customer.name,
          'phone': customer.phone,
          'address': customer.address,
          'opening_balance': customer.openingBalance,
          'updated_at': (customer.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('Enqueue customer ($operation) failed: $e');
    }
  }

  /// Update customer using data class (Legacy compatibility wrapper)
  Future<bool> updateCustomerByData(Customer customer) async {
    try {
      final result = await update(customers).replace(customer);
      return result;
    } catch (e) {
      rethrow;
    }
  }

  /// Update customer active status (Soft Delete)
  Future<void> deleteCustomer(String id) async {
    try {
      await (update(customers)..where((t) => t.id.equals(id))).write(
        CustomersCompanion(isActive: const Value(false)),
      );
      debugPrint('✅ Customer soft deleted - ID: $id');
    } catch (e) {
      debugPrint('❌ Error deleting customer: $e');
      rethrow;
    }
  }

  // Compatibility with existing code calling deleteCustomer with Insertable
  Future<int> deleteCustomerLegacy(Insertable<Customer> customer) =>
      delete(customers).delete(customer);

  // ===== STATISTICS =====

  /// Get total active customer count
  Stream<int> watchCustomersCount() {
    final countExp = customers.id.count();
    return (selectOnly(customers)
          ..addColumns([countExp])
          ..where(customers.isActive.equals(true)))
        .map((row) => row.read(countExp) ?? 0)
        .watchSingle();
  }

  /// Get Total Debt across all active customers
  Stream<double> watchTotalDebt() {
    // Determine which column tracks debt.
    // Schema now has `totalDebt` column.
    // Ideally this column is updated whenever transactions happen.
    // If we rely on calculation from Ledger for accuracy, we should use that.
    // But per user request we added `totalDebt` column. We will sum that.

    final totalDebtExp = customers.totalDebt.sum();

    return (selectOnly(customers)
          ..addColumns([totalDebtExp])
          ..where(customers.isActive.equals(true)))
        .map((row) => row.read(totalDebtExp) ?? 0.0)
        .watchSingle();
  }

  /// Get total active customer count (non-stream version)
  Future<int> getTotalCustomerCount() async {
    final countExp = customers.id.count();
    final result =
        await (selectOnly(customers)
              ..addColumns([countExp])
              ..where(customers.isActive.equals(true)))
            .getSingle();
    return result.read(countExp) ?? 0;
  }

  /// Get customers with balance information
  Future<List<Customer>> getCustomersWithBalance() async {
    return (select(customers)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }
}
