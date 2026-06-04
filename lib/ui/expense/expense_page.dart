import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
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
  String _selectedCategory = 'rent';
  String _selectedPaymentMethod = 'cash';
  DateTime _selectedDate = DateTime.now();
  List<Expense> _expenses = [];
  bool _isLoading = false;
  final ExportService _exportService = ExportService();

  final List<String> _categories = [
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

  final List<String> _paymentMethods = ['cash', 'bank', 'card'];

  List<Supplier> _suppliers = [];
  List<Supplier> filteredSuppliers = [];
  Supplier? _selectedSupplier;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _loadExpenses();
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await widget.db.supplierDao.getAllSuppliers();
      setState(() {
        _suppliers = suppliers;
        filteredSuppliers = suppliers;
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
      setState(() {
        _expenses = expenses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.error_loading_expenses}: $e')),
        );
      }
    }
  }

  Future<void> _addExpense() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await widget.db.expenseDao.insertExpense(
        ExpensesCompanion(
          description: Value(_descriptionController.text),
          amount: Value(double.tryParse(_amountController.text) ?? 0.0),
          date: Value(_selectedDate),
          category: Value(_selectedCategory),
          paymentMethod: Value(_selectedPaymentMethod),
          notes: Value(
            _notesController.text.isEmpty ? null : _notesController.text,
          ),
        ),
      );

      // Always add to ledger for tracking financial flow
      await widget.db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_expense',
          entityType: _selectedSupplier != null ? 'Supplier' : 'Expense',
          refId: _selectedSupplier?.id ?? 'general_expense',
          date: _selectedDate,
          description: '$_selectedCategory: ${_descriptionController.text}',
          debit: const Value(0.0), // Expense is a credit (money out)
          credit: Value(double.tryParse(_amountController.text) ?? 0.0),
          origin: 'expense',
          paymentMethod: Value(_selectedPaymentMethod),
        ),
      );

      _clearForm();
      await _loadExpenses();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إضافة المصروف بنجاح')));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في إضافة المصروف: $e')));
      }
    }
  }

  void _clearForm() {
    _descriptionController.clear();
    _amountController.clear();
    _notesController.clear();
    setState(() {
      _selectedCategory = 'rent';
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
        'المبلغ',
        'طريقة الدفع',
        'ملاحظات',
      ],
      columns: [
        'التاريخ',
        'الوصف',
        'الفئة',
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
        'المبلغ',
        'طريقة الدفع',
        'ملاحظات',
      ],
      columns: [
        'التاريخ',
        'الوصف',
        'الفئة',
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

    // Fetch expenses for that day
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

    // Generate PDF for the day
    await _exportService.exportToPDF(
      title:
          'تقرير المصروفات اليومي - ${DateFormat('yyyy/MM/dd').format(date)}',
      data: dailyExpenses
          .map(
            (expense) => {
              'التاريخ': DateFormat(
                'HH:mm',
              ).format(expense.date), // Time only for daily
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
            _buildDetailRow(
              l10n.category,
              _getLocalizedCategory(expense.category, l10n),
            ),
            _buildDetailRow(
              l10n.payment_method,
              _getLocalizedPaymentMethod(expense.paymentMethod, l10n),
            ),
            if (expense.supplierId != null)
              _buildDetailRow(l10n.suppliers, expense.supplierId!),
            if (expense.notes != null && expense.notes!.isNotEmpty)
              _buildDetailRow(l10n.notes_optional, expense.notes!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
          TextButton(
            onPressed: () {
              // Delete Logic?
              // Ideally check simple delete
              Navigator.pop(context); // Close details
              _deleteExpense(expense);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadExpenses),
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
      body: Row(
        children: [
          // Add Expense Form
          Expanded(
            flex: 1,
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.add_new_expense,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Gap(16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: l10n.description,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
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
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: l10n.amount,
                                border: const OutlineInputBorder(),
                                prefixText: '${l10n.currency} ',
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.enter_valid_total_amount;
                                }
                                if (double.tryParse(value) == null) {
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
                                text: DateFormat(
                                  'yyyy/MM/dd',
                                ).format(_selectedDate),
                              ),
                              decoration: InputDecoration(
                                labelText: l10n.date,
                                border: const OutlineInputBorder(),
                                suffixIcon: const Icon(Icons.calendar_today),
                              ),
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: Colors
                                              .grey, // Header background and selected date
                                          onPrimary:
                                              Colors.white, // Header text color
                                          surface: Colors
                                              .white, // Calendar background
                                          onSurface: Colors
                                              .black, // Calendar text color
                                        ),
                                        textButtonTheme: TextButtonThemeData(
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors
                                                .black, // Button text color
                                          ),
                                        ),
                                        dialogTheme: const DialogThemeData(
                                          backgroundColor: Colors.white,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
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
                              initialValue: _selectedCategory,
                              decoration: InputDecoration(
                                labelText: l10n.category,
                                border: const OutlineInputBorder(),
                              ),
                              items: _categories.map((category) {
                                return DropdownMenuItem(
                                  value: category,
                                  child: Text(
                                    _getLocalizedCategory(category, l10n),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => _selectedCategory = value!);
                              },
                            ),
                          ),
                          const Gap(12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedPaymentMethod,
                              decoration: InputDecoration(
                                labelText: l10n.payment_method,
                                border: const OutlineInputBorder(),
                              ),
                              items: _paymentMethods.map((method) {
                                return DropdownMenuItem(
                                  value: method,
                                  child: Text(
                                    _getLocalizedPaymentMethod(method, l10n),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => _selectedPaymentMethod = value!);
                              },
                            ),
                          ),
                        ],
                      ),
                      const Gap(12),
                      if (_selectedCategory == 'marketing' ||
                          _selectedCategory == 'other_expenses') ...[
                        // Supplier dropdown for purchases
                        const SizedBox(height: 8),
                        Text(
                          l10n.supplier_colon,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<Supplier>(
                            initialValue: _selectedSupplier,
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
                        ),
                      ],
                      TextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l10n.notes_optional,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const Gap(20),
                      PermissionGuard(
                        permission: Permission.editSettings,
                        showUpgradePrompt: false,
                        fallback: const SizedBox.shrink(),
                        child: SizedBox(
                          width: double.infinity,
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
            ),
          ),
          // Expenses List
          Expanded(
            flex: 2,
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.expenses,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${l10n.total_colon} ${_expenses.fold<double>(0.0, (sum, expense) => sum + expense.amount).toStringAsFixed(2)} ${l10n.currency}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: _expenses.isEmpty
                        ? Center(child: Text(l10n.no_expenses))
                        : ListView.builder(
                            itemCount: _expenses.length,
                            itemBuilder: (context, index) {
                              final expense = _expenses[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  onTap: () => _showExpenseDetails(expense),
                                  leading: CircleAvatar(
                                    backgroundColor: _getCategoryColor(
                                      expense.category,
                                    ),
                                    child: Icon(
                                      _getCategoryIcon(expense.category),
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(expense.description),
                                  subtitle: Text(
                                    '${DateFormat('yyyy/MM/dd').format(expense.date)} • ${_getLocalizedPaymentMethod(expense.paymentMethod, l10n)}',
                                  ),
                                  trailing: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${expense.amount.toStringAsFixed(2)} ${l10n.currency}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (expense.notes != null &&
                                          expense.notes!.isNotEmpty)
                                        Text(
                                          expense.notes!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'إيجار':
        return Colors.red;
      case 'كهرباء':
        return Colors.orange;
      case 'مياه':
        return Colors.blue;
      case 'إنترنت':
        return Colors.purple;
      case 'رواتب':
        return Colors.green;
      case 'صيانة':
        return Colors.brown;
      case 'تسويق':
        return Colors.teal;
      case 'مصاريف أخرى':
        return Colors.grey;
      default:
        return Colors.indigo;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'إيجار':
        return Icons.home;
      case 'كهرباء':
        return Icons.local_gas_station;
      case 'مياه':
        return Icons.water_drop;
      case 'إنترنت':
        return Icons.wifi;
      case 'رواتب':
        return Icons.attach_money;
      case 'صيانة':
        return Icons.build;
      case 'تسويق':
        return Icons.handshake;
      case 'مصاريف أخرى':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }
}
