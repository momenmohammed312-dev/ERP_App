import 'package:drift/drift.dart';
import 'product_table.dart';

/// Bill of Materials header — recipe for a finished product.
@DataClassName('BillOfMaterial')
class BillOfMaterials extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Which product this recipe produces (must be productType='finished_product' or null)
  IntColumn get finishedProductId => integer().references(Products, #id)();

  /// Optional human label, e.g. BOM-CHAIR-01
  TextColumn get code => text().nullable()();

  /// e.g. "كرسي خشب — قياسي"
  TextColumn get name => text().withLength(min: 1, max: 255)();

  /// How many finished units this recipe produces per batch
  RealColumn get yieldQuantity => real().withDefault(const Constant(1))();

  /// Header-level default waste % applied to all lines unless overridden
  RealColumn get wastePercentage => real().withDefault(const Constant(0))();

  /// 'Active' | 'Inactive' (soft toggle)
  TextColumn get status => text().withDefault(const Constant('Active'))();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// BOM line item — raw material requirement.
@DataClassName('BomItem')
class BomItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get bomId => integer().references(BillOfMaterials, #id, onDelete: KeyAction.cascade)();

  /// Raw material product (productType='raw_material' or any product)
  IntColumn get rawMaterialProductId => integer().references(Products, #id)();

  /// Quantity required per [BillOfMaterials.yieldQuantity] batch.
  /// Stored as REAL so fractional recipes are readable (e.g. 0.2 liter),
  /// but execution rounds to whole base-units (see D.1 Option A).
  RealColumn get quantityRequired => real()();

  /// Snapshot of the raw material's unit at BOM-authoring time
  TextColumn get unit => text().nullable()();

  /// Overrides header waste % for this specific line
  RealColumn get wastePercentageOverride => real().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  TextColumn get notes => text().nullable()();
}
