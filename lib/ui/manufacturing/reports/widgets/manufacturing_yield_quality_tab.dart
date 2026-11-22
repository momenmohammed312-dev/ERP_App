import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_costing_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_inspections_table.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';

/// Phase 4 Reports Tab: Stage Yields, Quality Inspections, External Operations,
/// and Internal Cost/Margin summary (D-11 / D-07).
///
/// Responsive on Mobile (`< 600px`) and Desktop, and Light/Dark mode aware.
class ManufacturingYieldQualityTab extends StatelessWidget {
  final AppDatabase db;
  final DateTimeRange? range;

  const ManufacturingYieldQualityTab({
    super.key,
    required this.db,
    required this.range,
  });

  Color _successFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D);

  Color _warningFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFF92400E);

  Color _errorFg(BuildContext context) => Theme.of(context).colorScheme.error;

  Future<_YieldQualityReportData> _load() async {
    final start =
        range?.start ?? DateTime.now().subtract(const Duration(days: 30));
    final end = (range?.end ?? DateTime.now()).add(const Duration(days: 1));

    final allOrders = await db.manufacturingOrderDao.getAll();
    final orders = allOrders
        .where(
          (o) =>
              o.createdAt.isAfter(start.subtract(const Duration(days: 1))) &&
              o.createdAt.isBefore(end),
        )
        .toList();

    final breakdowns = <({ManufacturingOrder order, OrderCostBreakdown cost})>[];
    final yields = <({ManufacturingOrder order, StageYieldRecord yieldRec})>[];
    final pendingExt = <({ManufacturingOrder order, ExternalOperationRecord op})>[];

    for (final o in orders) {
      final c = await db.manufacturingCostingDao.computeOrderCost(o.id);
      breakdowns.add((order: o, cost: c));

      final orderYields = await db.stageYieldDao.getForOrder(o.id);
      for (final y in orderYields) {
        yields.add((order: o, yieldRec: y));
      }

      final extOps = await db.externalOperationDao.getForOrder(o.id);
      for (final op in extOps) {
        if ((op.sentQty - op.receivedQty - op.scrapQty) > 0.01) {
          pendingExt.add((order: o, op: op));
        }
      }
    }

    final inspections = await db.manufacturingInspectionDao.getInRange(
      start: start,
      end: end,
    );

    return _YieldQualityReportData(
      breakdowns: breakdowns,
      yields: yields,
      inspections: inspections,
      pendingExternal: pendingExt,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_YieldQualityReportData>(
      future: _load(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('خطأ: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data!;
        final totalActual = data.breakdowns.fold<double>(
          0.0,
          (s, e) => s + e.cost.totalActualCost,
        );
        final totalMargin = data.breakdowns.fold<double>(
          0.0,
          (s, e) => s + e.cost.actualMargin,
        );
        final avgYield = data.yields.isEmpty
            ? 0.0
            : data.yields.fold<double>(
                  0.0,
                  (s, e) => s + e.yieldRec.yieldPercent,
                ) /
                data.yields.length;
        final atVendorQty = data.pendingExternal.fold<double>(
          0.0,
          (s, e) =>
              s + (e.op.sentQty - e.op.receivedQty - e.op.scrapQty),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 600;
            final cardW = isCompact
                ? (constraints.maxWidth - 42) / 2
                : math.max(180.0, (constraints.maxWidth - 62) / 4);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _kpiCard(
                        context,
                        width: cardW,
                        title: 'إجمالي التكلفة الفعلية',
                        value: '${totalActual.toStringAsFixed(2)} ج.م',
                        color: context.primaryColor,
                      ),
                      _kpiCard(
                        context,
                        width: cardW,
                        title: 'صافي الهامش الفعلي',
                        value: '${totalMargin.toStringAsFixed(2)} ج.م',
                        color: totalMargin >= 0
                            ? _successFg(context)
                            : _errorFg(context),
                      ),
                      _kpiCard(
                        context,
                        width: cardW,
                        title: 'متوسط كفاءة المراحل',
                        value: '${avgYield.toStringAsFixed(1)}%',
                        color: MadarColors.info,
                      ),
                      _kpiCard(
                        context,
                        width: cardW,
                        title: 'قطع عند الورش الخارجية',
                        value: atVendorQty.toStringAsFixed(0),
                        color: atVendorQty > 0
                            ? _warningFg(context)
                            : _successFg(context),
                      ),
                    ],
                  ),
                  const Gap(20),
                  _sectionTitle(context, 'ملخص الهوامش والتكاليف للأوامر (${data.breakdowns.length})'),
                  const Gap(8),
                  if (data.breakdowns.isEmpty)
                    _emptyHint(context, 'لا توجد أوامر في الفترة المحددة')
                  else
                    for (final item in data.breakdowns)
                      _tileCard(
                        context,
                        title: item.order.orderNumber,
                        trailing:
                            'الهامش: ${item.cost.actualMargin.toStringAsFixed(2)} ج.م',
                        trailingColor: item.cost.actualMargin >= 0
                            ? _successFg(context)
                            : _errorFg(context),
                        subtitle:
                            'فعلي: ${item.cost.totalActualCost.toStringAsFixed(2)} • مخطط: ${item.cost.plannedCost.toStringAsFixed(2)} • انحراف: ${item.cost.variance.toStringAsFixed(2)}',
                      ),
                  const Gap(20),
                  _sectionTitle(context, 'فحوصات الجودة (D-07) — ${data.inspections.length}'),
                  const Gap(8),
                  if (data.inspections.isEmpty)
                    _emptyHint(context, 'لا توجد فحوصات جودة في الفترة المحددة')
                  else
                    for (final ins in data.inspections)
                      _tileCard(
                        context,
                        title:
                            'أمر #${ins.manufacturingOrderId} • ${InspectionResult.label(ins.result)}',
                        trailing: 'الكمية: ${ins.quantity.toStringAsFixed(0)}',
                        trailingColor: ins.result == InspectionResult.accepted
                            ? _successFg(context)
                            : _warningFg(context),
                        subtitle:
                            'الفاحص: ${ins.inspectedBy}${ins.dispositionNote != null ? ' — ${ins.dispositionNote}' : ''}',
                      ),
                  const Gap(20),
                  _sectionTitle(context, 'معلق لدى الورش الخارجية (${data.pendingExternal.length})'),
                  const Gap(8),
                  if (data.pendingExternal.isEmpty)
                    _emptyHint(context, 'لا توجد كميات معلقة عند الورش الخارجية')
                  else
                    for (final p in data.pendingExternal)
                      _tileCard(
                        context,
                        title: '${p.order.orderNumber} — ${p.op.vendor}',
                        trailing:
                            'متبقي: ${(p.op.sentQty - p.op.receivedQty - p.op.scrapQty).toStringAsFixed(1)}',
                        trailingColor: _warningFg(context),
                        subtitle:
                            'مرسل: ${p.op.sentQty} • مستلم: ${p.op.receivedQty} • هالك: ${p.op.scrapQty}',
                      ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _kpiCard(
    BuildContext context, {
    required double width,
    required String title,
    required String value,
    required Color color,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.textSecondary, fontSize: 11),
            ),
            const Gap(4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
    );
  }

  Widget _emptyHint(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(color: context.textSecondary, fontSize: 12),
    );
  }

  Widget _tileCard(
    BuildContext context, {
    required String title,
    required String trailing,
    required Color trailingColor,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
              const Gap(8),
              Text(
                trailing,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: trailingColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Gap(4),
          Text(
            subtitle,
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _YieldQualityReportData {
  final List<({ManufacturingOrder order, OrderCostBreakdown cost})> breakdowns;
  final List<({ManufacturingOrder order, StageYieldRecord yieldRec})> yields;
  final List<ManufacturingInspection> inspections;
  final List<({ManufacturingOrder order, ExternalOperationRecord op})>
      pendingExternal;

  const _YieldQualityReportData({
    required this.breakdowns,
    required this.yields,
    required this.inspections,
    required this.pendingExternal,
  });
}
