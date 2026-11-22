import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/reconciliation_dao.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';

/// Responsive, Light/Dark-aware reconciliation card for a manufacturing order
/// (FEAT-039 Phase 1 Batch 3).
///
/// Displays:
/// 1. Order & custody KPIs (including `productionCompletedAt` when present).
/// 2. Custody equation violation alerts (D-02).
/// 3. Per-material custody reconciliation (`Issued / Consumed / ReturnedExcess / Remaining`)
///    with an action to return unused order material back into customer custody (`return_excess`).
/// 4. Analytical consumption log (`ConsumptionRecords`) linked to stock/custody movements.
/// 5. Current customer custody balances with an action to physically return excess material
///    back to the customer (`return_custody`).
class MoReconciliationSection extends StatelessWidget {
  final AppDatabase db;
  final ManufacturingOrder order;
  final Customer? customer;
  final double deliveredQty;
  final List<CustomerStockMovement> orderMovements;
  final List<CustomerStockBalance> customerBalances;
  final Set<int> orderBalanceIds;
  final Map<int, String> balanceProductNames;
  final ReconciliationSummary? reconciliationSummary;
  final List<String> custodyViolations;
  final List<ConsumptionRecord> consumptionRecords;
  final VoidCallback onDataChanged;

  const MoReconciliationSection({
    super.key,
    required this.db,
    required this.order,
    required this.customer,
    required this.deliveredQty,
    required this.orderMovements,
    required this.customerBalances,
    required this.orderBalanceIds,
    required this.balanceProductNames,
    required this.reconciliationSummary,
    required this.custodyViolations,
    required this.consumptionRecords,
    required this.onDataChanged,
  });

  String _fmtQty(double v) {
    if ((v - v.roundToDouble()).abs() < 0.0001) {
      return v.round().toString();
    }
    return v.toStringAsFixed(2);
  }

