import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/routing_tables.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';

/// Industry-agnostic Routing Templates management screen (FEAT-039 Phase 2 — §3.1).
///
/// Supports sequential and parallel routing branches (`parentNodeId`),
/// operation types, technique parameters, default labor/machine rates, and
/// terminal node marking (`isTerminal` for §2.4 output counting).
/// Fully responsive (Mobile `< 720px` & Desktop `>= 720px`) and Light/Dark aware.
class RoutingTemplatesScreen extends StatefulWidget {
  final AppDatabase db;

  const RoutingTemplatesScreen({super.key, required this.db});

  @override
  State<RoutingTemplatesScreen> createState() => _RoutingTemplatesScreenState();
}

class _RoutingTemplatesScreenState extends State<RoutingTemplatesScreen> {
  int? _selectedTemplateId;

  Color _successFg(BuildContext context) =>
      context.isDarkMode ? const Color(0xFF4ADE80) : const Color(0xFF15803D);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: context.bgCanvas,
      appBar: AppBar(
        title: const Text('قوالب مسارات الإنتاج (Routing)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.precision_manufacturing_outlined),
            tooltip: 'أوامر التصنيع',
            onPressed: () => context.push('/manufacturing/orders'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateTemplateDialog,
        icon: const Icon(Icons.add),
        label: const Text('قالب مسار جديد'),
      ),
      body: Column(
        children: [
          _buildQuickNavStrip(theme),
          Expanded(
            child: StreamBuilder<List<RoutingTemplate>>(
              stream: widget.db.routingDao.watchAllTemplates(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('خطأ: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final templates = snap.data!;
                if (templates.isEmpty) {
                  return _buildEmptyState();
                }

                final selected = templates.firstWhere(
                  (t) => t.id == _selectedTemplateId,
                  orElse: () => templates.first,
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 720;
                    if (isCompact) {
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                        itemCount: templates.length,
                        separatorBuilder: (_, _) => const Gap(10),
                        itemBuilder: (ctx, idx) {
                          final tpl = templates[idx];
                          final isSelected = tpl.id == selected.id;
                          return Column(
                            children: [
                              _buildTemplateCard(ctx, tpl, isSelected),
                              if (isSelected) ...[
                                const Gap(8),
                                _buildTemplateDetailCard(ctx, tpl),
                              ],
                            ],
                          );
                        },
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 340,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: templates.length,
                              separatorBuilder: (_, _) => const Gap(10),
                              itemBuilder: (ctx, idx) {
                                final tpl = templates[idx];
                                return _buildTemplateCard(
                                  ctx,
                                  tpl,
                                  tpl.id == selected.id,
                                );
                              },
                            ),
                          ),
                          const Gap(16),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 80),
                              child: _buildTemplateDetailCard(context, selected),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickNavStrip(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => context.push('/manufacturing/orders'),
              icon: const Icon(Icons.precision_manufacturing, size: 18),
              label: const Text('أوامر التصنيع'),
            ),
            const Gap(8),
            FilledButton.tonalIcon(
              onPressed: () {},
              icon: const Icon(Icons.alt_route, size: 18),
              label: const Text('مسارات الإنتاج'),
            ),
            const Gap(8),
            OutlinedButton.icon(
              onPressed: () => context.push('/manufacturing/bom'),
              icon: const Icon(Icons.playlist_add_check, size: 18),
              label: const Text('الوصفات (BOM)'),
            ),
            const Gap(8),
            OutlinedButton.icon(
              onPressed: () => context.push('/manufacturing/reports'),
              icon: const Icon(Icons.analytics_outlined, size: 18),
              label: const Text('تقارير التصنيع'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alt_route, size: 56, color: context.textMuted),
            const Gap(12),
            Text(
              'لا توجد قوالب مسارات إنتاج بعد',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Gap(6),
            Text(
              'أنشئ قالب مسار عام (متسلسل أو بفروع متوازية) لتطبيقه وتجميده على أوامر التشغيل.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCard(
    BuildContext context,
    RoutingTemplate tpl,
    bool isSelected,
  ) {
    final isActive = tpl.status == 'active';
    final statusColor = isActive ? _successFg(context) : context.textMuted;

    return Card(
      elevation: isSelected ? 3 : 1,
      color: isSelected ? context.primaryContainer : context.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? context.primaryColor : context.borderSubtle,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedTemplateId = tpl.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.account_tree_outlined, color: context.primaryColor),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tpl.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      tpl.code,
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'نشط' : 'موقوف',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateDetailCard(BuildContext context, RoutingTemplate tpl) {
    final isActive = tpl.status == 'active';
    return Card(
      elevation: 2,
      color: context.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${tpl.name} (${tpl.code})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: context.textPrimary,
                            ),
                      ),
                      if (tpl.notes != null && tpl.notes!.isNotEmpty)
                        Text(
                          tpl.notes!,
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => widget.db.routingDao.updateTemplateStatus(
                          tpl.id,
                          isActive ? 'inactive' : 'active',
                        ),
                        icon: Icon(
                          isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
                          size: 16,
                        ),
                        label: Text(isActive ? 'إيقاف' : 'تفعيل'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openAddNodeDialog(tpl.id),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('إضافة خطوة / فرع'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            StreamBuilder<List<RoutingTemplateNode>>(
              stream: widget.db.routingDao.watchNodesForTemplate(tpl.id),
              builder: (context, snap) {
                final nodes = snap.data ?? const <RoutingTemplateNode>[];
                if (nodes.isEmpty) {
                  return Text(
                    'لا توجد خطوات في هذا القالب بعد. اضغط "إضافة خطوة / فرع" لبدء تعريف المسار.',
                    style: TextStyle(color: context.textSecondary, fontSize: 13),
                  );
                }
                final nodeNames = {for (final n in nodes) n.id: n.name};
                return Column(
                  children: [
                    for (final n in nodes)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.bgSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 13,
                                  backgroundColor: context.primaryContainer,
                                  child: Text(
                                    '${n.stageOrder}',
                                    style: TextStyle(
                                      color: context.primaryColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Gap(8),
                                Expanded(
                                  child: Text(
                                    n.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: context.textPrimary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (n.isTerminal)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _successFg(context)
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'نهائية §2.4',
                                      style: TextStyle(
                                        color: _successFg(context),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  tooltip: 'حذف الخطوة',
                                  onPressed: () =>
                                      widget.db.routingDao.deleteTemplateNode(n.id),
                                ),
                              ],
                            ),
                            const Gap(6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                _chipText(
                                  context,
                                  'النوع: ${RoutingOperationType.label(n.operationType)}',
                                ),
                                if (n.technique != null &&
                                    n.technique!.trim().isNotEmpty)
                                  _chipText(context, 'التقنية: ${n.technique}'),
                                if (n.parentNodeId != null)
                                  _chipText(
                                    context,
                                    'متفرع من: ${nodeNames[n.parentNodeId!] ?? '#${n.parentNodeId}'}',
                                  ),
                                _chipText(
                                  context,
                                  'عمالة/ساعة: ${n.defaultLaborRate} • ماكينة/ساعة: ${n.defaultMachineRate}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipText(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(color: context.textSecondary, fontSize: 12),
    );
  }

  Future<void> _openCreateTemplateDialog() async {
    final codeCtrl = TextEditingController(
      text: 'RT-${DateTime.now().year}-${DateTime.now().millisecond}',
    );
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? err;

    final createdId = await showDialog<int>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('قالب مسار إنتاج جديد'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'كود المسار *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المسار * (مثل: تيشيرت طباعة وتقفيل)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(12),
                  TextField(
                    controller: notesCtrl,
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
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final id = await widget.db.routingDao.createTemplate(
                    code: codeCtrl.text,
                    name: nameCtrl.text,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, id);
                } catch (e) {
                  setStateDialog(() => err = e.toString());
                }
              },
              child: const Text('حفظ القالب'),
            ),
          ],
        ),
      ),
    );

    codeCtrl.dispose();
    nameCtrl.dispose();
    notesCtrl.dispose();

    if (createdId != null && mounted) {
      setState(() => _selectedTemplateId = createdId);
    }
  }

  Future<void> _openAddNodeDialog(int templateId) async {
    final existingNodes =
        await widget.db.routingDao.getNodesForTemplate(templateId);
    if (!mounted) return;

    final nameCtrl = TextEditingController();
    final orderCtrl = TextEditingController(
      text: '${existingNodes.length + 1}',
    );
    final techniqueCtrl = TextEditingController();
    final laborCtrl = TextEditingController(text: '0');
    final machineCtrl = TextEditingController(text: '0');
    String opType = RoutingOperationType.generic;
    int? parentNodeId;
    bool isTerminal = existingNodes.isEmpty;
    String? err;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('إضافة خطوة / فرع في المسار'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم العملية / المرحلة *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: orderCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'الترتيب',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: opType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'نوع العملية',
                            border: OutlineInputBorder(),
                          ),
                          items: RoutingOperationType.all
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(RoutingOperationType.label(t)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setStateDialog(() => opType = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  if (existingNodes.isNotEmpty) ...[
                    DropdownButtonFormField<int?>(
                      initialValue: parentNodeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'تتبع خطوة (للفروع المتوازية/المتسلسلة)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('بداية مستقلة (بدون أب)'),
                        ),
                        for (final n in existingNodes)
                          DropdownMenuItem<int?>(
                            value: n.id,
                            child: Text('${n.stageOrder}. ${n.name}'),
                          ),
                      ],
                      onChanged: (v) => setStateDialog(() => parentNodeId = v),
                    ),
                    const Gap(12),
                  ],
                  TextField(
                    controller: techniqueCtrl,
                    decoration: const InputDecoration(
                      labelText: 'التقنية (اختياري: screen_print, embroidery...)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: laborCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'معدل العمالة/ساعة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: TextField(
                          controller: machineCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'معدل الماكينة/ساعة',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isTerminal,
                    onChanged: (v) => setStateDialog(() => isTerminal = v),
                    title: const Text(
                      'مرحلة نهائية (تُحسب مخرجاتها في الإنتاج §2.4)',
                      style: TextStyle(fontSize: 13),
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
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.db.routingDao.addTemplateNode(
                    templateId: templateId,
                    parentNodeId: parentNodeId,
                    stageOrder: int.tryParse(orderCtrl.text.trim()),
                    name: nameCtrl.text,
                    operationType: opType,
                    technique: techniqueCtrl.text.trim().isEmpty
                        ? null
                        : techniqueCtrl.text.trim(),
                    defaultLaborRate:
                        double.tryParse(laborCtrl.text.trim()) ?? 0.0,
                    defaultMachineRate:
                        double.tryParse(machineCtrl.text.trim()) ?? 0.0,
                    isTerminal: isTerminal,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                } catch (e) {
                  setStateDialog(() => err = e.toString());
                }
              },
              child: const Text('إضافة الخطوة'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    orderCtrl.dispose();
    techniqueCtrl.dispose();
    laborCtrl.dispose();
    machineCtrl.dispose();
  }
}
