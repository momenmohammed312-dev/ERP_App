import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/database/tables/stage_yield.dart';

part 'stage_yield_dao.g.dart';

/// DAO for [StageYieldRecord] — D-11's named, auditable Stage Yield metric
/// (FEAT-039 Phase 1): `yieldPercent = acceptedOutput / inputQuantity * 100`.
@DriftAccessor(tables: [
  StageYieldRecords,
  ManufacturingOrders,
  ManufacturingStages,
])
class StageYieldDao extends DatabaseAccessor<AppDatabase>
    with _$StageYieldDaoMixin {
  StageYieldDao(super.db);

  /// Encodes and records the Stage Yield metric of one stage.
  ///
  /// `yieldPercent` is computed at write time (accepted/input × 100, `0.0`
  /// when input is 0) so the number is stored, not recomputed later — it is
  /// an auditable metric, not an ad-hoc efficiency reading (plan §4).
  Future<StageYieldRecord> recordStageYield({
    required int manufacturingOrderId,
    required int stageId,
    required double inputQuantity,
    required double acceptedOutput,
  }) async {
    if (inputQuantity < 0 || acceptedOutput < 0) {
      throw ArgumentError(
        'stage inputQuantity/acceptedOutput must be ≥ 0 '
        '(order #$manufacturingOrderId, stage #$stageId)',
      );
    }
    final id = await into(db.stageYieldRecords).insert(
      StageYieldRecordsCompanion.insert(
        manufacturingOrderId: manufacturingOrderId,
        stageId: stageId,
        inputQuantity: Value(inputQuantity),
        acceptedOutput: Value(acceptedOutput),
        yieldPercent: Value(
          inputQuantity > 0 ? acceptedOutput / inputQuantity * 100 : 0.0,
        ),
      ),
    );
    return (select(db.stageYieldRecords)
          ..where((t) => t.id.equals(id)))
        .getSingle();
  }

  /// All Stage Yield rows of one order (oldest first).
  Future<List<StageYieldRecord>> getForOrder(int orderId) {
    return (select(db.stageYieldRecords)
          ..where((t) => t.manufacturingOrderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// Latest Stage Yield of one stage of the order, if recorded.
  Future<StageYieldRecord?> getByStage(int orderId, int stageId) {
    return (select(db.stageYieldRecords)
          ..where(
            (t) =>
                t.manufacturingOrderId.equals(orderId) &
                t.stageId.equals(stageId),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<List<StageYieldRecord>> watchForOrder(int orderId) {
    return (select(db.stageYieldRecords)
          ..where((t) => t.manufacturingOrderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .watch();
  }
}