  Color _successFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D);

  Color _warningFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFF92400E);

  Color _errorFg(BuildContext context) => Theme.of(context).colorScheme.error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // FEAT-009: prefer order-scoped balances when the order has touched custody.
    final linkedBalances = customerBalances
        .where((b) => orderBalanceIds.contains(b.productId))
        .toList();
    final scoped = linkedBalances.isNotEmpty;
    final visibleBalances = scoped ? linkedBalances : customerBalances;

    double totalIssued = 0.0;
    for (final m in orderMovements) {
      if (m.movementType == 'issued_to_order' ||
          m.movementType == 'manufacturing_consumption') {
        totalIssued += m.quantity.abs();
      }
    }

    double totalOnHand = 0.0;
    for (final b in customerBalances) {
      totalOnHand += b.quantityOnHand;
    }

    final custodyLines =
        reconciliationSummary?.custody.values.toList() ?? const <CustodyLine>[];
    final hasViolations = custodyViolations.isNotEmpty;

    return Card(
      elevation: 2,
      color: context.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 600;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, theme, custodyLines.isNotEmpty, hasViolations),
                const Divider(height: 24),
                _buildKpis(
                  context,
                  constraints.maxWidth,
                  isCompact,
                  totalIssued,
                  totalOnHand,
                ),
                if (hasViolations) ...[
                  const Gap(16),
                  _buildViolationsBanner(context, colorScheme),
                ],
                const Gap(20),
                _buildCustodyReconciliationBlock(
                  context,
                  theme,
                  isCompact,
                  custodyLines,
                ),
                const Gap(20),
                _buildConsumptionLogBlock(context, theme, isCompact),
                if (customerBalances.isNotEmpty) ...[
                  const Gap(20),
                  _buildBalancesBlock(
                    context,
                    theme,
                    isCompact,
                    scoped,
                    visibleBalances,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    bool hasCustodyData,
    bool hasViolations,
  ) {
    final badgeColor = hasViolations ? _errorFg(context) : _successFg(context);
    return Row(
      children: [
        Icon(Icons.compare_arrows, color: context.primaryColor),
        const Gap(8),
        Expanded(
          child: Text(
            'بطاقة مطابقة الخامات والتشغيل (Reconciliation)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
        ),
        if (hasCustodyData || hasViolations) ...[
          const Gap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: badgeColor.withValues(alpha: 0.6)),
            ),
            child: Text(
              hasViolations
                  ? 'تجاوز صرف (${custodyViolations.length})'
                  : 'متطابق',
              style: TextStyle(
                color: badgeColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKpis(
    BuildContext context,
    double maxWidth,
    bool isCompact,
    double totalIssued,
    double totalOnHand,
  ) {
    final items = <({String label, String value, IconData icon})>[
      (
        label: 'العميل صاحب العهدة',
        value: customer?.name ?? '—',
        icon: Icons.person_outline,
      ),
      (
        label: 'الكمية المنتجة',
        value: '${_fmtQty(order.producedQuantity)} وحدة',
        icon: Icons.check_circle_outline,
      ),
      (
        label: 'المسلم للعميل',
        value: '${_fmtQty(deliveredQty)} وحدة',
        icon: Icons.local_shipping_outlined,
      ),
      (
        label: 'المتبقي للتسليم',
        value: '${_fmtQty(math.max(0.0, order.producedQuantity - deliveredQty))} وحدة',
        icon: Icons.hourglass_bottom,
      ),
      (
        label: 'المصروف من العهدة',
        value: '${_fmtQty(totalIssued)} وحدة',
        icon: Icons.remove_circle_outline,
      ),
      (
        label: 'رصيد العهدة بالمخزن',
        value: '${_fmtQty(totalOnHand)} وحدة',
        icon: Icons.warehouse_outlined,
      ),
      if (order.productionCompletedAt != null)
        (
          label: 'إتمام الإنتاج',
          value: DateFormat('yyyy/MM/dd HH:mm').format(order.productionCompletedAt!),
          icon: Icons.event_available_outlined,
        ),
    ];

    final tileWidth = isCompact
        ? (maxWidth - 10) / 2
        : math.max(170.0, (maxWidth - 30) / 4);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in items)
          SizedBox(
            width: tileWidth,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(item.icon, size: 18, color: context.primaryColor),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          item.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildViolationsBanner(BuildContext context, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: colorScheme.onErrorContainer,
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  'تنبيهات معادلة العهدة (D-02)',
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const Gap(6),
          for (final v in custodyViolations)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $v',
                style: TextStyle(
                  color: colorScheme.onErrorContainer,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustodyReconciliationBlock(
    BuildContext context,
    ThemeData theme,
    bool isCompact,
    List<CustodyLine> lines,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'مصالحة خامات العميل حسب الصنف (D-02)',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
        const Gap(8),
        if (lines.isEmpty)
          Text(
            'لا توجد حركات صرف أو استهلاك عهدة مسجلة لهذا الأمر بعد.',
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          )
        else if (isCompact)
          Column(
            children: [
              for (final line in lines)
                _buildCustodyMobileCard(context, line),
            ],
          )
        else
          _buildCustodyDesktopTable(context, lines),
      ],
    );
  }

  Widget _buildCustodyMobileCard(BuildContext context, CustodyLine line) {
    final name = balanceProductNames[line.productId] ?? '#${line.productId}';
    final maxReturnable = math.max(0.0, line.issued - line.returnedExcess);
    final remColor = line.remaining < -0.01
        ? _errorFg(context)
        : (line.remaining > 0.01 ? _warningFg(context) : _successFg(context));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                'المتبقي: ${_fmtQty(line.remaining)}',
                style: TextStyle(
                  color: remColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Gap(8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _miniStat(context, 'مصروف', _fmtQty(line.issued)),
              _miniStat(context, 'مستهلك', _fmtQty(line.consumed)),
              _miniStat(context, 'مرتجع للعهدة', _fmtQty(line.returnedExcess)),
            ],
          ),
          if (maxReturnable > 0.001) ...[
            const Gap(10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openReturnExcessDialog(context, line, name),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('إرجاع فائض للعهدة'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCustodyDesktopTable(
    BuildContext context,
    List<CustodyLine> lines,
  ) {
    return Table(
      border: TableBorder.all(color: context.borderColor),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FlexColumnWidth(2.6),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(1.4),
        3: FlexColumnWidth(1.6),
        4: FlexColumnWidth(1.4),
        5: FlexColumnWidth(2.0),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: context.bgSurface),
          children: [
            _th(context, 'الصنف'),
            _th(context, 'المصروف'),
            _th(context, 'المستهلك'),
            _th(context, 'مرتجع للعهدة'),
            _th(context, 'المتبقي'),
            _th(context, 'إجراء'),
          ],
        ),
        for (final line in lines) _buildCustodyRow(context, line),
      ],
    );
  }

  TableRow _buildCustodyRow(BuildContext context, CustodyLine line) {
    final name = balanceProductNames[line.productId] ?? '#${line.productId}';
    final maxReturnable = math.max(0.0, line.issued - line.returnedExcess);
    final remColor = line.remaining < -0.01
        ? _errorFg(context)
        : (line.remaining > 0.01 ? _warningFg(context) : _successFg(context));
    return TableRow(
      children: [
        _td(context, name, bold: true),
        _td(context, _fmtQty(line.issued)),
        _td(context, _fmtQty(line.consumed)),
        _td(context, _fmtQty(line.returnedExcess)),
        _td(context, _fmtQty(line.remaining), bold: true, color: remColor),
        Padding(
          padding: const EdgeInsets.all(6),
          child: maxReturnable > 0.001
              ? OutlinedButton.icon(
                  onPressed: () =>
                      _openReturnExcessDialog(context, line, name),
                  icon: const Icon(Icons.undo, size: 15),
                  label: const Text('إرجاع فائض'),
                )
              : Text(
                  '—',
                  style: TextStyle(color: context.textMuted),
                ),
        ),
      ],
    );
  }

  Widget _buildConsumptionLogBlock(
    BuildContext context,
    ThemeData theme,
    bool isCompact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'سجل الاستهلاك التحليلي (${consumptionRecords.length})',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
        const Gap(8),
        if (consumptionRecords.isEmpty)
          Text(
            'لا توجد سجلات استهلاك تحليلي مسجلة لهذا الأمر بعد.',
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          )
        else if (isCompact)
          Column(
            children: [
              for (final r in consumptionRecords)
                _buildConsumptionMobileCard(context, r),
            ],
          )
        else
          _buildConsumptionDesktopTable(context),
      ],
    );
  }

  Widget _buildConsumptionMobileCard(
    BuildContext context,
    ConsumptionRecord r,
  ) {
    final name =
        balanceProductNames[r.materialProductId] ?? '#${r.materialProductId}';
    final isCust = r.ownershipType == 'customer_owned';
    final badgeColor = isCust ? MadarColors.info : context.primaryColor;
    final linkLabel = r.customerStockMovementId != null
        ? '#C-${r.customerStockMovementId}'
        : (r.stockMovementId != null ? '#I-${r.stockMovementId}' : '—');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isCust ? 'عهدة عميل' : 'مخزن المصنع',
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Gap(6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _miniStat(context, 'مخطط', _fmtQty(r.plannedQty ?? 0)),
              _miniStat(context, 'فعلي', _fmtQty(r.actualQty ?? 0)),
              _miniStat(
                context,
                'التكلفة',
                (r.unitCostSnapshot ?? 0).toStringAsFixed(2),
              ),
              _miniStat(context, 'مرجع الحركة', linkLabel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConsumptionDesktopTable(BuildContext context) {
    return Table(
      border: TableBorder.all(color: context.borderColor),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FlexColumnWidth(2.4),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.2),
        4: FlexColumnWidth(1.4),
        5: FlexColumnWidth(1.3),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: context.bgSurface),
          children: [
            _th(context, 'الصنف'),
            _th(context, 'الملكية'),
            _th(context, 'مخطط'),
            _th(context, 'فعلي'),
            _th(context, 'تكلفة الوحدة'),
            _th(context, 'رابط الحركة'),
          ],
        ),
        for (final r in consumptionRecords) _buildConsumptionRow(context, r),
      ],
    );
  }

  TableRow _buildConsumptionRow(BuildContext context, ConsumptionRecord r) {
    final name =
        balanceProductNames[r.materialProductId] ?? '#${r.materialProductId}';
    final isCust = r.ownershipType == 'customer_owned';
    final linkLabel = r.customerStockMovementId != null
        ? '#C-${r.customerStockMovementId}'
        : (r.stockMovementId != null ? '#I-${r.stockMovementId}' : '—');
    return TableRow(
      children: [
        _td(context, name, bold: true),
        _td(
          context,
          isCust ? 'عهدة عميل' : 'مخزن المصنع',
          color: isCust ? MadarColors.info : context.primaryColor,
        ),
        _td(context, _fmtQty(r.plannedQty ?? 0)),
        _td(context, _fmtQty(r.actualQty ?? 0), bold: true),
        _td(context, (r.unitCostSnapshot ?? 0).toStringAsFixed(2)),
        _td(context, linkLabel),
      ],
    );
  }

  Widget _buildBalancesBlock(
    BuildContext context,
    ThemeData theme,
    bool isCompact,
    bool scoped,
    List<CustomerStockBalance> visibleBalances,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          scoped
              ? 'أرصدة عهدة العميل المرتبطة بهذا الأمر:'
              : 'أرصدة عهدة العميل الحالية بالمخزن — كامل عهدة العميل (لا توجد حركة خاصة بهذا الأمر بعد):',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
        const Gap(8),
        if (isCompact)
          Column(
            children: [
              for (final b in visibleBalances)
                _buildBalanceMobileCard(context, b),
            ],
          )
        else
          _buildBalancesDesktopTable(context, visibleBalances),
      ],
    );
  }

  Widget _buildBalanceMobileCard(
    BuildContext context,
    CustomerStockBalance b,
  ) {
    final name = balanceProductNames[b.productId] ?? '#${b.productId}';
    final colorSize = '${b.color ?? ''} ${b.size ?? ''}'.trim();
    final available = math.max(0.0, b.quantityOnHand - b.quantityAllocated);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  colorSize.isEmpty ? name : '$name ($colorSize)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                'المتاح: ${_fmtQty(available)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _successFg(context),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Gap(6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _miniStat(context, 'بالمخزن', _fmtQty(b.quantityOnHand)),
              _miniStat(context, 'محجوز', _fmtQty(b.quantityAllocated)),
            ],
          ),
          if (available > 0.001 && order.customerId != null) ...[
            const Gap(10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openReturnCustodyDialog(context, b, name),
                icon: const Icon(Icons.assignment_return_outlined, size: 16),
                label: const Text('رد للعميل'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBalancesDesktopTable(
    BuildContext context,
    List<CustomerStockBalance> visibleBalances,
  ) {
    return Table(
      border: TableBorder.all(color: context.borderColor),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FlexColumnWidth(2.6),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(1.4),
        3: FlexColumnWidth(1.6),
        4: FlexColumnWidth(1.9),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: context.bgSurface),
          children: [
            _th(context, 'الصنف'),
            _th(context, 'الرصيد بالمخزن'),
            _th(context, 'المحجوز'),
            _th(context, 'اللون / المقاس'),
            _th(context, 'إجراء'),
          ],
        ),
        for (final b in visibleBalances) _buildBalanceRow(context, b),
      ],
    );
  }

  TableRow _buildBalanceRow(BuildContext context, CustomerStockBalance b) {
    final name = balanceProductNames[b.productId] ?? '#${b.productId}';
    final colorSize = '${b.color ?? ''} ${b.size ?? ''}'.trim();
    final available = math.max(0.0, b.quantityOnHand - b.quantityAllocated);
    return TableRow(
      children: [
        _td(context, name, bold: true),
        _td(
          context,
          _fmtQty(b.quantityOnHand),
          bold: true,
          color: _successFg(context),
        ),
        _td(context, _fmtQty(b.quantityAllocated)),
        _td(context, colorSize.isEmpty ? '—' : colorSize),
        Padding(
          padding: const EdgeInsets.all(6),
          child: available > 0.001 && order.customerId != null
              ? OutlinedButton.icon(
                  onPressed: () =>
                      _openReturnCustodyDialog(context, b, name),
                  icon: const Icon(
                    Icons.assignment_return_outlined,
                    size: 15,
                  ),
                  label: const Text('رد للعميل'),
                )
              : Text(
                  '—',
                  style: TextStyle(color: context.textMuted),
                ),
        ),
      ],
    );
  }

  Widget _miniStat(BuildContext context, String label, String value) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 12, color: context.textSecondary),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _th(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: context.textPrimary,
        ),
      ),
    );
  }

  Widget _td(
    BuildContext context,
    String text, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color ?? context.textPrimary,
        ),
      ),
    );
  }

  Future<void> _openReturnExcessDialog(
    BuildContext context,
    CustodyLine line,
    String productName,
  ) async {
    final maxAllowable = math.max(0.0, line.issued - line.returnedExcess);
    final initialQty = line.remaining > 0.001 ? line.remaining : maxAllowable;
    final qtyCtrl = TextEditingController(text: _fmtQty(initialQty));
    final noteCtrl = TextEditingController();
    String? err;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('إرجاع فائض خامات للعهدة'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الصنف: $productName',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: ctx.textPrimary,
                    ),
                  ),
                  const Gap(4),
                  Text(
                    'سيتم رد الفائض من الأمر إلى رصيد عهدة العميل بالمخزن ومصالحة سجل الاستهلاك (D-02 / D-03).',
                    style: TextStyle(fontSize: 12, color: ctx.textSecondary),
                  ),
                  const Gap(12),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'الكمية المرتجعة *',
                      helperText: 'الحد الأقصى المتاح للإرجاع: ${_fmtQty(maxAllowable)}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const Gap(12),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (err != null) ...[
                    const Gap(10),
                    Text(
                      err!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final q = double.tryParse(qtyCtrl.text.trim());
                      if (q == null || q <= 0) {
                        setStateDialog(() => err = 'أدخل كمية صحيحة > 0');
                        return;
                      }
                      setStateDialog(() {
                        saving = true;
                        err = null;
                      });
                      try {
                        await db.customerMaterialReceiptDao
                            .returnExcessFromOrder(
                          orderId: order.id,
                          productId: line.productId,
                          quantity: q,
                          notes: noteCtrl.text.trim().isEmpty
                              ? null
                              : noteCtrl.text.trim(),
                        );
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                      } catch (e) {
                        setStateDialog(() {
                          saving = false;
                          err = e.toString();
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('تأكيد الإرجاع'),
            ),
          ],
        ),
      ),
    );

    qtyCtrl.dispose();
    noteCtrl.dispose();

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرجاع الفائض لرصيد عهدة العميل بنجاح'),
        ),
      );
      onDataChanged();
    }
  }

  Future<void> _openReturnCustodyDialog(
    BuildContext context,
    CustomerStockBalance bal,
    String productName,
  ) async {
    final maxAllowable = math.max(0.0, bal.quantityOnHand - bal.quantityAllocated);
    final qtyCtrl = TextEditingController(text: _fmtQty(maxAllowable));
    final noteCtrl = TextEditingController();
    String? err;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('رد خامات فائضة للعميل'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الصنف: $productName',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: ctx.textPrimary,
                    ),
                  ),
                  const Gap(4),
                  Text(
                    'سيتم خصم الكمية من رصيد العهدة وتسليمها فعلياً للعميل مع قيد حركة return_custody.',
                    style: TextStyle(fontSize: 12, color: ctx.textSecondary),
                  ),
                  const Gap(12),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'الكمية المردودة للعميل *',
                      helperText: 'المتاح غير المحجوز: ${_fmtQty(maxAllowable)}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const Gap(12),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (err != null) ...[
                    const Gap(10),
                    Text(
                      err!,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final q = double.tryParse(qtyCtrl.text.trim());
                      if (q == null || q <= 0) {
                        setStateDialog(() => err = 'أدخل كمية صحيحة > 0');
                        return;
                      }
                      setStateDialog(() {
                        saving = true;
                        err = null;
                      });
                      try {
                        await db.customerMaterialReceiptDao
                            .returnCustodyToCustomer(
                          customerId: order.customerId!,
                          productId: bal.productId,
                          quantity: q,
                          color: bal.color,
                          size: bal.size,
                          notes: noteCtrl.text.trim().isEmpty
                              ? null
                              : noteCtrl.text.trim(),
                        );
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                      } catch (e) {
                        setStateDialog(() {
                          saving = false;
                          err = e.toString();
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('تأكيد الرد للعميل'),
            ),
          ],
        ),
      ),
    );

    qtyCtrl.dispose();
    noteCtrl.dispose();

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل رد الخامات للعميل بنجاح'),
        ),
      );
      onDataChanged();
    }
  }
}
