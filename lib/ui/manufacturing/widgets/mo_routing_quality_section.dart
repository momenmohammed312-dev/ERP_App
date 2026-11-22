import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_inspections_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';

/// Responsive Light/Dark section in [MoDetailScreen] covering FEAT-039 Phases 2 & 4:
/// - Applying & inspecting frozen RoutingTemplate copies + §2.4 terminal output count
/// - External Operations (atVendor tracking)
/// - Rework operations (non-terminal)
/// - Stage Yield metrics (D-11)
/// - Internal Quality Inspections (D-07 / D-10)
class MoRoutingQualitySection extends StatelessWidget {
  final AppDatabase db;
  final ManufacturingOrder order;
  final List<ManufacturingStage> stages;
  final VoidCallback onDataChanged;

  const MoRoutingQualitySection({
    super.key,
    required this.db,
    required this.order,
    required this.stages,
    required this.onDataChanged,
  });

  Color _successFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D);

  Color _warningFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFF92400E);

  String _fmtQty(double v) =>
      (v - v.roundToDouble()).abs() < 0.0001 ? v.round().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canMutate = order.status != ManufacturingOrderStatus.completed &&
        order.status != ManufacturingOrderStatus.cancelled;

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
                _buildActionBar(context, canMutate),
                const Gap(16),
                _buildExternalOpsBlock(context, isCompact),
                const Gap(16),
                _buildReworksBlock(context),
                const Gap(16),
                _buildStageYieldsBlock(context),
                const Gap(16),
                _buildInspectionsBlock(context),
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
              Icon(Icons.alt_route, color: context.primaryColor),
              const Gap(8),
              Flexible(
                child: Text(
                  'التوجيه العام، الورش الخارجية والجودة',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (order.routingCode != null)
                _pill(
                  context,
                  'مسار مجمّد: ${order.routingCode}',
                  MadarColors.info,
                ),
              FutureBuilder<double>(
                future: db.routingDao.computeTerminalProducedQuantity(order.id),
                builder: (ctx, snap) {
                  final val = snap.data ?? 0.0;
                  return _pill(
                    ctx,
                    'إنتاج نهائي §2.4: ${_fmtQty(val)}',
                    _successFg(ctx),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context, bool canMutate) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canMutate)
          OutlinedButton.icon(
            onPressed: () => _openApplyTemplateDialog(context),
            icon: const Icon(Icons.account_tree_outlined, size: 16),
            label: const Text('تطبيق قالب مسار'),
          ),
        OutlinedButton.icon(
          onPressed: () => _openAddExternalOpDialog(context),
          icon: const Icon(Icons.local_shipping_outlined, size: 16),
          label: const Text('عمل خارجي (ورشة)'),
        ),
        if (stages.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _openRecordReworkDialog(context),
            icon: const Icon(Icons.replay_circle_filled_outlined, size: 16),
            label: const Text('إعادة تشغيل (Rework)'),
          ),
        OutlinedButton.icon(
          onPressed: () => _openRecordInspectionDialog(context),
          icon: const Icon(Icons.verified_outlined, size: 16),
          label: const Text('فحص جودة (D-07)'),
        ),
      ],
    );
  }

  Widget _buildExternalOpsBlock(BuildContext context, bool isCompact) {
    return StreamBuilder<List<ExternalOperationRecord>>(
      stream: db.externalOperationDao.watchForOrder(order.id),
      builder: (context, snap) {
        final ops = snap.data ?? const <ExternalOperationRecord>[];
        final atVendorTotal = ops.fold<double>(
          0.0,
          (s, r) => s + (r.sentQty - r.receivedQty - r.scrapQty),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'العمليات الخارجية (${ops.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (ops.isNotEmpty)
                  _pill(
                    context,
                    'عند الورش: ${_fmtQty(atVendorTotal)}',
                    atVendorTotal > 0.01
                        ? _warningFg(context)
                        : _successFg(context),
                  ),
              ],
            ),
            const Gap(6),
            if (ops.isEmpty)
              Text(
                'لا توجد عمليات خارجية مسجلة.',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              )
            else
              for (final op in ops)
                _rowCard(
                  context,
                  title: op.vendor,
                  trailing: '${op.cost.toStringAsFixed(2)} ج.م',
                  subtitle:
                      'مرسل: ${_fmtQty(op.sentQty)} • مستلم: ${_fmtQty(op.receivedQty)} • هالك: ${_fmtQty(op.scrapQty)} • متبقي: ${_fmtQty(math.max(0.0, op.sentQty - op.receivedQty - op.scrapQty))}',
                ),
          ],
        );
      },
    );
  }

  Widget _buildReworksBlock(BuildContext context) {
    return StreamBuilder<List<ManufacturingReworkRecord>>(
      stream: db.routingDao.watchReworksForOrder(order.id),
      builder: (context, snap) {
        final rows = snap.data ?? const <ManufacturingReworkRecord>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سجل إعادة التشغيل — Rework (${rows.length})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
                fontSize: 13,
              ),
            ),
            const Gap(6),
            if (rows.isEmpty)
              Text(
                'لا توجد حالات إعادة تشغيل.',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              )
            else
              for (final r in rows)
                _rowCard(
                  context,
                  title: 'كمية ${_fmtQty(r.quantity)} — ${r.reason}',
                  trailing: r.reworkedBy ?? '—',
                  subtitle: r.dispositionNote ?? 'مرحلة #${r.originalStageId}',
                ),
          ],
        );
      },
    );
  }

  Widget _buildStageYieldsBlock(BuildContext context) {
    final stageNames = {for (final s in stages) s.id: s.stageName};
    return StreamBuilder<List<StageYieldRecord>>(
      stream: db.stageYieldDao.watchForOrder(order.id),
      builder: (context, snap) {
        final rows = snap.data ?? const <StageYieldRecord>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'كفاءة المراحل — Stage Yield (${rows.length})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
                fontSize: 13,
              ),
            ),
            const Gap(6),
            if (rows.isEmpty)
              Text(
                'تُحتسب تلقائياً عند إكمال كل مرحلة.',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final y in rows)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: context.bgSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: Text(
                        '${stageNames[y.stageId] ?? 'مرحلة #${y.stageId}'}: '
                        '${y.yieldPercent.toStringAsFixed(1)}% '
                        '(${_fmtQty(y.acceptedOutput)} / ${_fmtQty(y.inputQuantity)})',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildInspectionsBlock(BuildContext context) {
    return StreamBuilder<List<ManufacturingInspection>>(
      stream: db.manufacturingInspectionDao.watchForOrder(order.id),
      builder: (context, snap) {
        final rows = snap.data ?? const <ManufacturingInspection>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'فحوصات الجودة الداخلية (${rows.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  'داخلي فقط (D-10)',
                  style: TextStyle(color: context.textMuted, fontSize: 11),
                ),
              ],
            ),
            const Gap(6),
            if (rows.isEmpty)
              Text(
                'لا توجد فحوصات جودة مسجلة.',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              )
            else
              for (final ins in rows)
                _rowCard(
                  context,
                  title:
                      '${InspectionResult.label(ins.result)} • كمية ${_fmtQty(ins.quantity)}',
                  trailing: ins.inspectedBy,
                  subtitle: ins.dispositionNote ?? 'فحص تقديري (D-07)',
                ),
          ],
        );
      },
    );
  }

  Widget _rowCard(
    BuildContext context, {
    required String title,
    required String trailing,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
              const Gap(8),
              Text(
                trailing,
                style: TextStyle(
                  color: context.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Gap(2),
          Text(
            subtitle,
            style: TextStyle(color: context.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _openApplyTemplateDialog(BuildContext context) async {
    final templates = (await db.routingDao.getAllTemplates())
        .where((t) => t.status == 'active')
        .toList();
    if (!context.mounted) return;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أنشئ قالب مسار أولاً من شاشة مسارات الإنتاج')),
      );
      return;
    }

    int selectedId = templates.first.id;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('تطبيق قالب مسار وتجميده للأمر'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'اختر القالب',
                    border: OutlineInputBorder(),
                  ),
                  items: templates
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.name} (${t.code})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setStateDialog(() => selectedId = v);
                  },
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await db.routingDao.applyTemplateToOrder(
                    templateId: selectedId,
                    orderId: order.id,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                } catch (e) {
                  setStateDialog(() => err = e.toString());
                }
              },
              child: const Text('تطبيق وتجميد'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) onDataChanged();
  }

  Future<void> _openAddExternalOpDialog(BuildContext context) async {
    final vendorCtrl = TextEditingController();
    final sentCtrl = TextEditingController(text: _fmtQty(order.plannedQuantity));
    final recCtrl = TextEditingController(text: '0');
    final scrapCtrl = TextEditingController(text: '0');
    final costCtrl = TextEditingController(text: '0');
    int? stageId = stages.isNotEmpty ? stages.first.id : null;
    String? err;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('تسجيل عملية خارجية (ورشة)'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: vendorCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الورشة / المقاول الخارجي *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(10),
                  if (stages.isNotEmpty) ...[
                    DropdownButtonFormField<int?>(
                      initialValue: stageId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'المرحلة المرتبطة',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in stages)
                          DropdownMenuItem<int?>(
                            value: s.id,
                            child: Text(s.stageName),
                          ),
                      ],
                      onChanged: (v) => setStateDialog(() => stageId = v),
                    ),
                    const Gap(10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: sentCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'مرسل *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const Gap(8),
                      Expanded(
                        child: TextField(
                          controller: recCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'مستلم',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: scrapCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'هالك عند الورشة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const Gap(8),
                      Expanded(
                        child: TextField(
                          controller: costCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'التكلفة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
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
                  await db.externalOperationDao.insertExternalOperationRecord(
                    manufacturingOrderId: order.id,
                    operationId: stageId,
                    vendor: vendorCtrl.text,
                    sentQty: double.tryParse(sentCtrl.text.trim()) ?? 0.0,
                    receivedQty: double.tryParse(recCtrl.text.trim()) ?? 0.0,
                    scrapQty: double.tryParse(scrapCtrl.text.trim()) ?? 0.0,
                    cost: double.tryParse(costCtrl.text.trim()) ?? 0.0,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                } catch (e) {
                  setStateDialog(() => err = e.toString());
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    vendorCtrl.dispose();
    sentCtrl.dispose();
    recCtrl.dispose();
    scrapCtrl.dispose();
    costCtrl.dispose();
    if (ok == true) onDataChanged();
  }

  Future<void> _openRecordReworkDialog(BuildContext context) async {
    int stageId = stages.first.id;
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    final byCtrl = TextEditingController();
    String? err;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('تسجيل إعادة تشغيل (Rework)'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: stageId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المرحلة الأصلية',
                      border: OutlineInputBorder(),
                    ),
                    items: stages
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.stageName),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setStateDialog(() => stageId = v);
                    },
                  ),
                  const Gap(10),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'الكمية المعاد تشغيلها *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(10),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'سبب إعادة التشغيل *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(10),
                  TextField(
                    controller: byCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المشرف / المسؤول (اختياري)',
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
                  await db.routingDao.recordRework(
                    orderId: order.id,
                    originalStageId: stageId,
                    quantity: double.tryParse(qtyCtrl.text.trim()) ?? 0.0,
                    reason: reasonCtrl.text,
                    reworkedBy: byCtrl.text.trim().isEmpty
                        ? null
                        : byCtrl.text.trim(),
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                } catch (e) {
                  setStateDialog(() => err = e.toString());
                }
              },
              child: const Text('تسجيل إعادة التشغيل'),
            ),
          ],
        ),
      ),
    );

    qtyCtrl.dispose();
    reasonCtrl.dispose();
    byCtrl.dispose();
    if (ok == true) onDataChanged();
  }

  Future<void> _openRecordInspectionDialog(BuildContext context) async {
    final byCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: _fmtQty(order.plannedQuantity));
    final noteCtrl = TextEditingController();
    String result = InspectionResult.accepted;
    int? stageId = stages.isNotEmpty ? stages.first.id : null;
    String? err;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('تسجيل فحص جودة داخلي (D-07)'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: byCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الفاحص / المشرف *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(10),
                  DropdownButtonFormField<String>(
                    initialValue: result,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'نتيجة الفحص *',
                      border: OutlineInputBorder(),
                    ),
                    items: InspectionResult.all
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(InspectionResult.label(r)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setStateDialog(() => result = v);
                    },
                  ),
                  const Gap(10),
                  if (stages.isNotEmpty) ...[
                    DropdownButtonFormField<int?>(
                      initialValue: stageId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'المرحلة',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('فحص نهائي للأمر'),
                        ),
                        for (final s in stages)
                          DropdownMenuItem<int?>(
                            value: s.id,
                            child: Text(s.stageName),
                          ),
                      ],
                      onChanged: (v) => setStateDialog(() => stageId = v),
                    ),
                    const Gap(10),
                  ],
                  TextField(
                    controller: qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'الكمية المفحوصة *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(10),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات التقدير (داخلي فقط)',
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
                  await db.manufacturingInspectionDao.recordInspection(
                    orderId: order.id,
                    stageId: stageId,
                    productId: order.finishedProductId,
                    inspectedBy: byCtrl.text,
                    result: result,
                    quantity: double.tryParse(qtyCtrl.text.trim()) ?? 0.0,
                    dispositionNote: noteCtrl.text.trim().isEmpty
                        ? null
                        : noteCtrl.text.trim(),
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                } catch (e) {
                  setStateDialog(() => err = e.toString());
                }
              },
              child: const Text('حفظ الفحص'),
            ),
          ],
        ),
      ),
    );

    byCtrl.dispose();
    qtyCtrl.dispose();
    noteCtrl.dispose();
    if (ok == true) onDataChanged();
  }
}
