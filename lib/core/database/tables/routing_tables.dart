import 'package:drift/drift.dart';

import 'manufacturing_orders_table.dart';
import 'manufacturing_stages_table.dart';
import 'product_table.dart';

/// Operation types allowed for universal routing nodes (FEAT-039 §3.1).
abstract final class RoutingOperationType {
  static const machining = 'machining';
  static const decoration = 'decoration';
  static const assembly = 'assembly';
  static const finishing = 'finishing';
  static const inspection = 'inspection';
  static const external = 'external';
  static const generic = 'generic';

  static const all = [
    machining,
    decoration,
    assembly,
    finishing,
    inspection,
    external,
    generic,
  ];

  static String label(String type) {
    switch (type) {
      case machining:
        return 'تصنيع / تشغيل';
      case decoration:
        return 'تزيين / طباعة / تطريز';
      case assembly:
        return 'تجميع';
      case finishing:
        return 'تشطيب / تغليف';
      case inspection:
        return 'فحص وجودة';
      case external:
        return 'عمل خارجي (ورشة)';
      default:
        return 'عام';
    }
  }
}

/// Output classifications for §2.4 "Don't double-count finished units".
abstract final class StageOutputType {
  static const primary = 'primary';
  static const coProduct = 'co_product';
  static const byProduct = 'by_product';
  static const waste = 'waste';

  static const all = [primary, coProduct, byProduct, waste];
}

/// Industry-agnostic Routing Template header (FEAT-039 Phase 2 — §3.1).
///
/// Independent of BOM; editing a template never modifies orders that already
/// froze a copy via [ManufacturingOrders.routingTemplateId].
@DataClassName('RoutingTemplate')
class RoutingTemplates extends Table {
  @override
  String get tableName => 'routing_templates';

  IntColumn get id => integer().autoIncrement()();

  /// Unique code, e.g. RT-2026-01
  TextColumn get code => text().unique()();

  TextColumn get name => text().withLength(min: 1, max: 255)();

  /// Optional linked product (null = generic template across products)
  IntColumn? get productId => integer()
      .references(Products, #id, onDelete: KeyAction.setNull)
      .nullable()();

  /// 'active' | 'inactive'
  TextColumn get status => text().withDefault(const Constant('active'))();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Individual routing operation node inside a [RoutingTemplate].
///
/// Supports sequential chains and parallel branches via [parentNodeId] and
/// [stageOrder] (D-06), plus industry-agnostic parameters JSON (§3.1).
@DataClassName('RoutingTemplateNode')
class RoutingTemplateNodes extends Table {
  @override
  String get tableName => 'routing_template_nodes';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get templateId =>
      integer().references(RoutingTemplates, #id, onDelete: KeyAction.cascade)();

  /// Optional parent node id for DAG / parallel branches (no second FK to avoid Drift self-ref name clash)
  IntColumn? get parentNodeId => integer().nullable()();

  IntColumn get stageOrder => integer().withDefault(const Constant(1))();

  TextColumn get name => text().withLength(min: 1, max: 255)();

  /// One of [RoutingOperationType]
  TextColumn get operationType =>
      text().withDefault(const Constant(RoutingOperationType.generic))();

  /// e.g. 'cnc_turning' | 'embroidery' | 'screen_print' | 'heat_transfer' | null
  TextColumn get technique => text().nullable()();

  /// Versioned JSON string with technique parameters
  TextColumn get parametersJson => text().nullable()();

  RealColumn get defaultLaborRate => real().withDefault(const Constant(0.0))();
  RealColumn get defaultMachineRate => real().withDefault(const Constant(0.0))();

  /// Whether this node is a terminal operation whose outputs count toward finished `produced` (§2.4)
  BoolColumn get isTerminal => boolean().withDefault(const Constant(false))();

  /// 'active' | 'inactive'
  TextColumn get status => text().withDefault(const Constant('active'))();
}

/// Rework execution record linking an original stage to a rework operation (§3.1, D-06).
@DataClassName('ManufacturingReworkRecord')
class ManufacturingReworkRecords extends Table {
  @override
  String get tableName => 'manufacturing_rework_records';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  IntColumn get originalStageId =>
      integer().references(ManufacturingStages, #id, onDelete: KeyAction.cascade)();

  /// Optional stage created to perform the rework (nullable integer to keep Drift refs unambiguous)
  IntColumn? get reworkStageId => integer().nullable()();

  RealColumn get quantity => real()();
  TextColumn get reason => text().withLength(min: 1, max: 500)();
  TextColumn get dispositionNote => text().nullable()();
  TextColumn get reworkedBy => text().nullable()();
  DateTimeColumn get reworkedAt => dateTime().withDefault(currentDateAndTime)();
}
