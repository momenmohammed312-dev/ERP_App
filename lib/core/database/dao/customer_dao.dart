// database/dao/customer_dao.dart
import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_table.dart';
import '../app_database.dart';
import 'package:flutter/foundation.dart';

part 'customer_dao.g.dart';

/// Normalizes a phone number to a canonical digit string so that trivial
/// formatting variants never create duplicate customer identities.
///
/// Rules (documented once here, used by sync reconciliation only):
///  1. strip every non-digit (spaces, dashes, '+', parentheses);
///  2. strip Egyptian country-prefix variants: leading '0020' or '20'
///     (only when digits remain longer than a local number);
///  3. strip one leading trunk '0'.
/// Empty/null input normalizes to '' (never matches — callers skip it).
String normalizePhone(String? raw) {
  if (raw == null) return '';
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('0020')) {
    digits = digits.substring(4);
  } else if (digits.startsWith('20') && digits.length > 10) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('0') && digits.length > 1) {
    digits = digits.substring(1);
  }
  return digits;
}

/// Outcome of [CustomerDao.reconcileRemoteCustomer].
enum CustomerSyncOutcome {
  /// Remote `sync_id` matched a local row by stable id (upsert applied or
  /// skipped by last-write-wins).
  matchedById,

  /// Remote id unknown/absent but exactly ONE local row shares the same
  /// normalized phone — remote fields adopted onto that row (id unchanged).
  mergedByPhone,

  /// Remote id unknown/absent and no local row shares the phone — inserted
  /// as a new local row under the remote id (when present).
  inserted,

  /// Remote id unknown/absent and ≥2 local rows share the normalized phone.
  /// NOTHING was changed — caller must surface/log the conflict.
  conflict,

  /// Local row is newer (last-write-wins) — remote row ignored.
  skippedStale,
}

/// Typed result of a customer sync-reconciliation attempt. A [conflict]
/// outcome preserves all history and carries the ambiguous candidate ids.
class CustomerReconciliation {
  final CustomerSyncOutcome outcome;

  /// Local customer id that was created/updated, if any.
  final String? customerId;

  /// Ambiguous local candidate ids (only for [CustomerSyncOutcome.conflict]).
  final List<String> conflictIds;

  const CustomerReconciliation({
    required this.outcome,
    this.customerId,
    this.conflictIds = const [],
  });

