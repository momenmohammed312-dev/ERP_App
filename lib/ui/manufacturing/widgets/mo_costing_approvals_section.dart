import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_costing_dao.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/searchable_product_picker.dart';

/// Internal-only costing breakdown (D-11 / §5) and customer extra-material
/// approvals section (D-04, D-05, D-08) for [MoDetailScreen].
///
/// Responsive on Mobile (`< 600px`) and Desktop, and Light/Dark aware.
class MoCostingApprovalsSection extends StatelessWidget {
  final AppDatabase db;
  final ManufacturingOrder order;
  final Map<int, String> balanceProductNames;
  final VoidCallback onDataChanged;

  const MoCostingApprovalsSection({
    super.key,
    required this.db,
    required this.order,
    required this.balanceProductNames,
    required this.onDataChanged,
  });

  Color _successFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D);

  Color _warningFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFF92400E);

  Color _errorFg(BuildContext context) => Theme.of(context).colorScheme.error;

  String _fmtQty(double v) =>
      (v - v.roundToDouble()).abs() < 0.0001 ? v.round().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                _buildHeader(context, theme),
                const Divider(height: 24),
                _buildCostingKpis(context, constraints.maxWidth, isCompact),
                if (order.orderType != 'internal') ...[
                  const Gap(20),
                  _buildApprovalsBlock(context),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.analytics_outlined, color: context.primaryColor),
              const Gap(8),
              Flexible(
                child: Text(
                  'التكلفة الداخلية الفعلية وموافقات الخامات الإضافية',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          StreamBuilder<ManufacturingCostSnapshot?>(
            stream: db.manufacturingCostingDao.watchLatestSnapshot(order.id),
            builder: (ctx, snap) {
              final hasFrozen = snap.data != null;
              return Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (hasFrozen ? _successFg(ctx) : _warningFg(ctx))
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      hasFrozen ? 'لقطة مجمّدة (داخلي D-10)' : 'معاينة حية (داخلي D-10)',
                      style: TextStyle(
                        color: hasFrozen ? _successFg(ctx) : _warningFg(ctx),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await db.manufacturingCostingDao.freezeCostSnapshot(
                        order.id,
                        notes: 'تجميد يدوي من شاشة الأمر',
                      );
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('تم تجميد لقطة التكلفة والهامش بنجاح'),
                          ),
                        );
                        onDataChanged();
                      }
                    },
                    icon: const Icon(Icons.lock_outline, size: 15),
                    label: const Text('تجميد التكلفة'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCostingKpis(
    BuildContext context,
    double maxWidth,
    bool isCompact,
  ) {
    return FutureBuilder<OrderCostBreakdown>(
      future: db.manufacturingCostingDao.computeOrderCost(order.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const LinearProgressIndicator();
        }
        final b = snap.data!;
        final tileWidth = isCompact
            ? (maxWidth - 10) / 2
            : math.max(165.0, (maxWidth - 30) / 4);

        final kpis = <({String label, String value, Color? color})>[
          (
            label: 'خامات المصنع (عميل=0)',
            value: '${b.materialCost.toStringAsFixed(2)} ج.م',
            color: null,
          ),
          (
            label: 'تكلفة العمالة',
            value: '${b.laborCost.toStringAsFixed(2)} ج.م',
            color: null,
          ),
          (
            label: 'تكلفة الماكينات',
            value: '${b.machineCost.toStringAsFixed(2)} ج.م',
            color: null,
          ),
          (
            label: 'أعمال خارجية',
            value: '${b.externalCost.toStringAsFixed(2)} ج.م',
            color: null,
          ),
          (
            label: 'مصاريف إضافية',
            value: '${b.otherCost.toStringAsFixed(2)} ج.م',
            color: null,
          ),
          (
            label: 'إجمالي فعلي / مخطط',
            value:
                '${b.totalActualCost.toStringAsFixed(2)} / ${b.plannedCost.toStringAsFixed(2)}',
            color: context.primaryColor,
          ),
          (
            label: 'الانحراف (Variance)',
            value: '${b.variance.toStringAsFixed(2)} ج.م',
            color: b.variance >= 0 ? _successFg(context) : _errorFg(context),
          ),
          (
            label: 'الهامش الفعلي (Margin)',
            value: '${b.actualMargin.toStringAsFixed(2)} ج.م',
            color:
                b.actualMargin >= 0 ? _successFg(context) : _errorFg(context),
          ),
        ];

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final k in kpis)
              SizedBox(
                width: tileWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.bgSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        k.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: k.color ?? context.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildApprovalsBlock(BuildContext context) {
    return StreamBuilder<List<ExtraMaterialApproval>>(
      stream: db.manufacturingCostingDao.watchApprovalsForOrder(order.id),
      builder: (context, snap) {
        final rows = snap.data ?? const <ExtraMaterialApproval>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'اعتماد خامات إضافية من المصنع (D-04 / D-05 / D-08)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  if (order.invoiceId == null)
                    FilledButton.tonalIcon(
                      onPressed: () => _openRequestExtraDialog(context),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('طلب خام إضافي'),
                    ),
                ],
              ),
            ),
            const Gap(8),
            if (rows.isEmpty)
              Text(
                'لا توجد طلبات خامات إضافية. المعتمد فقط يُضاف تلقائياً للفاتورة بتكلفة costPrice.',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              )
            else
              for (final a in rows) _buildApprovalCard(context, a),
          ],
        );
      },
    );
  }

  Widget _buildApprovalCard(BuildContext context, ExtraMaterialApproval a) {
    final prodName = balanceProductNames[a.productId] ?? 'صنف #${a.productId}';
    final statusColor = a.status == 'approved'
        ? _successFg(context)
        : (a.status == 'rejected' ? _errorFg(context) : _warningFg(context));
    final statusLabel = a.status == 'approved'
        ? 'معتمد للفاتورة'
        : (a.status == 'rejected' ? 'مرفوض' : 'بانتظار اعتماد العميل');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
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
                  prodName,
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
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Gap(4),
          Text(
            'الكمية: ${_fmtQty(a.quantity)} • تكلفة/وحدة: ${a.unitCostSnapshot.toStringAsFixed(2)} '
            '• هامش: ${a.marginPercent}% • الإجمالي: ${a.approvedAmount.toStringAsFixed(2)} ج.م',
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          if (a.authorizationRef != null && a.authorizationRef!.isNotEmpty)
            Text(
              'مرجع الاعتماد: ${a.authorizationRef} (${a.approvedBy ?? ''})',
              style: TextStyle(color: context.textMuted, fontSize: 11),
            ),
          if (a.status == 'pending') ...[
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  onPressed: () => _openApproveDialog(context, a),
                  icon: const Icon(Icons.check, size: 15),
                  label: const Text('اعتماد العميل'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await db.manufacturingCostingDao.rejectExtraMaterial(
                      approvalId: a.id,
                    );
                    onDataChanged();
                  },
                  icon: const Icon(Icons.close, size: 15),
                  label: const Text('رفض'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openRequestExtraDialog(BuildContext context) async {
    Product? selectedProd;
    final qtyCtrl = TextEditingController(text: '1');
    final marginCtrl = TextEditingController(text: '0');
    final reqByCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? err;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('طلب خام إضافي من المصنع (D-04 / D-08)'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SearchableProductPicker(
                    db: db,
                    label: 'الصنف الإضافي *',
                    showAddButton: false,
                    onChanged: (p) => setStateDialog(() => selectedProd = p),
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'الكمية *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const Gap(8),
                      Expanded(
                        child: TextField(
                          controller: marginCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'الهامش % (افتراضي 0)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  TextField(
                    controller: reqByCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم طالب الإذن (المشرف) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (err != null) ...[
                    const Gap(8),
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
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (selectedProd == null) {
                  setStateDialog(() => err = 'اختر الصنف أولاً');
                  return;
                }
                try {
                  await db.manufacturingCostingDao.requestExtraMaterial(
                    orderId: order.id,
                    productId: selectedProd!.id,
                    quantity: double.tryParse(qtyCtrl.text.trim()) ?? 0.0,
                    marginPercent:
                        double.tryParse(marginCtrl.text.trim()) ?? 0.0,
                    requestedBy: reqByCtrl.text,
                    notes: noteCtrl.text.trim().isEmpty
                        ? null
                        : noteCtrl.text.trim(),
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                } catch (e) {
                  setStateDialog(() => err = e.toString());
                }
              },
              child: const Text('إرسال للاعتماد'),
            ),
          ],
        ),
      ),
    );

    qtyCtrl.dispose();
    marginCtrl.dispose();
    reqByCtrl.dispose();
    noteCtrl.dispose();
    if (ok == true) onDataChanged();
  }

  Future<void> _openApproveDialog(
    BuildContext context,
    ExtraMaterialApproval approval,
  ) async {
    final byCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final amtCtrl =
        TextEditingController(text: approval.approvedAmount.toStringAsFixed(2));
    String? err;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('اعتماد العميل للخام الإضافي'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: byCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المعتمد (من طرف العميل) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(10),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'مرجع الموافقة (رقم إذن / رسالة)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(10),
                  TextField(
                    controller: amtCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ المعتمد (ج.م)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (err != null) ...[
                    const Gap(8),
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
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await db.manufacturingCostingDao.approveExtraMaterial(
                    approvalId: approval.id,
                    approvedBy: byCtrl.text,
                    authorizationRef: refCtrl.text.trim().isEmpty
                        ? null
                        : refCtrl.text.trim(),
                    overrideAmount: double.tryParse(amtCtrl.text.trim()),
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                } catch (e) {
                  setStateDialog(() => err = e.toString());
                }
              },
              child: const Text('تأكيد الاعتماد'),
            ),
          ],
        ),
      ),
    );

    byCtrl.dispose();
    refCtrl.dispose();
    amtCtrl.dispose();
    if (ok == true) onDataChanged();
  }
}
