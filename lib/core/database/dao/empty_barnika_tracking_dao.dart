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
