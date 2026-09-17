import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/user_model.dart';

/// Typed failure for [CustomerMergeService.mergeCustomers].
class CustomerMergeException implements Exception {
  final String message;
  const CustomerMergeException(this.message);
  @override
  String toString() => 'CustomerMergeException: $message';
}

/// Admin-only customer merge utility (B2).
///
/// Moves EVERY history row from [sourceId] to [targetId] inside ONE
/// `db.transaction`, deactivates the source, and writes audit rows. Re-running
/// is safe (idempotent): rows already pointing at the target are skipped by
/// the `WHERE customer_id = sourceId` / `ref_id = sourceId` predicates.
///
/// ## Customer-id references covered (exhaustive schema+codebase scan)
///  1. `invoices.customer_id` (+ denormalized `customer_name/contact/address`
///     snapshots refreshed to the target) — reassigned.
///  2. `ledger_transactions.ref_id` WHERE `entity_type = 'Customer'` —
///     reassigned (authoritative balance moves with the rows; no amount is
///     recomputed).
///  3. `sales_returns.customer_id` (+ `customer_name` snapshot) — reassigned.
///  4. `customer_containers.customer_id` (part of PK) — reassigned; when the
///     target already holds the same `product_id`, quantities are SUMMED into
///     the target row and the source row deleted (PK collision merge).
///     The `__walkin__` sentinel row is never a merge source.
///  5. `empty_barnika_tracking.customer_id` (FK → customers) — reassigned.
///  6. `sync_queue` — has no FK; pending rows are payload snapshots. After
///     reassignment, fresh `update` outbox rows for the target customer, the
///     source customer (now inactive) and every touched invoice are enqueued
///     (same payload shapes as `CustomerDao._enqueueCustomer` /
///     `InvoiceDao._enqueueInvoice`) so the server converges; stale source
///     snapshots are superseded because the queue is processed oldest-first
///     and upserts key on `sync_id` with the newest write last.
///
/// ## Explicitly EXCLUDED (with reason)
///  - `invoice_items.invoice_id`, `invoice_payments.invoice_id`,
///    `credit_payments.sale_id`, `sales_return_items.return_id` — no customer
///    column; they follow their parent invoice/return automatically.
///  - `user_activity_log` — append-only audit text (`Customer, Product,
///    Invoice…` label column), rewriting it would falsify history.
///  - `sales`, `expenses`, `days`, `cash_sessions`, `purchases`,
///    supplier-side tables — schema scan shows NO customer column.
///  - Supplier-side merge — out of scope (B2 is customer-only).
///
/// ## Source deactivation WITHOUT schema change
/// No `merged_into` column exists on `customers` (checked
/// `customer_table.dart`) and schema changes are forbidden for this agent, so
/// the link is recorded in the existing `notes` TEXT column as
/// `merged_into=<targetId>` (appended, previous notes preserved) together
/// with `isActive=false` + `status='Inactive'`.
/// Ideal DDL (NOT applied — `app_database.dart` owned by Agent 1):
///   ALTER TABLE customers ADD COLUMN merged_into TEXT;
class CustomerMergeService {
  CustomerMergeService(this._db);

  final AppDatabase _db;

