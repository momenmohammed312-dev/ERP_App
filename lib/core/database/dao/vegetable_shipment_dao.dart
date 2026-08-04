import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';

part 'vegetable_shipment_dao.g.dart';

@DriftAccessor(tables: [VegetableShipments])
class VegetableShipmentDao extends DatabaseAccessor<AppDatabase>
    with _$VegetableShipmentDaoMixin {
  VegetableShipmentDao(super.db);

  Future<VegetableShipment?> getById(int id) =>
      (select(vegetableShipments)..where((s) => s.id.equals(id)))
          .getSingleOrNull();

  Future<VegetableShipment?> getByShipmentNumber(String number) =>
      (select(vegetableShipments)
            ..where((s) => s.shipmentNumber.equals(number)))
          .getSingleOrNull();

  Future<List<VegetableShipment>> getAll() => select(vegetableShipments).get();

  /// Open shipments with remaining barnikas, oldest first (FIFO order).
  Future<List<VegetableShipment>> getOpenShipmentsFifo() =>
      (select(vegetableShipments)
            ..where((s) => s.barnikaRemainingCount.isBiggerThanValue(0))
            ..orderBy([(s) => OrderingTerm.asc(s.date)]))
          .get();

  Stream<List<VegetableShipment>> watchAll() =>
      select(vegetableShipments).watch();

  /// إجمالي البرانيك المتبقية بالمخزن عبر كل الشحنات المفتوحة
  /// (barnikaRemainingCount > 0) — مجرد SUM، من غير أي جدول جديد.
  Future<int> getTotalRemainingBarnikas() async {
    final query = selectOnly(vegetableShipments)
      ..addColumns([vegetableShipments.barnikaRemainingCount.sum()])
      ..where(vegetableShipments.barnikaRemainingCount.isBiggerThanValue(0));
    final row = await query.getSingle();
    return row.read(vegetableShipments.barnikaRemainingCount.sum()) ?? 0;
  }

  Future<int> insertShipment(VegetableShipmentsCompanion entry) {
    validatePricingFields(
      pricingMode: entry.pricingMode.value,
      costPricePerBarnika: entry.costPricePerBarnika.present
          ? entry.costPricePerBarnika.value
          : null,
      lumpSumCost:
          entry.lumpSumCost.present ? entry.lumpSumCost.value : null,
      commissionPercentage: entry.commissionPercentage.present
          ? entry.commissionPercentage.value
          : null,
    );

    final total = entry.totalBarnikaCount.value;
    final remaining = entry.barnikaRemainingCount.present
        ? entry.barnikaRemainingCount.value
        : total;

    return into(vegetableShipments).insert(
      entry.copyWith(
        barnikaRemainingCount: Value(remaining),
        barnikaSoldCount: entry.barnikaSoldCount.present
            ? entry.barnikaSoldCount
            : const Value(0),
      ),
    );
  }

  Future<bool> updateShipment(VegetableShipment shipment) =>
      update(vegetableShipments).replace(shipment);

  /// Ensures only pricing-mode-specific cost fields are set.
  static void validatePricingFields({
    required String? pricingMode,
    required double? costPricePerBarnika,
    required double? lumpSumCost,
    required double? commissionPercentage,
  }) {
    if (pricingMode == null || !ShipmentPricingMode.all.contains(pricingMode)) {
      throw ArgumentError(
        'pricingMode must be one of ${ShipmentPricingMode.all}',
      );
    }

    switch (pricingMode) {
      case ShipmentPricingMode.perUnit:
        if (costPricePerBarnika == null) {
          throw ArgumentError(
            'costPricePerBarnika is required for per_unit pricing',
          );
        }
        if (lumpSumCost != null || commissionPercentage != null) {
          throw ArgumentError(
            'lumpSumCost and commissionPercentage must be null for per_unit',
          );
        }
      case ShipmentPricingMode.lumpSum:
        if (lumpSumCost == null) {
          throw ArgumentError(
            'lumpSumCost is required for lump_sum pricing',
          );
        }
        if (costPricePerBarnika != null || commissionPercentage != null) {
          throw ArgumentError(
            'costPricePerBarnika and commissionPercentage must be null for lump_sum',
          );
        }
      case ShipmentPricingMode.commission:
        if (commissionPercentage == null) {
          throw ArgumentError(
            'commissionPercentage is required for commission pricing',
          );
        }
        if (costPricePerBarnika != null || lumpSumCost != null) {
          throw ArgumentError(
            'costPricePerBarnika and lumpSumCost must be null for commission',
          );
        }
    }
  }
}
