import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/expenses_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/document_date_service.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/shipment_settlement_service.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/widgets/document_date_picker.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';

class ExpensePage extends StatefulWidget {
  final AppDatabase db;

  const ExpensePage({super.key, required this.db});

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedCategory = AppFeatures.hasShipmentTracking ? 'أكل / شاي' : 'rent';
  String _selectedPaymentMethod = 'cash';
  String _selectedScope = ExpenseScope.shop;
  int? _selectedShipmentId;
  String _scopeFilter = 'all'; // 'all' | ExpenseScope.shop | ExpenseScope.shipment
  DateTime _selectedDate = DateTime.now();
  List<Expense> _expenses = [];
  List<VegetableShipment> _shipments = [];
  Map<int, VegetableShipment> _shipmentsById = {};
  Map<String, Supplier> _suppliersById = {};
  bool _isLoading = false;
  final ExportService _exportService = ExportService();

  static const List<String> _baseCategories = [
    'rent',
    'electricity',
    'water',
    'internet',
    'salaries',
    'maintenance',
    'marketing',
    'other_expenses',
    'supplier_purchases',
  ];

  static const List<String> _vegetableShopCategories = [
    'أكل / شاي',
    'كهرباء',
    'إيجار',
    'عمالة / يومية',
    'أخرى محل',
  ];

  static const List<String> _vegetableShipmentCategories = [
    'نولون',
    'مشال',
    'أخرى شحنة',
  ];

  final List<String> _paymentMethods = ['cash', 'bank', 'card'];

  List<Supplier> _suppliers = [];
  Supplier? _selectedSupplier;

