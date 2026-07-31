import 'package:drift/drift.dart';

import 'supplier_table.dart';

/// Pricing modes for vegetable-market shipments.
abstract final class ShipmentPricingMode {
  static const perUnit = 'per_unit';
  static const lumpSum = 'lump_sum';
  static const commission = 'commission';

  static const all = [perUnit, lumpSum, commission];
}

class VegetableShipments extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get supplierId => text().references(Suppliers, #id)();

  TextColumn get shipmentNumber => text().unique()();

  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();

  /// [ShipmentPricingMode.perUnit] | [ShipmentPricingMode.lumpSum] |
  /// [ShipmentPricingMode.commission]
  TextColumn get pricingMode => text()();

  IntColumn get totalBarnikaCount => integer()();

  /// Active when [pricingMode] is [ShipmentPricingMode.perUnit].
  RealColumn get costPricePerBarnika => real().nullable()();

  /// Active when [pricingMode] is [ShipmentPricingMode.lumpSum].
  RealColumn get lumpSumCost => real().nullable()();

  /// Active when [pricingMode] is [ShipmentPricingMode.commission].
  RealColumn get commissionPercentage => real().nullable()();

  /// Optional container (برنيكة) deposit price.
  RealColumn get containerPrice => real().nullable()();

  RealColumn get totalCost => real()();

  IntColumn get barnikaSoldCount =>
      integer().withDefault(const Constant(0))();

  IntColumn get barnikaRemainingCount => integer()();

  TextColumn get notes => text().nullable()();
}