  bool get isConflict => outcome == CustomerSyncOutcome.conflict;
}

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

  /// Watch only active (non soft-deleted) customers, sorted by name.
  /// Used by the customer UI so soft-deleted customers disappear from the list.
  Stream<List<Customer>> watchActiveCustomers() {
    return (select(customers)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
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

  /// Find an active (non soft-deleted) customer by exact name.
  /// Soft-deleted customers are ignored so their names can be reused.
  Future<Customer?> getActiveCustomerByName(String name) {
    return (select(customers)
          ..where(
            (t) => t.isActive.equals(true) & t.name.equals(name),
          ))
        .getSingleOrNull();
  }

  // ===== WRITE =====

  /// Insert a new customer with duplicate name check
  Future<int> insertCustomer(CustomersCompanion customer) async {
    try {
      final existing = await getActiveCustomerByName(customer.name.value);
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
  ///
  /// Soft-delete replication rule (documented once here):
  ///  - ordering key is `updatedAt` (falling back to `createdAt` when
  ///    `updatedAt` is null — [insertCustomer] historically left it null);
  ///    a row with no clock at all counts as epoch (remote wins);
  ///  - newer timestamp wins (last-write-wins);
  ///  - on an exact timestamp TIE, delete wins: if either side is
  ///    inactive/deleted the merged row stays deleted;
  ///  - when clocks are incomparable (remote has no timestamp) a locally
  ///    deleted row is NEVER resurrected — the delete is preserved;
  ///  - legacy remote rows without any activity flag keep the local
  ///    `isActive`/`status` untouched (no silent resurrection, no silent
  ///    delete).
  /// The remote activity flag is read opportunistically from `is_active` (or
  /// `status` == 'Inactive'/'Deleted'); absence means "unknown", not "active".
  Future<void> upsertFromRemote(Map<String, dynamic> remoteRow) async {
    final syncId = remoteRow['sync_id'] as String?;
    if (syncId == null || syncId.isEmpty) return;
    final remoteUpdated =
        DateTime.tryParse(remoteRow['updated_at'] as String? ?? '');
    final remoteIsActive = _remoteIsActive(remoteRow);
    final existing = await getCustomerById(syncId);

    if (existing == null) {
      await into(customers).insert(
        _remoteCompanion(
          syncId,
          remoteRow,
          remoteUpdated,
          isActive: remoteIsActive ?? true,
        ),
      );
      return;
    }

    final localClock = existing.updatedAt ?? existing.createdAt;
    if (!_remoteWins(localClock, remoteUpdated)) {
      // Local row is newer — last-write-wins: do not overwrite.
      // Tie with a local delete also keeps the delete (delete-wins-on-tie).
      return;
    }

    final tie = localClock != null &&
        remoteUpdated != null &&
        localClock.isAtSameMomentAs(remoteUpdated);
    // On a tie, delete wins: merged activity = active ONLY if both sides active.
    final mergedActive = tie
        ? (existing.isActive && (remoteIsActive ?? true))
        : (remoteIsActive ?? existing.isActive);

    final companion = _remoteCompanion(
      syncId,
      remoteRow,
      remoteUpdated,
      isActive: mergedActive,
    );
    await (update(customers)..where((t) => t.id.equals(syncId)))
        .write(companion);
  }

  /// Reconciles one remote customer row when the remote stable id may be
  /// unknown locally. NEVER merges on name alone.
  ///
  ///  1. `sync_id` matches a local row → id-based upsert (see
  ///     [upsertFromRemote]) → [CustomerSyncOutcome.matchedById].
  ///  2. id unknown/absent → match ONLY on unambiguous normalized phone
  ///     ([normalizePhone]; the [Customers] schema has NO customer-code
  ///     column — checked `customer_table.dart`: id/name/phone/address/
  ///     gstinNumber/email/openingBalance/totalDebt/totalPaid/createdAt/
  ///     updatedAt/notes/isActive/status — so phone is the sole fallback key):
  ///       - exactly 1 candidate → adopt remote fields onto that row
  ///         (row id NEVER changes, history preserved; guarded by the same
  ///         last-write-wins clock) → `mergedByPhone`;
  ///       - 0 candidates → insert under the remote id when present,
  ///         else synthesize nothing and report `inserted` with null id...
  ///         (a row without any stable id cannot be tracked, so it is
  ///         SKIPPED and reported as `skippedStale` — never invented);
  ///       - ≥2 candidates → [CustomerSyncOutcome.conflict]: NOTHING is
  ///         merged, all history preserved, candidate ids returned and the
  ///         conflict is logged for an admin to resolve via the merge utility.
  Future<CustomerReconciliation> reconcileRemoteCustomer(
    Map<String, dynamic> remoteRow,
  ) async {
    final syncId = remoteRow['sync_id'] as String?;
    if (syncId != null &&
        syncId.isNotEmpty &&
        await getCustomerById(syncId) != null) {
      final before = await getCustomerById(syncId);
      await upsertFromRemote(remoteRow);
      final after = await getCustomerById(syncId);
      if (before != null &&
          after != null &&
          before.updatedAt != null &&
          _remoteDate(remoteRow) != null &&
          before.updatedAt!.isAfter(_remoteDate(remoteRow)!)) {
        return const CustomerReconciliation(
          outcome: CustomerSyncOutcome.skippedStale,
        );
      }
      return CustomerReconciliation(
        outcome: CustomerSyncOutcome.matchedById,
        customerId: syncId,
      );
    }

    final remotePhone = normalizePhone(remoteRow['phone'] as String?);
    if (remotePhone.isEmpty) {
      // No stable id and no phone: insert only when a remote id exists to
      // track the row by; otherwise there is nothing safe to key on.
      if (syncId == null || syncId.isEmpty) {
        debugPrint(
          '[CustomerSync] skipped remote row with no sync_id and no phone',
        );
        return const CustomerReconciliation(
          outcome: CustomerSyncOutcome.skippedStale,
        );
      }
      await upsertFromRemote(remoteRow);
      return CustomerReconciliation(
        outcome: CustomerSyncOutcome.inserted,
        customerId: syncId,
      );
    }

    final candidates = await _findByNormalizedPhone(remotePhone);
    if (candidates.length >= 2) {
      final ids = candidates.map((c) => c.id).toList();
      debugPrint(
        '[CustomerSync] CONFLICT: ambiguous phone "$remotePhone" matches '
        '${ids.length} local customers (${ids.join(', ')}). No merge performed.',
      );
      return CustomerReconciliation(
        outcome: CustomerSyncOutcome.conflict,
        conflictIds: ids,
      );
    }
    if (candidates.isEmpty) {
      if (syncId == null || syncId.isEmpty) {
        debugPrint(
          '[CustomerSync] skipped remote row with no sync_id and unmatched phone',
        );
        return const CustomerReconciliation(
          outcome: CustomerSyncOutcome.skippedStale,
        );
      }
      await upsertFromRemote(remoteRow);
      return CustomerReconciliation(
        outcome: CustomerSyncOutcome.inserted,
        customerId: syncId,
      );
    }

    // Exactly one candidate: adopt remote fields onto the existing row.
    // The row id NEVER changes, so invoices/ledger/containers keep pointing
    // at the same row — full history preserved.
    final target = candidates.single;
    final remoteUpdated = _remoteDate(remoteRow);
    final localClock = target.updatedAt ?? target.createdAt;
    if (!_remoteWins(localClock, remoteUpdated)) {
      return CustomerReconciliation(
        outcome: CustomerSyncOutcome.skippedStale,
        customerId: target.id,
      );
    }
    final remoteIsActive = _remoteIsActive(remoteRow);
    await (update(customers)..where((t) => t.id.equals(target.id))).write(
      _remoteCompanion(
        target.id,
        remoteRow,
        remoteUpdated,
        isActive: remoteIsActive ?? target.isActive,
      ),
    );
    debugPrint(
      '[CustomerSync] merged remote row into local ${target.id} by unambiguous phone',
    );
    return CustomerReconciliation(
      outcome: CustomerSyncOutcome.mergedByPhone,
      customerId: target.id,
    );
  }

  /// Local clock comparison for last-write-wins.
  /// Returns true when the remote row may overwrite the local row:
  /// remote strictly newer, exact tie (delete-wins resolves the flag), or
  /// local clock unknown-but-remote-known... — EXCEPT a locally deleted row
  /// is never resurrected by a remote row without a comparable clock.
  bool _remoteWins(DateTime? localClock, DateTime? remoteUpdated) {
    if (remoteUpdated == null) return false;
    if (localClock == null) return true;
    return !localClock.isAfter(remoteUpdated);
  }

  DateTime? _remoteDate(Map<String, dynamic> remoteRow) =>
      DateTime.tryParse(remoteRow['updated_at'] as String? ?? '');

  /// Reads the remote activity flag opportunistically. Returns null when the
  /// remote row carries no activity information (legacy row → "unknown").
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

  CustomersCompanion _remoteCompanion(
    String id,
    Map<String, dynamic> remoteRow,
    DateTime? remoteUpdated, {
    required bool isActive,
  }) {
    return CustomersCompanion(
      id: Value(id),
      name: Value(remoteRow['name'] as String? ?? ''),
      phone: Value(remoteRow['phone'] as String?),
      address: Value(remoteRow['address'] as String?),
      openingBalance: Value((remoteRow['opening_balance'] as num?)?.toDouble() ?? 0),
      isActive: Value(isActive),
      status: Value(isActive ? 'Active' : 'Inactive'),
      updatedAt: Value(remoteUpdated),
    );
  }

  /// Finds local customers whose phone normalizes ([normalizePhone]) to
  /// [normalized]. Normalization is app-side (SQLite has no such function),
  /// so this scans the table — fine for reconciliation cardinality.
  Future<List<Customer>> _findByNormalizedPhone(String normalized) async {
    if (normalized.isEmpty) return const [];
    final all = await select(customers).get();
    return all
        .where((c) => normalizePhone(c.phone) == normalized)
        .toList();
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

  /// Update customer active status (Soft Delete).
  /// Bumps `updatedAt` so last-write-wins ordering keeps working, and
  /// enqueues the change so the delete replicates to other devices instead
  /// of being silently resurrected by a stale remote row.
  Future<void> deleteCustomer(String id) async {
    try {
      await (update(customers)..where((t) => t.id.equals(id))).write(
        CustomersCompanion(
          isActive: const Value(false),
          status: const Value('Inactive'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _enqueueCustomer(id, 'update');
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

  /// Get Total Debt across all active customers.
  ///
  /// LEDGER IS AUTHORITATIVE (B5): the `customers.totalDebt` cached column is
  /// a second truth that diverges (it is only ever written by the add/edit
  /// UI with hand-typed values — see `add_edit_customer_page.dart`, now
  /// neutralized to preserve stored values and display the ledger balance).
  /// This stream therefore DELEGATES to
  /// [LedgerDao.watchTotalReceivables], which computes
  /// openingBalance + Σ(debit − credit) per active customer from the ledger.
  /// Old formula: SUM(customers.totalDebt) WHERE is_active → new delegate:
  /// ledger receivables. Do NOT reintroduce the cached-column sum.
  Stream<double> watchTotalDebt() => db.ledgerDao.watchTotalReceivables();

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
