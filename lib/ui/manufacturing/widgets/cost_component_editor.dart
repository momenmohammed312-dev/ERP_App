import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_cost_components_table.dart';

class CostComponentEditor extends StatefulWidget {
  final AppDatabase db;
  final int orderId;
  final String orderStatus; // to gate editing
  final void Function()? onChanged; // notify parent to refresh cost summary

  const CostComponentEditor({
    super.key,
    required this.db,
    required this.orderId,
    required this.orderStatus,
    this.onChanged,
  });

  @override
  State<CostComponentEditor> createState() => _CostComponentEditorState();
}

class _CostComponentEditorState extends State<CostComponentEditor> {
  bool get _isReadOnly =>
      widget.orderStatus == 'completed' || widget.orderStatus == 'cancelled';

  Future<void> _showAddEditDialog({ManufacturingCostComponent? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final valueCtrl = TextEditingController(text: existing != null ? existing.value.toString() : '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String costType = existing?.costType ?? ManufacturingCostType.fixed;
    String? error;

    final res = await showDialog<bool>(
      context: context,
      builder: (c) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(existing == null ? 'إضافة تكلفة' : 'تعديل تكلفة'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (error != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                      ),
                    if (error != null) const Gap(12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم البند *',
                        hintText: 'عمالة، كهرباء، تعبئة...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const Gap(12),
                    DropdownButtonFormField<String>(
                      initialValue: costType,
                      decoration: const InputDecoration(
                        labelText: 'نوع التكلفة *',
                        border: OutlineInputBorder(),
                      ),
                      items: ManufacturingCostType.all
                          .map((t) => DropdownMenuItem(value: t, child: Text(ManufacturingCostType.label(t))))
                          .toList(),
                      onChanged: (v) => setStateDialog(() => costType = v ?? ManufacturingCostType.fixed),
                    ),
                    const Gap(12),
                    TextField(
                      controller: valueCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: costType == ManufacturingCostType.percentage ? 'النسبة % *' : costType == ManufacturingCostType.fixed ? 'المبلغ (ج.م) *' : 'المبلغ لكل وحدة (ج.م) *',
                        border: const OutlineInputBorder(),
                        suffixText: costType == ManufacturingCostType.percentage ? '%' : 'ج.م',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const Gap(8),
                    _buildCostTypeHint(costType),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final val = double.tryParse(valueCtrl.text.trim());
                    if (name.isEmpty) {
                      setStateDialog(() => error = 'اسم البند مطلوب');
                      return;
                    }
                    if (val == null || val < 0) {
                      setStateDialog(() => error = 'أدخل قيمة صحيحة ≥ 0');
                      return;
                    }
                    if (costType == ManufacturingCostType.percentage && val > 100) {
                      setStateDialog(() => error = 'النسبة يجب أن تكون بين 0 و 100');
                      return;
                    }
                    try {
                      if (existing == null) {
                        await widget.db.manufacturingCostComponentDao.insertComponent(
                          ManufacturingCostComponentsCompanion(
                            manufacturingOrderId: Value(widget.orderId),
                            name: Value(name),
                            costType: Value(costType),
                            value: Value(val),
                            notes: Value(notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim()),
                          ),
                        );
                      } else {
                        await widget.db.manufacturingCostComponentDao.updateComponent(
                          existing.copyWith(
                            name: name,
                            costType: costType,
                            value: val,
                            notes: Value(notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim()),
                          ),
                        );
                      }
                      if (c.mounted) Navigator.pop(c, true);
                    } catch (e) {
                      setStateDialog(() => error = 'فشل: $e');
                    }
                  },
                  child: Text(existing == null ? 'إضافة' : 'حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    if (res == true && mounted) {
      widget.onChanged?.call();
      if (mounted) setState(() {});
    }
  }

  Widget _buildCostTypeHint(String type) {
    String hint;
    switch (type) {
      case ManufacturingCostType.fixed:
        hint = 'مبلغ ثابت يضاف مرة واحدة على إجمالي الأمر';
        break;
      case ManufacturingCostType.percentage:
        hint = 'نسبة من التكلفة المادية فقط (لا تشمل باقي التكاليف)';
        break;
      case ManufacturingCostType.perUnit:
        hint = 'مبلغ يضرب في عدد الوحدات المنتجة';
        break;
      default:
        hint = '';
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.grey),
          const Gap(8),
          Expanded(child: Text(hint, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        ],
      ),
    );
  }

  Future<void> _deleteComponent(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف البند'),
        content: const Text('هل أنت متأكد من حذف هذا البند؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.db.manufacturingCostComponentDao.deleteComponent(id);
    widget.onChanged?.call();
  }

  Future<void> _copyFromLastOrder() async {
    try {
      final sourceId = await widget.db.manufacturingCostComponentDao.findMostRecentOrderWithComponents(excludeOrderId: widget.orderId);
      if (sourceId == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد أمر سابق به تكاليف للنسخ')));
        return;
      }
      await widget.db.manufacturingCostComponentDao.copyFromOrder(sourceOrderId: sourceId, targetOrderId: widget.orderId);
      widget.onChanged?.call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نسخ التكاليف من الأمر #$sourceId')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النسخ: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('تكاليف إضافية', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (!_isReadOnly) ...[
              TextButton.icon(
                onPressed: _copyFromLastOrder,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('نسخ من آخر أمر'),
              ),
              FilledButton.icon(
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة'),
              ),
            ] else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                child: Text('للقراءة فقط',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const Gap(8),
        StreamBuilder<List<ManufacturingCostComponent>>(
          stream: widget.db.manufacturingCostComponentDao.watchForOrder(widget.orderId),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('خطأ: ${snapshot.error}');
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final comps = snapshot.data!;
            if (comps.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Icon(Icons.receipt_outlined, color: Colors.grey.shade400, size: 32),
                    const Gap(8),
                    Text('لا توجد تكاليف إضافية بعد', style: TextStyle(color: Colors.grey.shade600)),
                    if (!_isReadOnly) const Gap(4),
                    if (!_isReadOnly) Text('أضف عمالة، كهرباء، تعبئة...', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: comps.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final c = comps[index];
                IconData icon;
                Color color;
                String valueLabel;
                switch (c.costType) {
                  case ManufacturingCostType.fixed:
                    icon = Icons.attach_money;
                    color = Colors.blue;
                    valueLabel = '${c.value.toStringAsFixed(2)} ج.م (ثابت)';
                    break;
                  case ManufacturingCostType.percentage:
                    icon = Icons.percent;
                    color = Colors.purple;
                    valueLabel = '${c.value.toStringAsFixed(1)}%';
                    break;
                  case ManufacturingCostType.perUnit:
                    icon = Icons.numbers;
                    color = Colors.orange;
                    valueLabel = '${c.value.toStringAsFixed(2)} ج.م/وحدة';
                    break;
                  default:
                    icon = Icons.help;
                    color = Colors.grey;
                    valueLabel = '${c.value}';
                }
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    '$valueLabel • ${ManufacturingCostType.label(c.costType)}'
                    '${c.computedAmount != null ? ' → محسوب: ${c.computedAmount!.toStringAsFixed(2)} ج.م' : ''}'
                    '${c.notes != null ? ' • ${c.notes}' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  trailing: _isReadOnly
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _showAddEditDialog(existing: c);
                            if (v == 'delete') _deleteComponent(c.id);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('تعديل')),
                            PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