  List<String> get _activeCategories {
    if (!AppFeatures.hasShipmentTracking) return _baseCategories;
    return _selectedScope == ExpenseScope.shipment
        ? _vegetableShipmentCategories
        : _vegetableShopCategories;
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadSuppliers(),
      if (AppFeatures.hasShipmentTracking) _loadShipments(),
      _loadExpenses(),
    ]);
  }

  Future<void> _loadShipments() async {
    try {
      final all = await widget.db.vegetableShipmentDao.getAll();
      all.sort((a, b) {
        if (a.status != b.status) {
          return a.status == VegetableShipmentStatus.open ? -1 : 1;
        }
        return b.date.compareTo(a.date);
      });
      if (!mounted) return;
      setState(() {
        _shipments = all;
        _shipmentsById = {for (final s in all) s.id: s};
      });
    } catch (_) {}
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await widget.db.supplierDao.getAllSuppliers();
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _suppliersById = {for (final s in suppliers) s.id: s};
      });
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.error_loading_suppliers}: $e')),
        );
      }
    }
  }

  Future<void> _loadExpenses() async {
    setState(() => _isLoading = true);
    try {
      final expenses = await widget.db.expenseDao.getAllExpenses();
      expenses.sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.error_loading_expenses}: $e')),
      );
    }
  }

  Future<void> _addExpense() async {
    if (!_formKey.currentState!.validate()) return;

    if (AppFeatures.hasShipmentTracking &&
        _selectedScope == ExpenseScope.shipment &&
        _selectedShipmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر الشحنة المرتبطة بهذا المصروف أولاً'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final isDayOpen = await widget.db.dayDao.isDayOpen();
    if (!isDayOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يجب فتح يوم مالي أولاً'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
      final desc = _descriptionController.text.trim();
      final notes = _notesController.text.trim();
      final isShipmentScope =
          AppFeatures.hasShipmentTracking && _selectedScope == ExpenseScope.shipment;
      final linkedShipment =
          isShipmentScope ? _shipmentsById[_selectedShipmentId] : null;

      await widget.db.transaction(() async {
        await widget.db.expenseDao.insertExpense(
          ExpensesCompanion(
            description: Value(desc),
            amount: Value(amount),
            date: Value(_selectedDate),
            category: Value(_selectedCategory),
            paymentMethod: Value(_selectedPaymentMethod),
            supplierId: Value(
              isShipmentScope ? linkedShipment?.supplierId : _selectedSupplier?.id,
            ),
            notes: Value(notes.isEmpty ? null : notes),
            shipmentId: Value(isShipmentScope ? _selectedShipmentId : null),
            scope: Value(
              isShipmentScope ? ExpenseScope.shipment : ExpenseScope.shop,
            ),
          ),
        );

        // For shipment-scoped expenses, post under entityType='Expense' so we don't
        // double-adjust Supplier ledger (ShipmentSettlementService subtracts shipment
        // expenses before posting shp_settle_$id).
        final entityType = (!isShipmentScope && _selectedSupplier != null)
            ? 'Supplier'
            : 'Expense';
        final refId = isShipmentScope
            ? 'shipment_$_selectedShipmentId'
            : (_selectedSupplier?.id ?? 'general_expense');
        final receiptNo = isShipmentScope && _selectedShipmentId != null
            ? ShipmentSettlementService.shipmentReceiptNumber(_selectedShipmentId!)
            : null;

        await widget.db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${DateTime.now().millisecondsSinceEpoch}_expense',
            entityType: entityType,
            refId: refId,
            date: _selectedDate,
            description: '$_selectedCategory: $desc',
            debit: const Value(0.0),
            credit: Value(amount),
            origin: 'expense',
            paymentMethod: Value(_selectedPaymentMethod),
            receiptNumber: Value(receiptNo),
          ),
        );
      });

      _clearForm();
      await _loadExpenses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isShipmentScope
                  ? 'تم إضافة مصروف الشحنة وربطه بكشف المورد'
                  : 'تم إضافة المصروف بنجاح',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إضافة المصروف: $e')),
      );
    }
  }

  void _clearForm() {
    _descriptionController.clear();
    _amountController.clear();
    _notesController.clear();
    setState(() {
      _selectedScope = ExpenseScope.shop;
      _selectedShipmentId = null;
      _selectedSupplier = null;
      _selectedCategory =
          AppFeatures.hasShipmentTracking ? _vegetableShopCategories.first : 'rent';
      _selectedPaymentMethod = 'cash';
      _selectedDate = DateTime.now();
    });
  }

  String _getLocalizedCategory(String category, AppLocalizations l10n) {
    switch (category) {
      case 'rent':
        return l10n.rent;
      case 'electricity':
        return l10n.electricity;
      case 'water':
        return l10n.water;
      case 'internet':
        return l10n.internet;
      case 'salaries':
        return l10n.salaries;
      case 'maintenance':
        return l10n.maintenance;
      case 'marketing':
        return l10n.marketing;
      case 'other_expenses':
        return l10n.other_expenses;
      case 'supplier_purchases':
        return l10n.supplier_purchases;
      default:
        return category;
    }
  }

  String _getLocalizedPaymentMethod(String method, AppLocalizations l10n) {
    switch (method) {
      case 'cash':
        return l10n.cash;
      case 'bank':
        return l10n.bank;
      case 'card':
        return l10n.card;
      default:
        return method;
    }
  }

  List<Expense> get _filteredExpenses {
    if (!AppFeatures.hasShipmentTracking || _scopeFilter == 'all') {
      return _expenses;
    }
    return _expenses.where((e) => e.scope == _scopeFilter).toList();
  }

  Future<void> _exportToPDF() async {
    if (_expenses.isEmpty) return;

    await _exportService.exportToPDF(
      title: 'تقرير المصروفات',
      data: _expenses
          .map(
            (expense) => {
              'التاريخ': DateFormat('yyyy/MM/dd').format(expense.date),
              'الوصف': expense.description,
              'الفئة': expense.category,
              'النوع': expense.scope == ExpenseScope.shipment ? 'مصروف شحنة' : 'مصروف محل',
              'المبلغ': expense.amount.toStringAsFixed(2),
              'طريقة الدفع': expense.paymentMethod,
              'ملاحظات': expense.notes ?? '',
            },
          )
          .toList(),
      headers: [
        'التاريخ',
        'الوصف',
        'الفئة',
        'النوع',
        'المبلغ',
        'طريقة الدفع',
        'ملاحظات',
      ],
      columns: [
        'التاريخ',
        'الوصف',
        'الفئة',
        'النوع',
        'المبلغ',
        'طريقة الدفع',
        'ملاحظات',
      ],
      fileName:
          'expenses_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تصدير تقرير المصروفات')));
    }
  }

  Future<void> _exportToExcel() async {
    if (_expenses.isEmpty) return;

    await _exportService.exportToExcel(
      title: 'تقرير المصروفات',
      data: _expenses
          .map(
            (expense) => {
              'التاريخ': DateFormat('yyyy/MM/dd').format(expense.date),
              'الوصف': expense.description,
              'الفئة': expense.category,
              'النوع': expense.scope == ExpenseScope.shipment ? 'مصروف شحنة' : 'مصروف محل',
              'المبلغ': expense.amount,
              'طريقة الدفع': expense.paymentMethod,
              'ملاحظات': expense.notes ?? '',
            },
          )
          .toList(),
      headers: [
        'التاريخ',
        'الوصف',
        'الفئة',
        'النوع',
        'المبلغ',
        'طريقة الدفع',
        'ملاحظات',
      ],
      columns: [
        'التاريخ',
        'الوصف',
        'الفئة',
        'النوع',
        'المبلغ',
        'طريقة الدفع',
        'ملاحظات',
      ],
      fileName:
          'expenses_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تصدير تقرير المصروفات')));
    }
  }

  Future<void> _printDailyReport() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (date == null) return;

    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final dailyExpenses = await widget.db.expenseDao.getExpensesByDateRange(
      start,
      end,
    );

    if (dailyExpenses.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد مصروفات لهذا اليوم')),
        );
      }
      return;
    }

    await _exportService.exportToPDF(
      title:
          'تقرير المصروفات اليومي - ${DateFormat('yyyy/MM/dd').format(date)}',
      data: dailyExpenses
          .map(
            (expense) => {
              'التاريخ': DateFormat('HH:mm').format(expense.date),
              'الوصف': expense.description,
              'الفئة': expense.category,
              'المبلغ': expense.amount.toStringAsFixed(2),
              'طريقة الدفع': expense.paymentMethod,
              'ملاحظات': expense.notes ?? '',
            },
          )
          .toList(),
      headers: ['الوقت', 'الوصف', 'الفئة', 'المبلغ', 'طريقة الدفع', 'ملاحظات'],
      columns: ['الوقت', 'الوصف', 'الفئة', 'المبلغ', 'طريقة الدفع', 'ملاحظات'],
      fileName: 'daily_expenses_${DateFormat('yyyyMMdd').format(date)}',
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تصدير التقرير اليومي')));
    }
  }

  void _showExpenseDetails(Expense expense) {
    final l10n = AppLocalizations.of(context);
    final linkedShipment =
        expense.shipmentId != null ? _shipmentsById[expense.shipmentId!] : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(expense.description),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
              l10n.amount,
              '${expense.amount.toStringAsFixed(2)} ${l10n.currency}',
            ),
            const Divider(),
            _buildDetailRow(
              l10n.date,
              DateFormat('yyyy/MM/dd HH:mm').format(expense.date),
            ),
            if (AppFeatures.hasShipmentTracking)
              _buildDetailRow(
                'النطاق',
                expense.scope == ExpenseScope.shipment
                    ? 'مصروف على الشحنة${linkedShipment != null ? " (#${linkedShipment.shipmentNumber})" : ""}'
                    : 'مصروف عام على المحل',
              ),
            _buildDetailRow(
              l10n.category,
              _getLocalizedCategory(expense.category, l10n),
            ),
            _buildDetailRow(
              l10n.payment_method,
              _getLocalizedPaymentMethod(expense.paymentMethod, l10n),
            ),
            if (expense.supplierId != null)
              _buildDetailRow(
                l10n.suppliers,
                _suppliersById[expense.supplierId!]?.name ?? expense.supplierId!,
              ),
            if (expense.notes != null && expense.notes!.isNotEmpty)
              _buildDetailRow(l10n.notes_optional, expense.notes!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
          PermissionGuard(
            permission: Permission.editSettings,
            showUpgradePrompt: false,
            fallback: const SizedBox.shrink(),
            child: TextButton.icon(
              onPressed: () async {
                final picked = await pickDocumentDate(
                  context: context,
                  db: widget.db,
                  initialDate: expense.date,
                );
                if (picked != null) {
                  await DocumentDateService(widget.db).updateExpenseDate(
                    expenseId: expense.id,
                    newDate: picked,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    _loadExpenses();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم تعديل تاريخ المصروف بنجاح'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.edit_calendar, size: 18),
              label: const Text('تعديل التاريخ'),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
            ),
          ),
          PermissionGuard(
            permission: Permission.editSettings,
            showUpgradePrompt: false,
            fallback: const SizedBox.shrink(),
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteExpense(expense);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.delete),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteExpense(Expense expense) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete_confirmation),
        content: Text(l10n.confirm_delete_expense),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.db.expenseDao.deleteExpense(expense.id);
      _loadExpenses();
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildExpenseFormCard(AppLocalizations l10n) {
    final categories = _activeCategories;
    final currentCategory = categories.contains(_selectedCategory)
        ? _selectedCategory
        : categories.first;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.add_new_expense,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Gap(12),
              if (AppFeatures.hasShipmentTracking) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: ExpenseScope.shop,
                      label: Text('مصروف المحل'),
                      icon: Icon(Icons.storefront, size: 18),
                    ),
                    ButtonSegment<String>(
                      value: ExpenseScope.shipment,
                      label: Text('مصروف شحنة'),
                      icon: Icon(Icons.local_shipping, size: 18),
                    ),
                  ],
                  selected: {_selectedScope},
                  onSelectionChanged: (sel) {
                    final nextScope = sel.first;
                    setState(() {
                      _selectedScope = nextScope;
                      _selectedCategory = nextScope == ExpenseScope.shipment
                          ? _vegetableShipmentCategories.first
                          : _vegetableShopCategories.first;
                      if (nextScope == ExpenseScope.shop) {
                        _selectedShipmentId = null;
                      } else if (_selectedShipmentId == null &&
                          _shipments.isNotEmpty) {
                        _selectedShipmentId = _shipments.first.id;
                      }
                    });
                  },
                ),
                const Gap(12),
                if (_selectedScope == ExpenseScope.shipment) ...[
                  DropdownButtonFormField<int>(
                    initialValue: _selectedShipmentId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الشحنة المرتبطة (نولون / مشال)',
                      border: OutlineInputBorder(),
                    ),
                    items: _shipments.map((s) {
                      final supName = _suppliersById[s.supplierId]?.name ?? 'مورد';
                      final statusTag = s.status == VegetableShipmentStatus.closed
                          ? ' (مقفولة)'
                          : '';
                      return DropdownMenuItem<int>(
                        value: s.id,
                        child: Text(
                          'شحنة #${s.shipmentNumber} — $supName$statusTag',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedShipmentId = val),
                    validator: (val) {
                      if (_selectedScope == ExpenseScope.shipment && val == null) {
                        return 'اختر الشحنة';
                      }
                      return null;
                    },
                  ),
                  const Gap(12),
                ],
              ],
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: l10n.description,
                  hintText: AppFeatures.hasShipmentTracking
                      ? (_selectedScope == ExpenseScope.shipment
                          ? 'مثال: نولون العربية / مشال'
                          : 'مثال: شاي وقهوة / فاتورة كهرباء')
                      : null,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.please_fill_the_form;
                  }
                  return null;
                },
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l10n.amount,
                        border: const OutlineInputBorder(),
                        prefixText: '${l10n.currency} ',
                      ),
                      validator: (value) {
                        final parsed = double.tryParse(value?.trim() ?? '');
                        if (parsed == null || parsed <= 0) {
                          return l10n.enter_valid_total_amount;
                        }
                        return null;
                      },
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: TextFormField(
                      readOnly: true,
                      controller: TextEditingController(
                        text: DateFormat('yyyy/MM/dd').format(_selectedDate),
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.date,
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today),
                      ),
                      onTap: () async {
                        final date = await pickDocumentDate(
                          context: context,
                          db: widget.db,
                          initialDate: _selectedDate,
                        );
                        if (date != null) {
                          setState(() => _selectedDate = date);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: currentCategory,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.category,
                        border: const OutlineInputBorder(),
                      ),
                      items: categories.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(_getLocalizedCategory(category, l10n)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedCategory = value);
                        }
                      },
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedPaymentMethod,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.payment_method,
                        border: const OutlineInputBorder(),
                      ),
                      items: _paymentMethods.map((method) {
                        return DropdownMenuItem(
                          value: method,
                          child: Text(_getLocalizedPaymentMethod(method, l10n)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedPaymentMethod = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const Gap(12),
              if (!AppFeatures.hasShipmentTracking &&
                  (_selectedCategory == 'marketing' ||
                      _selectedCategory == 'other_expenses')) ...[
                DropdownButtonFormField<Supplier>(
                  initialValue: _selectedSupplier,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.select_supplier,
                    border: const OutlineInputBorder(),
                  ),
                  items: _suppliers.map((supplier) {
                    return DropdownMenuItem(
                      value: supplier,
                      child: Text(supplier.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedSupplier = value);
                  },
                ),
                const Gap(12),
              ],
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.notes_optional,
                  border: const OutlineInputBorder(),
                ),
              ),
              const Gap(16),
              PermissionGuard(
                permission: Permission.editSettings,
                showUpgradePrompt: false,
                fallback: const SizedBox.shrink(),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _addExpense,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.add_expense),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpensesListCard(AppLocalizations l10n, {required bool shrinkWrap}) {
    final visible = _filteredExpenses;
    final totalVisible =
        visible.fold<double>(0.0, (sum, expense) => sum + expense.amount);

    final listContent = visible.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text(l10n.no_expenses)),
          )
        : ListView.builder(
            shrinkWrap: shrinkWrap,
            physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final expense = visible[index];
              final isShip = expense.scope == ExpenseScope.shipment;
              final ship = expense.shipmentId != null
                  ? _shipmentsById[expense.shipmentId!]
                  : null;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  onTap: () => _showExpenseDetails(expense),
                  leading: CircleAvatar(
                    backgroundColor: _getCategoryColor(expense.category),
                    child: Icon(
                      _getCategoryIcon(expense.category),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    expense.description,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${DateFormat('yyyy/MM/dd').format(expense.date)} • ${_getLocalizedPaymentMethod(expense.paymentMethod, l10n)}',
                      ),
                      if (AppFeatures.hasShipmentTracking)
                        Builder(
                          builder: (context) {
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isShip
                                    ? Colors.orange.withValues(
                                        alpha: isDark ? 0.22 : 0.14,
                                      )
                                    : Colors.blueGrey.withValues(
                                        alpha: isDark ? 0.24 : 0.14,
                                      ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isShip
                                    ? 'شحنة${ship != null ? " #${ship.shipmentNumber}" : ""}'
                                    : 'محل',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isShip
                                      ? (isDark
                                          ? Colors.orange.shade200
                                          : Colors.orange.shade900)
                                      : (isDark
                                          ? Colors.blueGrey.shade200
                                          : Colors.blueGrey.shade900),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  trailing: Text(
                    '${expense.amount.toStringAsFixed(2)} ${l10n.currency}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              );
            },
          );

    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.expenses,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${l10n.total_colon} ${totalVisible.toStringAsFixed(2)} ${l10n.currency}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
          if (AppFeatures.hasShipmentTracking)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('الكل'),
                      selected: _scopeFilter == 'all',
                      onSelected: (_) => setState(() => _scopeFilter = 'all'),
                    ),
                    ChoiceChip(
                      label: const Text('مصروف المحل'),
                      selected: _scopeFilter == ExpenseScope.shop,
                      onSelected: (_) =>
                          setState(() => _scopeFilter = ExpenseScope.shop),
                    ),
                    ChoiceChip(
                      label: const Text('مصروف الشحنة'),
                      selected: _scopeFilter == ExpenseScope.shipment,
                      onSelected: (_) =>
                          setState(() => _scopeFilter = ExpenseScope.shipment),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(),
          if (shrinkWrap) listContent else Expanded(child: listContent),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.expense_management),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printDailyReport,
            tooltip: l10n.print,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportToPDF,
            tooltip: l10n.export_to_pdf,
          ),
          IconButton(
            icon: const Icon(Icons.table_chart),
            onPressed: _exportToExcel,
            tooltip: 'تصدير الكل Excel',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 800) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  _buildExpenseFormCard(l10n),
                  _buildExpensesListCard(l10n, shrinkWrap: true),
                ],
              ),
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: SingleChildScrollView(
                  child: _buildExpenseFormCard(l10n),
                ),
              ),
              Expanded(
                flex: 2,
                child: _buildExpensesListCard(l10n, shrinkWrap: false),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'rent':
      case 'إيجار':
        return Colors.red;
      case 'electricity':
      case 'كهرباء':
        return Colors.orange;
      case 'water':
        return Colors.blue;
      case 'internet':
        return Colors.purple;
      case 'salaries':
      case 'عمالة / يومية':
        return Colors.green;
      case 'maintenance':
        return Colors.brown;
      case 'marketing':
      case 'نولون':
        return Colors.deepOrange;
      case 'مشال':
      case 'أخرى شحنة':
        return Colors.amber.shade800;
      case 'أكل / شاي':
        return Colors.teal;
      case 'other_expenses':
      case 'أخرى محل':
        return Colors.grey;
      default:
        return Colors.indigo;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'rent':
      case 'إيجار':
        return Icons.home;
      case 'electricity':
      case 'كهرباء':
        return Icons.bolt;
      case 'water':
        return Icons.water_drop;
      case 'internet':
        return Icons.wifi;
      case 'salaries':
      case 'عمالة / يومية':
        return Icons.attach_money;
      case 'maintenance':
        return Icons.build;
      case 'marketing':
      case 'نولون':
        return Icons.local_shipping;
      case 'مشال':
        return Icons.handyman;
      case 'أكل / شاي':
        return Icons.local_cafe;
      case 'other_expenses':
      case 'أخرى محل':
      case 'أخرى شحنة':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }
}

