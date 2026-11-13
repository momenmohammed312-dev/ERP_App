import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/empty_barnika_tracking_table.dart';

part 'empty_barnika_tracking_dao.g.dart';

@DriftAccessor(tables: [EmptyBarnikaTracking])
class EmptyBarnikaTrackingDao extends DatabaseAccessor<AppDatabase>
    with _$EmptyBarnikaTrackingDaoMixin {
  EmptyBarnikaTrackingDao(super.db);

  Future<EmptyBarnikaTrackingData?> getById(int id) =>
      (select(emptyBarnikaTracking)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<EmptyBarnikaTrackingData>> getAll() =>
      select(emptyBarnikaTracking).get();

  Future<List<EmptyBarnikaTrackingData>> getOutstandingByCustomer(
    String customerId,
  ) =>
      (select(emptyBarnikaTracking)
            ..where(
              (t) =>
                  t.customerId.equals(customerId) &
                  t.status.isNotValue(EmptyBarnikaStatus.returned),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.dateOut)]))
          .get();

  Stream<List<EmptyBarnikaTrackingData>> watchOutstandingByCustomer(
    String customerId,
  ) =>
      (select(emptyBarnikaTracking)
            ..where(
              (t) =>
                  t.customerId.equals(customerId) &
                  t.status.isNotValue(EmptyBarnikaStatus.returned),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.dateOut)]))
          .watch();

  Future<List<EmptyBarnikaTrackingData>> getAllOutstanding() =>
      (select(emptyBarnikaTracking)
            ..where((t) => t.status.isNotValue(EmptyBarnikaStatus.returned))
            ..orderBy([(t) => OrderingTerm.desc(t.dateOut)]))
          .get();

  Stream<List<EmptyBarnikaTrackingData>> watchAllOutstanding() =>
      (select(emptyBarnikaTracking)
            ..where((t) => t.status.isNotValue(EmptyBarnikaStatus.returned))
            ..orderBy([(t) => OrderingTerm.desc(t.dateOut)]))
          .watch();

  Future<int> insertRecord(EmptyBarnikaTrackingCompanion entry) =>
      into(emptyBarnikaTracking).insert(entry);

  Future<List<EmptyBarnikaTrackingData>> getByInvoiceId(int invoiceId) =>
      (select(emptyBarnikaTracking)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .get();

  Future<int> deleteByInvoiceId(int invoiceId) =>
      (delete(emptyBarnikaTracking)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .go();

  /// Total unreturned empty barnikas currently held by [customerId].
  Future<int> getCustomerOutstandingBalance(String customerId) async {
    final rows = await getOutstandingByCustomer(customerId);
    return rows.fold<int>(
      0,
      (sum, r) => sum + (r.quantityOut - r.quantityReturned).clamp(0, 1 << 30),
    );
  }

  /// Applies [quantityReturned] empty barnikas across [customerId]'s
  /// outstanding tracking records oldest-first (FIFO).
  Future<void> recordCustomerReturnFifo({
    required String customerId,
    required int quantityReturned,
    DateTime? dateReturned,
  }) async {
    if (quantityReturned <= 0) {
      throw ArgumentError('quantityReturned must be positive');
    }
    final outstanding = await (select(emptyBarnikaTracking)
          ..where(
            (t) =>
                t.customerId.equals(customerId) &
                t.status.isNotValue(EmptyBarnikaStatus.returned),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.dateOut),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();

    final totalRemaining = outstanding.fold<int>(
      0,
      (sum, r) => sum + (r.quantityOut - r.quantityReturned).clamp(0, 1 << 30),
    );
    if (quantityReturned > totalRemaining) {
      throw ArgumentError(
        'البرانيك المستلمة ($quantityReturned) تتجاوز العهدة المتبقية على العميل ($totalRemaining)',
      );
    }

    var toApply = quantityReturned;
    final resolvedDate = dateReturned ?? DateTime.now();
    for (final rec in outstanding) {
      if (toApply <= 0) break;
      final remaining = (rec.quantityOut - rec.quantityReturned).clamp(0, 1 << 30);
      if (remaining <= 0) continue;
      final apply = toApply <= remaining ? toApply : remaining;
      await recordReturn(
        id: rec.id,
        quantityReturned: apply,
        dateReturned: resolvedDate,
      );
      toApply -= apply;
    }
  }

  Future<void> recordReturn({
    required int id,
    required int quantityReturned,
    DateTime? dateReturned,
  }) async {
    final record = await getById(id);
    if (record == null) {
      throw StateError('Empty barnika record $id not found');
    }

    final newReturned = record.quantityReturned + quantityReturned;
    if (newReturned > record.quantityOut) {
      throw ArgumentError(
        'quantityReturned ($newReturned) exceeds quantityOut (${record.quantityOut})',
      );
    }

    final status = _computeStatus(record.quantityOut, newReturned);

    await (update(emptyBarnikaTracking)..where((t) => t.id.equals(id))).write(
      EmptyBarnikaTrackingCompanion(
        quantityReturned: Value(newReturned),
        dateReturned: Value(dateReturned ?? DateTime.now()),
        status: Value(status),
      ),
    );
  }

  static String _computeStatus(int quantityOut, int quantityReturned) {
    if (quantityReturned <= 0) return EmptyBarnikaStatus.outstanding;
    if (quantityReturned >= quantityOut) return EmptyBarnikaStatus.returned;
    return EmptyBarnikaStatus.partial;
  }
}
