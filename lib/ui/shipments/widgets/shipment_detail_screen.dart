import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/expenses_table.dart';
import 'package:pos_offline_desktop/core/database/tables/supplier_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/shipment_allocation_service.dart';
import 'package:pos_offline_desktop/core/services/shipment_settlement_service.dart';
import 'package:pos_offline_desktop/core/utils/arabic_name_normalizer.dart';
import 'package:pos_offline_desktop/ui/shipments/widgets/shipment_form_dialog.dart';

class ShipmentDetailScreen extends StatefulWidget {
  final AppDatabase db;
  final int shipmentId;

  const ShipmentDetailScreen({
    super.key,
    required this.db,
    required this.shipmentId,
  });

  @override
  State<ShipmentDetailScreen> createState() => _ShipmentDetailScreenState();
}

class _ShipmentDetailScreenState extends State<ShipmentDetailScreen> {
  ShipmentStatement? _statement;
  List<(InvoiceItem, Invoice, Product?)> _linkedItems = [];
  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final settlementService = ShipmentSettlementService(widget.db);
      final statement =
          await settlementService.getShipmentStatement(widget.shipmentId);
      final items = await widget.db.invoiceDao
          .getItemsWithDetailsByShipment(widget.shipmentId);

      if (!mounted) return;
      setState(() {
        _statement = statement;
        _linkedItems = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ أثناء تحميل البيانات: $e';
        _isLoading = false;
      });
    }
  }

  String _getPricingModeLabel(String mode) {
    switch (mode) {
      case ShipmentPricingMode.perUnit:
        return 'سعر للبرنيكة';
      case ShipmentPricingMode.lumpSum:
        return 'جملة (Lump Sum)';
      case ShipmentPricingMode.commission:
        return 'عمولة % من إجمالي البيع';
      default:
        return mode;
    }
  }

  Future<void> _showReassignSupplierDialog(ShipmentStatement st) async {
    final allSuppliers = await widget.db.supplierDao.getActiveSuppliers();
    final selectable = allSuppliers
        .where((s) => s.id != DefaultSupplier.unknownId)
        .toList();
    if (!mounted) return;

    final searchCtrl = TextEditingController();
    final selected = await showDialog<Supplier>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final query = searchCtrl.text;
          final filtered = selectable.where((s) {
            return ArabicNameNormalizer.matchesQuery(
              candidate: s.name,
              query: query,
              candidatePhone: s.phone,
            );
          }).toList();

          return AlertDialog(
            title: const Text('تعيين / تغيير المورد'),
            content: SizedBox(
              width: 400,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'بحث عن مورد',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const Gap(10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('لا يوجد موردون مطابقون'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final sup = filtered[index];
                              final isCurrent = sup.id == st.shipment.supplierId;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isCurrent
                                      ? Colors.green.withValues(
                                          alpha: Theme.of(ctx).brightness ==
                                                  Brightness.dark
                                              ? 0.22
                                              : 0.12,
                                        )
                                      : Colors.blue.withValues(
                                          alpha: Theme.of(ctx).brightness ==
                                                  Brightness.dark
                                              ? 0.22
                                              : 0.12,
                                        ),
                                  child: Icon(
                                    Icons.person,
                                    color: isCurrent ? Colors.green : Colors.blue,
                                  ),
                                ),
                                title: Text(
                                  sup.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: sup.phone != null && sup.phone!.isNotEmpty
                                    ? Text(sup.phone!)
                                    : null,
                                trailing: isCurrent
                                    ? const Icon(Icons.check_circle, color: Colors.green)
                                    : null,
                                onTap: () => Navigator.pop(ctx, sup),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
            ],
          );
        },
      ),
    );
    searchCtrl.dispose();

    if (selected == null) return;
    setState(() => _isBusy = true);
    try {
      await ShipmentSettlementService(widget.db).reassignSupplier(
        shipmentId: st.shipment.id,
        newSupplierId: selected.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تعيين المورد: ${selected.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تغيير المورد: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showToppingDialog(ShipmentStatement st) async {
    final countCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(
      text: st.shipment.toppingReason ?? '',
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل برانيك التكميل'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'المتبقي المتاح حالياً: ${st.remainingCount} برنيكة',
                style: TextStyle(
                  color: Theme.of(ctx).brightness == Brightness.dark
                      ? Colors.green.shade300
                      : Colors.green.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Gap(12),
              TextFormField(
                controller: countCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'عدد البرانيك المضافة للتكميل',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  final n = int.tryParse(val?.trim() ?? '');
                  if (n == null || n <= 0) {
                    return 'أدخل عدداً صحيحاً أكبر من 0';
                  }
                  if (n > st.remainingCount) {
                    return 'يتجاوز المتبقي المتاح (${st.remainingCount})';
                  }
                  return null;
                },
              ),
              const Gap(12),
              TextFormField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'السبب (بعلم المورد)',
                  hintText: 'مثال: تكميل وزن باقي البرانيك',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('حفظ التكميل'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      countCtrl.dispose();
      reasonCtrl.dispose();
      return;
    }

    final additional = int.parse(countCtrl.text.trim());
    final reason = reasonCtrl.text.trim();
    countCtrl.dispose();
    reasonCtrl.dispose();

    setState(() => _isBusy = true);
    try {
      await ShipmentAllocationService(
        widget.db.vegetableShipmentDao,
        widget.db.emptyBarnikaTrackingDao,
      ).recordTopping(
        shipmentId: st.shipment.id,
        additionalToppingCount: additional,
        reason: reason.isEmpty ? null : reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تسجيل $additional برنيكة تكميل'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showAddShipmentExpenseDialog(ShipmentStatement st) async {
    final descCtrl = TextEditingController(text: 'نولون شحنة #${st.shipment.shipmentNumber}');
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String category = 'نولون';
    String paymentMethod = 'cash';
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('إضافة مصروف على الشحنة #${st.shipment.shipmentNumber}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(
                      labelText: 'نوع المصروف',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'نولون', child: Text('نولون')),
                      DropdownMenuItem(value: 'مشال', child: Text('مشال / تنزيل')),
                      DropdownMenuItem(value: 'أخرى شحنة', child: Text('مصروف شحنة آخر')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          category = val;
                          if (descCtrl.text.startsWith('نولون') ||
                              descCtrl.text.startsWith('مشال')) {
                            descCtrl.text = '$val شحنة #${st.shipment.shipmentNumber}';
                          }
                        });
                      }
                    },
                  ),
                  const Gap(10),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'البيان',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'البيان مطلوب' : null,
                  ),
                  const Gap(10),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ (ج.م)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n <= 0) return 'أدخل مبلغاً صحيحاً';
                      return null;
                    },
                  ),
                  const Gap(10),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'طريقة الدفع',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('نقدي (كاش)')),
                      DropdownMenuItem(value: 'bank', child: Text('تحويل بنكي')),
                      DropdownMenuItem(value: 'card', child: Text('بطاقة')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => paymentMethod = v);
                    },
                  ),
                  const Gap(10),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('حفظ المصروف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      descCtrl.dispose();
      amountCtrl.dispose();
      notesCtrl.dispose();
      return;
    }

    final amount = double.parse(amountCtrl.text.trim());
    final desc = descCtrl.text.trim();
    final notes = notesCtrl.text.trim();
    descCtrl.dispose();
    amountCtrl.dispose();
    notesCtrl.dispose();

    setState(() => _isBusy = true);
    try {
      final now = DateTime.now();
      await widget.db.transaction(() async {
        await widget.db.expenseDao.insertExpense(
          ExpensesCompanion.insert(
            id: 'exp_${now.millisecondsSinceEpoch}_${st.shipment.id}',
            description: desc,
            amount: amount,
            date: Value(now),
            category: category,
            paymentMethod: Value(paymentMethod),
            supplierId: Value(st.shipment.supplierId),
            notes: Value(notes.isEmpty ? null : notes),
            shipmentId: Value(st.shipment.id),
            scope: const Value(ExpenseScope.shipment),
          ),
        );
        await widget.db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${now.millisecondsSinceEpoch}_shp_exp_${st.shipment.id}',
            entityType: 'Expense',
            refId: 'shipment_${st.shipment.id}',
            date: now,
            description: '$category: $desc',
            debit: const Value(0.0),
            credit: Value(amount),
            origin: 'expense',
            paymentMethod: Value(paymentMethod),
            receiptNumber:
                Value(ShipmentSettlementService.shipmentReceiptNumber(st.shipment.id)),
          ),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة مصروف الشحنة وخصمه من كشف المورد'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _confirmAndCloseShipment(ShipmentStatement st) async {
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('قفل الشحنة #${st.shipment.shipmentNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (st.hasUnknownSupplier)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(
                    alpha: Theme.of(ctx).brightness == Brightness.dark
                        ? 0.18
                        : 0.1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.amber),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        'تنبيه: المورد ما زال «مورد غير محدد». يفضل تعيين المورد الفعلي قبل قفل الشحنة.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(ctx).brightness == Brightness.dark
                              ? Colors.amber.shade200
                              : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Text('المورد: ${st.supplier?.name ?? "غير محدد"}'),
            const Gap(6),
            Text('إجمالي المبيعات (كاش + آجل): ${st.totalSales.toStringAsFixed(2)} ج.م'),
            Text('عمولة المحل: -${st.commissionAmount.toStringAsFixed(2)} ج.م'),
            Text('مصروفات الشحنة: -${st.shipmentExpenses.toStringAsFixed(2)} ج.م'),
            const Divider(),
            Text(
              'صافي مستحق المورد: ${st.netSupplierDue.toStringAsFixed(2)} ج.م',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.green,
              ),
            ),
            const Gap(12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظات الإقفال (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          if (st.hasUnknownSupplier)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx, false);
                await _showReassignSupplierDialog(st);
              },
              child: const Text('تعيين المورد أولاً'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.lock),
            label: const Text('تأكيد القفل والترحيل'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      notesCtrl.dispose();
      return;
    }

    final notes = notesCtrl.text.trim();
    notesCtrl.dispose();

    setState(() => _isBusy = true);
    try {
      await ShipmentSettlementService(widget.db).closeShipment(
        shipmentId: st.shipment.id,
        notes: notes.isEmpty ? null : notes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم قفل الشحنة وترحيل صافي المستحق لحساب المورد'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء قفل الشحنة: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showSupplierPaymentDialog(ShipmentStatement st) async {
    if (st.hasUnknownSupplier) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تعيين المورد الفعلي قبل تسجيل دفعة له'),
          backgroundColor: Colors.orange,
        ),
      );
      if (!st.isClosed) {
        await _showReassignSupplierDialog(st);
      }
      return;
    }

    final defaultAmount =
        st.remainingForShipment > 0 ? st.remainingForShipment : 0.0;
    final amountCtrl = TextEditingController(
      text: defaultAmount > 0 ? defaultAmount.toStringAsFixed(2) : '',
    );
    final notesCtrl = TextEditingController();
    String paymentMethod = 'cash';
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('سداد للمورد: ${st.supplier?.name ?? ""}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المتبقي على هذه الشحنة: ${st.remainingForShipment.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Gap(12),
                TextFormField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المدفوع (ج.م)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final n = double.tryParse(v?.trim() ?? '');
                    if (n == null || n <= 0) return 'أدخل مبلغاً أكبر من 0';
                    return null;
                  },
                ),
                const Gap(10),
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'طريقة السداد',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقدي (كاش)')),
                    DropdownMenuItem(value: 'bank', child: Text('تحويل بنكي')),
                    DropdownMenuItem(value: 'card', child: Text('بطاقة')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => paymentMethod = v);
                  },
                ),
                const Gap(10),
                TextFormField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('تسجيل الدفعة'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      amountCtrl.dispose();
      notesCtrl.dispose();
      return;
    }

    final amount = double.parse(amountCtrl.text.trim());
    final notes = notesCtrl.text.trim();
    amountCtrl.dispose();
    notesCtrl.dispose();

    setState(() => _isBusy = true);
    try {
      await ShipmentSettlementService(widget.db).recordSupplierPayment(
        supplierId: st.shipment.supplierId,
        amount: amount,
        shipmentId: st.shipment.id,
        paymentMethod: paymentMethod,
        notes: notes.isEmpty ? null : notes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تسجيل دفعة ${amount.toStringAsFixed(2)} ج.م للمورد'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الشحنة')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _statement == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الشحنة')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const Gap(16),
              Text(_error ?? 'خطأ غير معروف', style: theme.textTheme.titleMedium),
              const Gap(16),
              ElevatedButton(
                onPressed: _loadData,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final st = _statement!;
    final s = st.shipment;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('تفاصيل الشحنة #${s.shipmentNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isBusy ? null : _loadData,
            tooltip: 'تحديث',
          ),
          if (!st.isClosed)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'تعديل الشحنة',
              onPressed: _isBusy
                  ? null
                  : () async {
                      final updated = await showDialog<bool>(
                        context: context,
                        builder: (_) => ShipmentFormDialog(db: widget.db, shipment: s),
                      );
                      if (updated == true) {
                        _loadData();
                      }
                    },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header summary card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.local_shipping,
                            color: theme.colorScheme.primary,
                            size: 28,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'شحنة #${s.shipmentNumber}',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Gap(4),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'المورد: ${st.supplier?.name ?? DefaultSupplier.unknownName}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: st.hasUnknownSupplier
                                          ? (isDark
                                              ? Colors.orange.shade300
                                              : Colors.orange.shade900)
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (!st.isClosed)
                                    TextButton.icon(
                                      onPressed: _isBusy
                                          ? null
                                          : () => _showReassignSupplierDialog(st),
                                      icon: const Icon(Icons.swap_horiz, size: 16),
                                      label: Text(
                                        st.hasUnknownSupplier
                                            ? 'تعيين المورد'
                                            : 'تغيير المورد',
                                      ),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (st.supplier?.phone != null &&
                                  st.supplier!.phone!.isNotEmpty)
                                Text(
                                  'الهاتف: ${st.supplier!.phone}',
                                  style: theme.textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: st.isClosed
                                ? Colors.blueGrey.withValues(
                                    alpha: isDark ? 0.24 : 0.14,
                                  )
                                : (st.remainingCount > 0
                                    ? Colors.green.withValues(
                                        alpha: isDark ? 0.22 : 0.12,
                                      )
                                    : Colors.amber.withValues(
                                        alpha: isDark ? 0.22 : 0.12,
                                      )),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: st.isClosed
                                  ? Colors.blueGrey
                                  : (st.remainingCount > 0
                                      ? Colors.green
                                      : Colors.amber.shade700),
                            ),
                          ),
                          child: Text(
                            st.isClosed ? 'مقفولة' : 'مفتوحة',
                            style: TextStyle(
                              color: st.isClosed
                                  ? (isDark
                                      ? Colors.blueGrey.shade200
                                      : Colors.blueGrey.shade900)
                                  : (st.remainingCount > 0
                                      ? (isDark
                                          ? Colors.green.shade300
                                          : Colors.green.shade900)
                                      : (isDark
                                          ? Colors.amber.shade300
                                          : Colors.amber.shade900)),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 20,
                      runSpacing: 14,
                      children: [
                        _buildStatTile(
                          context,
                          label: 'تاريخ الاستلام',
                          value: DateFormat('yyyy/MM/dd HH:mm').format(s.date.toLocal()),
                          icon: Icons.calendar_month,
                        ),
                        if (s.closedAt != null)
                          _buildStatTile(
                            context,
                            label: 'تاريخ القفل',
                            value: DateFormat('yyyy/MM/dd HH:mm')
                                .format(s.closedAt!.toLocal()),
                            icon: Icons.lock_clock,
                          ),
                        _buildStatTile(
                          context,
                          label: 'نظام التسعير',
                          value: _getPricingModeLabel(s.pricingMode),
                          icon: Icons.sell,
                        ),
                        _buildStatTile(
                          context,
                          label: 'البرانيك (مستلم / مباع)',
                          value: '${st.soldCount} / ${st.totalReceived}',
                          subtitle: 'المتبقي: ${st.remainingCount} برنيكة',
                          icon: Icons.inventory_2,
                        ),
                        _buildStatTile(
                          context,
                          label: 'برانيك التكميل',
                          value: '${st.toppingCount} برنيكة',
                          subtitle: s.toppingReason,
                          icon: Icons.tune,
                        ),
                        if (s.pricingMode == ShipmentPricingMode.commission)
                          _buildStatTile(
                            context,
                            label: 'نسبة العمولة',
                            value:
                                '${st.commissionPercentage.toStringAsFixed(1)} %',
                            icon: Icons.percent,
                          ),
                      ],
                    ),
                    if (!st.isClosed) ...[
                      const Gap(14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isBusy || st.remainingCount <= 0
                                ? null
                                : () => _showToppingDialog(st),
                            icon: const Icon(Icons.add_box_outlined, size: 18),
                            label: const Text('تسجيل برانيك تكميل'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isBusy
                                ? null
                                : () => _showAddShipmentExpenseDialog(st),
                            icon: const Icon(Icons.receipt_outlined, size: 18),
                            label: const Text('+ مصروف شحنة (نولون)'),
                          ),
                        ],
                      ),
                    ],
                    if (s.notes != null && s.notes!.isNotEmpty) ...[
                      const Gap(12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(
                            alpha: isDark ? 0.16 : 0.08,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'ملاحظات: ${s.notes!}',
                          style: TextStyle(
                            color: isDark
                                ? Colors.amber.shade200
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Gap(16),

            // 2. Supplier Settlement Statement Card (كشف الشحنة للمورد)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calculate_outlined, color: Colors.teal),
                        const Gap(8),
                        Expanded(
                          child: Text(
                            'كشف الشحنة وحساب المورد',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _buildStatementRow(
                      'مبيعات الكاش',
                      '${st.cashSales.toStringAsFixed(2)} ج.م',
                    ),
                    _buildStatementRow(
                      'مبيعات الآجل',
                      '${st.creditSales.toStringAsFixed(2)} ج.م',
                    ),
                    _buildStatementRow(
                      'إجمالي مبيعات الشحنة',
                      '${st.totalSales.toStringAsFixed(2)} ج.م',
                      isBold: true,
                    ),
                    if (st.commissionAmount > 0 ||
                        s.pricingMode == ShipmentPricingMode.commission)
                      _buildStatementRow(
                        '− عمولة المحل (${st.commissionPercentage.toStringAsFixed(1)}%)',
                        '-${st.commissionAmount.toStringAsFixed(2)} ج.م',
                        valueColor: isDark
                            ? Colors.teal.shade200
                            : Colors.teal.shade800,
                      ),
                    _buildStatementRow(
                      '− مصروفات الشحنة (النولون/المشال)',
                      '-${st.shipmentExpenses.toStringAsFixed(2)} ج.م',
                      valueColor:
                          isDark ? Colors.red.shade300 : Colors.red.shade700,
                    ),
                    const Divider(height: 18),
                    _buildStatementRow(
                      'صافي مستحق المورد',
                      '${st.netSupplierDue.toStringAsFixed(2)} ج.م',
                      isBold: true,
                      fontSize: 16,
                      valueColor: isDark
                          ? Colors.indigo.shade200
                          : Colors.indigo.shade900,
                    ),
                    _buildStatementRow(
                      'المدفوع للمورد على الشحنة',
                      '${st.paidForShipment.toStringAsFixed(2)} ج.م',
                      valueColor: isDark
                          ? Colors.green.shade300
                          : Colors.green.shade800,
                    ),
                    _buildStatementRow(
                      'المتبقي للمورد على الشحنة',
                      '${st.remainingForShipment.toStringAsFixed(2)} ج.م',
                      isBold: true,
                      valueColor: st.remainingForShipment > 0.01
                          ? (isDark
                              ? Colors.deepOrange.shade300
                              : Colors.deepOrange.shade800)
                          : (isDark
                              ? Colors.green.shade300
                              : Colors.green.shade800),
                    ),
                    const Gap(14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (!st.isClosed)
                          ElevatedButton.icon(
                            onPressed: _isBusy
                                ? null
                                : () => _confirmAndCloseShipment(st),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('قفل الشحنة وترحيل للمورد'),
                          ),
                        ElevatedButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () => _showSupplierPaymentDialog(st),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('تسجيل دفعة للمورد'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // 3. Shipment Expenses Card (مصروفات الشحنة)
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'مصروفات الشحنة (${st.expenses.length})',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (!st.isClosed)
                          TextButton.icon(
                            onPressed: _isBusy
                                ? null
                                : () => _showAddShipmentExpenseDialog(st),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('إضافة مصروف'),
                          ),
                      ],
                    ),
                    const Divider(),
                    if (st.expenses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'لا توجد مصروفات مسجلة على هذه الشحنة حتى الآن',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: st.expenses.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final exp = st.expenses[idx];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.red.withValues(
                                alpha: isDark ? 0.2 : 0.1,
                              ),
                              child: Icon(
                                Icons.money_off,
                                size: 16,
                                color: isDark
                                    ? Colors.red.shade300
                                    : Colors.red.shade700,
                              ),
                            ),
                            title: Text(exp.description),
                            subtitle: Text(
                              '${exp.category} • ${DateFormat('yyyy/MM/dd HH:mm').format(exp.date.toLocal())}',
                            ),
                            trailing: Text(
                              '${exp.amount.toStringAsFixed(2)} ج.م',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.red.shade300
                                    : Colors.red.shade800,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // 4. Linked Invoices Header & List
            Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'المبيعات المنسوبة لهذه الشحنة (${_linkedItems.length} عنصر)',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'صافي المبيعات: ${st.totalSales.toStringAsFixed(2)} ج.م',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Gap(10),

            if (_linkedItems.isEmpty)
              Card(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 44,
                        color: Colors.grey.shade400,
                      ),
                      const Gap(8),
                      Text(
                        'لم يتم صرف أي مبيعات من هذه الشحنة حتى الآن',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _linkedItems.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _linkedItems[index].$1;
                    final invoice = _linkedItems[index].$2;
                    final product = _linkedItems[index].$3;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                      title: Text(
                        '${product?.name ?? "منتج #${item.productId}"} × ${item.quantity} برنيكة',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'فاتورة ${displayInvoiceNumber(invoice.invoiceNumber, invoice.id) ?? ''} | ${DateFormat('yyyy/MM/dd HH:mm').format(invoice.date.toLocal())} | العميل: ${invoice.customerName ?? "عميل نقدي"}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${(item.price * item.quantity).toStringAsFixed(2)} ج.م',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          if (item.commission > 0)
                            Text(
                              'عمولة: ${item.commission.toStringAsFixed(2)} ج.م',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.green.shade300
                                    : Colors.green.shade800,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatementRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 14,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(
    BuildContext context, {
    required String label,
    required String value,
    String? subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const Gap(8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.brightness == Brightness.dark
                        ? Colors.green.shade300
                        : Colors.green.shade800,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

