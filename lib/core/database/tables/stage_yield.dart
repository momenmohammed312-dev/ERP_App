import 'package:drift/drift.dart';

import 'manufacturing_orders_table.dart';
import 'manufacturing_stages_table.dart';

/// Stage Yield Record — encoded metric for each completed routing stage:
/// `acceptedOutput / inputQuantity`.
///
/// FEAT-039 Phase 1 D-11: yield is a named, auditable metric —
/// NOT an ad-hoc "efficiency" reading.
@DataClassName('StageYieldRecord')
class StageYieldRecords extends Table {
  @override
  String get tableName => 'stage_yields';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  IntColumn get stageId => integer().references(ManufacturingStages, #id, onDelete: KeyAction.cascade)();

  /// qty that entered the stage (the stage's inputQuantity)
  RealColumn get inputQuantity => real().withDefault(const Constant(0.0))();

  /// accepted output of this stage (excluding scrap of this stage)
  RealColumn get acceptedOutput => real().withDefault(const Constant(0.0))();

  /// yield percent: acceptedOutput / inputQuantity * 100
  RealColumn get yieldPercent => real().withDefault(const Constant(0.0))();

  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();
}
