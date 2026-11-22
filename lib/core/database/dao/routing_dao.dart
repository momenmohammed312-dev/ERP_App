import 'dart:math' as math;

import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';
import 'package:pos_offline_desktop/core/database/tables/routing_tables.dart';

part 'routing_dao.g.dart';

/// DAO for industry-agnostic Routing Templates, frozen per-order execution copies,
/// parallel branches, rework operations, and §2.4 terminal output counting
/// (FEAT-039 Phase 2).
@DriftAccessor(tables: [
  RoutingTemplates,
  RoutingTemplateNodes,
  ManufacturingReworkRecords,
  ManufacturingOrders,
  ManufacturingStages,
  ManufacturingStageOutputs,
  Products,
])
class RoutingDao extends DatabaseAccessor<AppDatabase> with _$RoutingDaoMixin {
  RoutingDao(super.db);

  // ── Templates CRUD ──

  Future<int> createTemplate({
    required String code,
    required String name,
    int? productId,
    String? notes,
  }) {
    if (code.trim().isEmpty) {
      throw ArgumentError('Routing template code is required');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError('Routing template name is required');
    }
    return into(routingTemplates).insert(
      RoutingTemplatesCompanion.insert(
        code: code.trim(),
        name: name.trim(),
        productId: Value(productId),
        notes: Value(notes),
      ),
    );
  }

  Future<List<RoutingTemplate>> getAllTemplates() =>
      (select(routingTemplates)..orderBy([(t) => OrderingTerm.desc(t.id)]))
          .get();

  Stream<List<RoutingTemplate>> watchAllTemplates() =>
      (select(routingTemplates)..orderBy([(t) => OrderingTerm.desc(t.id)]))
          .watch();