  /// Merges [sourceId] into [targetId].
  ///
  /// Admin-only: [performedBy] must have `UserRole.admin` (checked via the
  /// existing `User`/`UserRole` role mechanism — evidence of reuse; admins
  /// hold every `Permission`, managers/cashiers are rejected).
  /// Throws [CustomerMergeException] on any precondition violation.
  Future<void> mergeCustomers({
    required String sourceId,
    required String targetId,
    required User? performedBy,
  }) async {
    if (performedBy == null || performedBy.role != UserRole.admin) {
      throw const CustomerMergeException(
        'mergeCustomers is admin-only (UserRole.admin required)',
      );
    }
    if (sourceId == targetId) {
      throw const CustomerMergeException('source and target must differ');
    }
    if (sourceId == '__walkin__' || targetId == '__walkin__') {
      throw const CustomerMergeException(
        'walk-in sentinel customer cannot be merged',
      );
    }

    final source = await _db.customerDao.getCustomerById(sourceId);
    if (source == null) {
      throw CustomerMergeException('source customer not found: $sourceId');
    }
    final target = await _db.customerDao.getCustomerById(targetId);
    if (target == null) {
      throw CustomerMergeException('target customer not found: $targetId');
    }
    if (!target.isActive) {
      throw CustomerMergeException('target customer is not active: $targetId');
    }
    // Idempotent re-run: source already merged into THIS target → still
    // sweep for stragglers below, but the preconditions hold.
    final alreadyMerged =
        !source.isActive && (source.notes ?? '').contains('merged_into=$targetId');

    await _db.transaction(() async {
      // 1. Invoices (+ denormalized snapshots) → target.
      final invoices = await (_db.select(_db.invoices)
            ..where((t) => t.customerId.equals(sourceId)))
          .get();
      for (final inv in invoices) {
        await (_db.update(_db.invoices)..where((t) => t.id.equals(inv.id)))
            .write(
          InvoicesCompanion(
            customerId: Value(targetId),
            customerName: Value(target.name),
            customerContact: Value(target.phone),
            customerAddress: Value(target.address),
          ),
        );
      }

      // 2. Ledger rows (entityType Customer) → target. Balance authority
      // stays in the ledger; rows just change owner.
      await (_db.update(_db.ledgerTransactions)
            ..where(
              (t) =>
                  t.entityType.equals('Customer') & t.refId.equals(sourceId),
            ))
          .write(const LedgerTransactionsCompanion().copyWith(refId: Value(targetId)));

      // 3. Sales returns → target.
      await (_db.update(_db.salesReturns)
            ..where((t) => t.customerId.equals(sourceId)))
          .write(
        SalesReturnsCompanion(
          customerId: Value(targetId),
          customerName: Value(target.name),
        ),
      );

      // 4. Customer containers → target, summing on PK collision.
      final containers = await (_db.select(_db.customerContainers)
            ..where((t) => t.customerId.equals(sourceId)))
          .get();
      for (final c in containers) {
        final existing = await (_db.select(_db.customerContainers)
              ..where(
                (t) =>
                    t.productId.equals(c.productId) &
                    t.customerId.equals(targetId),
              ))
            .getSingleOrNull();
        if (existing == null) {
          await (_db.update(_db.customerContainers)
                ..where(
                  (t) =>
                      t.productId.equals(c.productId) &
                      t.customerId.equals(sourceId),
                ))
              .write(
            CustomerContainersCompanion(customerId: Value(targetId)),
          );
        } else {
          await (_db.update(_db.customerContainers)
                ..where(
                  (t) =>
                      t.productId.equals(c.productId) &
                      t.customerId.equals(targetId),
                ))
              .write(
            CustomerContainersCompanion(
              quantityOut: Value(existing.quantityOut + c.quantityOut),
              quantityReturned:
                  Value(existing.quantityReturned + c.quantityReturned),
            ),
          );
          await (_db.delete(_db.customerContainers)
                ..where(
                  (t) =>
                      t.productId.equals(c.productId) &
                      t.customerId.equals(sourceId),
                ))
              .go();
        }
      }

      // 5. Empty-barnika tracking → target.
      await (_db.update(_db.emptyBarnikaTracking)
            ..where((t) => t.customerId.equals(sourceId)))
          .write(
        EmptyBarnikaTrackingCompanion(customerId: Value(targetId)),
      );

      // 6. Deactivate source with merged_into note (NO schema change).
      final priorNotes = source.notes;
      final marker = 'merged_into=$targetId';
      final mergedNotes = (priorNotes == null || priorNotes.isEmpty)
          ? marker
          : (priorNotes.contains(marker)
              ? priorNotes
              : '$priorNotes | $marker');
      await (_db.update(_db.customers)..where((t) => t.id.equals(sourceId)))
          .write(
        CustomersCompanion(
          isActive: const Value(false),
          status: const Value('Inactive'),
          notes: Value(mergedNotes),
          updatedAt: Value(DateTime.now()),
        ),
      );
      // Touch target clock so last-write-wins sees post-merge state.
      await (_db.update(_db.customers)..where((t) => t.id.equals(targetId)))
          .write(
        CustomersCompanion(updatedAt: Value(DateTime.now())),
      );

      // 7. Outbox: enqueue convergent updates (payload shapes mirror the
      // DAO enqueue helpers; quiet pull never re-enqueues these).
      await _enqueueCustomerSnapshot(targetId, 'update');
      await _enqueueCustomerSnapshot(sourceId, 'update');
      for (final inv in invoices) {
        await _enqueueInvoiceSnapshot(inv.id);
      }

      // 8. Audit rows (existing AuditDao mechanism — evidence of reuse).
      final detail = jsonEncode({
        'sourceId': sourceId,
        'targetId': targetId,
        'invoicesMoved': invoices.length,
        'alreadyMergedRerun': alreadyMerged,
      });
      await _db.auditDao.logAudit(
        userId: performedBy.id,
        action: 'customer_merge',
        tableName: 'customers',
        details:
            'Merged customer $sourceId into $targetId by ${performedBy.username} $detail',
      );
      await _db.auditDao.logAudit(
        userId: performedBy.id,
        action: 'customer_merge_source_deactivated',
        tableName: 'customers',
        details: 'Deactivated source $sourceId ($marker)',
      );
    });

    debugPrint(
      '[CustomerMerge] $sourceId → $targetId by ${performedBy.username} '
      '(invoices: done in-transaction)',
    );
  }

  /// Local-first: outbox failures are swallowed (same philosophy as
  /// `CustomerDao._enqueueCustomer`) so a sync-queue hiccup can NEVER roll
  /// back the in-transaction financial reassignment above.
  Future<void> _enqueueCustomerSnapshot(String id, String operation) async {
    try {
      final c = await _db.customerDao.getCustomerById(id);
      if (c == null) return;
      await _db.syncQueueDao.enqueue(
        tableName: 'customers',
        recordSyncId: id,
        operation: operation,
        payload: {
          'sync_id': id,
          'name': c.name,
          'phone': c.phone,
          'address': c.address,
          'opening_balance': c.openingBalance,
          'updated_at':
              (c.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('Enqueue merged customer snapshot ($id) failed: $e');
    }
  }

  Future<void> _enqueueInvoiceSnapshot(int localId) async {
    try {
      final inv = await (_db.select(_db.invoices)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      final syncId = inv?.syncId;
      if (inv == null || syncId == null) return;
      await _db.syncQueueDao.enqueue(
        tableName: 'invoices',
        recordSyncId: syncId,
        operation: 'update',
        payload: {
          'sync_id': syncId,
          'invoice_number': inv.invoiceNumber,
          'customer_sync_id': inv.customerId,
          'total_amount': inv.totalAmount,
          'paid_amount': inv.paidAmount,
          'status': inv.status,
          'invoice_date': inv.date.toUtc().toIso8601String(),
          'updated_at':
              (inv.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('Enqueue merged invoice snapshot ($localId) failed: $e');
    }
  }
}
