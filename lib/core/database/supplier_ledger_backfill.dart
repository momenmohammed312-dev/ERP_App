import 'package:drift/drift.dart';
import 'dart:developer';

import 'app_database.dart';

/// One-time repair for supplier purchases saved before the ledger pair
/// became mandatory (cash purchases wrote no supplier ledger rows at all,
/// old credit purchases wrote only a single due row).
///
/// For every purchase WITHOUT a `${invoiceNumber}_ledger` due row, posts the
/// standard pair via [LedgerDao.recordSupplierPurchase]. An old-style single
/// due row is completed with its payment leg ONLY when amounts reconcile
/// (`due.credit == total - paid`); anything else is left untouched and
/// logged. Guarded by a `_migration_log` marker so it runs exactly once —
/// and row-level try/catch means one bad purchase can never brick startup.
class SupplierLedgerBackfill {
  static const int _version = 56;
  static const String _step = 'supplier_ledger_backfill';
  static const double _eps = 0.01;

  static Future<void> run(AppDatabase db) async {
    try {
      if (await _alreadyCompleted(db)) return;

      int created = 0;
      int skipped = 0;

      List<Purchase> purchases;
      try {
        purchases = await db.select(db.purchases).get();
      } catch (e) {
        log('SupplierLedgerBackfill: purchases unreadable, skipping: $e');
        return;
      }

      for (final p in purchases) {
        if (p.isDeleted) continue;
        if (p.status == 'voided' || p.status == 'cancelled') continue;
        final supplierId = p.supplierId;
        if (supplierId == null || supplierId.isEmpty) continue;
        try {
          final result = await _repairOne(db, p, supplierId);
          if (result) {
            created++;
          } else {
            skipped++;
          }
        } catch (e) {
          skipped++;
          log('SupplierLedgerBackfill: purchase ${p.id} skipped: $e');
        }
      }

      try {
        await db.customStatement(
          'INSERT INTO _migration_log (version, step, status, error) VALUES (?, ?, ?, ?)',
          [
            _version,
            _step,
            'completed',
            'created=$created skipped=$skipped',
          ],
        );
      } catch (_) {}
      log('SupplierLedgerBackfill done: created=$created skipped=$skipped');
    } catch (e) {
      log('SupplierLedgerBackfill failed (non-fatal): $e');
    }
  }

  /// Returns true when rows were created.
  static Future<bool> _repairOne(
    AppDatabase db,
    Purchase p,
    String supplierId,
  ) async {
    final dueId = '${p.invoiceNumber}_ledger';
    final payId = '${p.invoiceNumber}_ledger_pay';
    final due = await db.ledgerDao.getTransactionById(dueId);
    final pay = await db.ledgerDao.getTransactionById(payId);

    if (due != null && pay != null) return false; // already paired
    if (due == null && pay != null) {
      log('SupplierLedgerBackfill: orphan pay leg for ${p.id}, left alone');
      return false;
    }
    if (due != null) {
      // Old-style single due row: complete the pair only on exact reconcile.
      final expectedRemaining = p.totalAmount - p.paidAmount;
      if (p.paidAmount > 0 &&
          (due.credit - expectedRemaining).abs() <= _eps) {
        await db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: payId,
            entityType: 'Supplier',
            refId: supplierId,
            date: p.purchaseDate,
            description: 'سداد ${p.invoiceNumber}',
            debit: Value(p.paidAmount),
            credit: const Value(0.0),
            origin: 'payment',
            paymentMethod: const Value('cash'),
          ),
        );
        return true;
      }
      log('SupplierLedgerBackfill: due row for ${p.id} does not reconcile, '
          'left alone');
      return false;
    }
    await db.ledgerDao.recordSupplierPurchase(
      supplierId: supplierId,
      invoiceNumber: p.invoiceNumber,
      total: p.totalAmount,
      paid: p.paidAmount,
      date: p.purchaseDate,
    );
    return true;
  }

  static Future<bool> _alreadyCompleted(AppDatabase db) async {
    try {
      final row = await db
          .customSelect(
            'SELECT status FROM _migration_log WHERE version = ? AND step = ? '
            'ORDER BY id DESC LIMIT 1',
            variables: [
              Variable.withInt(_version),
              Variable.withString(_step),
            ],
          )
          .getSingleOrNull();
      return row != null && row.read<String>('status') == 'completed';
    } catch (_) {
      return false;
    }
  }
}