  Future<RoutingTemplate?> getTemplateById(int id) =>
      (select(routingTemplates)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> updateTemplateStatus(int id, String status) async {
    await (update(routingTemplates)..where((t) => t.id.equals(id))).write(
      RoutingTemplatesCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> addTemplateNode({
    required int templateId,
    int? parentNodeId,
    required String name,
    int? stageOrder,
    String operationType = RoutingOperationType.generic,
    String? technique,
    String? parametersJson,
    double defaultLaborRate = 0.0,
    double defaultMachineRate = 0.0,
    bool isTerminal = false,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Routing node name is required');
    }
    if (defaultLaborRate < 0 || defaultMachineRate < 0) {
      throw ArgumentError('Default labor/machine rates must be >= 0');
    }
    int order = stageOrder ?? 1;
    if (stageOrder == null) {
      final existing = await getNodesForTemplate(templateId);
      if (existing.isNotEmpty) {
        order = existing.map((n) => n.stageOrder).reduce(math.max) + 1;
      }
    }
    return into(routingTemplateNodes).insert(
      RoutingTemplateNodesCompanion.insert(
        templateId: templateId,
        parentNodeId: Value(parentNodeId),
        stageOrder: Value(order),
        name: name.trim(),
        operationType: Value(operationType),
        technique: Value(technique),
        parametersJson: Value(parametersJson),
        defaultLaborRate: Value(defaultLaborRate),
        defaultMachineRate: Value(defaultMachineRate),
        isTerminal: Value(isTerminal),
      ),
    );
  }

  Future<List<RoutingTemplateNode>> getNodesForTemplate(int templateId) {
    return (select(routingTemplateNodes)
          ..where((n) => n.templateId.equals(templateId))
          ..orderBy([
            (n) => OrderingTerm.asc(n.stageOrder),
            (n) => OrderingTerm.asc(n.id),
          ]))
        .get();
  }

  Stream<List<RoutingTemplateNode>> watchNodesForTemplate(int templateId) {
    return (select(routingTemplateNodes)
          ..where((n) => n.templateId.equals(templateId))
          ..orderBy([
            (n) => OrderingTerm.asc(n.stageOrder),
            (n) => OrderingTerm.asc(n.id),
          ]))
        .watch();
  }

  Future<void> deleteTemplateNode(int nodeId) async {
    await (delete(routingTemplateNodes)..where((n) => n.id.equals(nodeId)))
        .go();
  }

  // ── Per-Order Copy & Freeze (§3.3) ──

  /// Copies active nodes of [templateId] onto [orderId] as independent
  /// [ManufacturingStages] rows and freezes `routingTemplateId`/`routingCode` on
  /// the order. Editing the template later never alters existing order stages.
  Future<List<int>> applyTemplateToOrder({
    required int templateId,
    required int orderId,
    double? initialInputQuantity,
  }) {
    return transaction(() async {
      final template = await getTemplateById(templateId);
      if (template == null) {
        throw ArgumentError('RoutingTemplate #$templateId not found');
      }
      final order = await (select(manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
      if (order == null) {
        throw ArgumentError('ManufacturingOrder #$orderId not found');
      }

      final nodes = (await getNodesForTemplate(templateId))
          .where((n) => n.status == 'active')
          .toList();
      if (nodes.isEmpty) {
        throw StateError(
          'RoutingTemplate "${template.name}" has no active nodes',
        );
      }

      final existingStages = await (select(manufacturingStages)
            ..where((s) => s.manufacturingOrderId.equals(orderId)))
          .get();
      final baseOrder = existingStages.isEmpty
          ? 0
          : existingStages.map((s) => s.stageOrder).reduce(math.max);

      final now = DateTime.now();
      final nodeToStageId = <int, int>{};
      final createdIds = <int>[];
      final effectiveInput = initialInputQuantity ?? order.plannedQuantity;

      for (final node in nodes) {
        final mappedParent = node.parentNodeId != null
            ? nodeToStageId[node.parentNodeId!]
            : null;
        final stageId = await into(manufacturingStages).insert(
          ManufacturingStagesCompanion.insert(
            manufacturingOrderId: orderId,
            stageName: node.name,
            stageOrder: Value(baseOrder + node.stageOrder),
            status: const Value(ManufacturingStageStatus.pending),
            inputQuantity: Value(effectiveInput),
            routingNodeId: Value(node.id),
            parentStageId: Value(mappedParent),
            operationType: Value(node.operationType),
            technique: Value(node.technique),
            parametersJson: Value(node.parametersJson),
            laborRate: Value(node.defaultLaborRate),
            machineRate: Value(node.defaultMachineRate),
            isTerminal: Value(node.isTerminal),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        nodeToStageId[node.id] = stageId;
        createdIds.add(stageId);
      }

      await (update(manufacturingOrders)..where((o) => o.id.equals(orderId)))
          .write(
        ManufacturingOrdersCompanion(
          routingTemplateId: Value(template.id),
          routingCode: Value(template.code),
          currentStageName: Value(nodes.first.name),
          updatedAt: Value(now),
        ),
      );

      return createdIds;
    });
  }

  // ── Rework (D-06, §3.1) ──

  /// Records rework on [originalStageId], optionally spawning a dedicated
  /// non-terminal rework stage (`status = rework`) so rework outputs never
  /// double-count finished production (§2.4).
  Future<ManufacturingReworkRecord> recordRework({
    required int orderId,
    required int originalStageId,
    required double quantity,
    required String reason,
    String? dispositionNote,
    String? reworkedBy,
    bool createReworkStage = true,
  }) {
    return transaction(() async {
      if (quantity <= 0) {
        throw ArgumentError.value(
          quantity,
          'quantity',
          'Rework quantity must be > 0',
        );
      }
      if (reason.trim().isEmpty) {
        throw ArgumentError.value(reason, 'reason', 'Rework reason is required');
      }

      final order = await (select(manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
      if (order == null) {
        throw ArgumentError('ManufacturingOrder #$orderId not found');
      }

      final origStage = await (select(manufacturingStages)
            ..where((s) => s.id.equals(originalStageId)))
          .getSingleOrNull();
      if (origStage == null || origStage.manufacturingOrderId != orderId) {
        throw ArgumentError(
          'Stage #$originalStageId does not belong to order #$orderId',
        );
      }

      final now = DateTime.now();
      int? reworkStageId;
      if (createReworkStage) {
        reworkStageId = await into(manufacturingStages).insert(
          ManufacturingStagesCompanion.insert(
            manufacturingOrderId: orderId,
            stageName: '${origStage.stageName} (إعادة تشغيل)',
            stageOrder: Value(origStage.stageOrder),
            parentStageId: Value(origStage.id),
            status: const Value(ManufacturingStageStatus.rework),
            inputQuantity: Value(quantity),
            operationType: Value(origStage.operationType),
            technique: Value(origStage.technique),
            laborRate: Value(origStage.laborRate),
            machineRate: Value(origStage.machineRate),
            isTerminal: const Value(false),
            notes: Value(dispositionNote ?? reason.trim()),
            startedAt: Value(now),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }

      final recId = await into(manufacturingReworkRecords).insert(
        ManufacturingReworkRecordsCompanion.insert(
          manufacturingOrderId: orderId,
          originalStageId: originalStageId,
          reworkStageId: Value(reworkStageId),
          quantity: quantity,
          reason: reason.trim(),
          dispositionNote: Value(dispositionNote),
          reworkedBy: Value(reworkedBy),
          reworkedAt: Value(now),
        ),
      );

      return (select(manufacturingReworkRecords)
            ..where((r) => r.id.equals(recId)))
          .getSingle();
    });
  }

  Future<List<ManufacturingReworkRecord>> getReworksForOrder(int orderId) {
    return (select(manufacturingReworkRecords)
          ..where((r) => r.manufacturingOrderId.equals(orderId))
          ..orderBy([(r) => OrderingTerm.desc(r.id)]))
        .get();
  }

  Stream<List<ManufacturingReworkRecord>> watchReworksForOrder(int orderId) {
    return (select(manufacturingReworkRecords)
          ..where((r) => r.manufacturingOrderId.equals(orderId))
          ..orderBy([(r) => OrderingTerm.desc(r.id)]))
        .watch();
  }

  // ── §2.4 Terminal Produced Quantity (No Double Counting) ──

  /// Computes finished produced quantity strictly from terminal stages'
  /// `primary` / `co_product` outputs (`produced - scrap`), excluding
  /// intermediate stages, rework stages, `by_product`, and `waste` (§2.4).
  Future<double> computeTerminalProducedQuantity(int orderId) async {
    final stages = await (select(manufacturingStages)
          ..where((s) => s.manufacturingOrderId.equals(orderId)))
        .get();
    final eligible = stages
        .where(
          (s) =>
              s.status != ManufacturingStageStatus.rework &&
              s.status != ManufacturingStageStatus.cancelled,
        )
        .toList();
    if (eligible.isEmpty) return 0.0;

    var terminalStages = eligible.where((s) => s.isTerminal).toList();
    if (terminalStages.isEmpty) {
      final maxOrder = eligible.map((s) => s.stageOrder).reduce(math.max);
      terminalStages =
          eligible.where((s) => s.stageOrder == maxOrder).toList();
    }

    final terminalIds = terminalStages.map((s) => s.id).toList();
    final outputs = await (select(manufacturingStageOutputs)
          ..where(
            (o) =>
                o.manufacturingOrderId.equals(orderId) &
                o.stageId.isIn(terminalIds) &
                o.disposition.equals('produced') &
                o.outputType.isIn([
                  StageOutputType.primary,
                  StageOutputType.coProduct,
                ]),
          ))
        .get();

    return outputs.fold<double>(
      0.0,
      (sum, o) => sum + math.max(0.0, o.producedQuantity - o.scrapQuantity),
    );
  }
}
