import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import 'package:pos_offline_desktop/core/utils/currency_helper.dart';

class ExpensesReportScreen extends StatefulWidget {
  final AppDatabase db;

  const ExpensesReportScreen({super.key, required this.db});

  @override
  State<ExpensesReportScreen> createState() => _ExpensesReportScreenState();
}

class _ExpensesReportScreenState extends State<ExpensesReportScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  List<Expense> _expenses = [];
  List<Expense> _filteredExpenses = [];
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'الكل';

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExpenses() async {
    setState(() => _isLoading = true);

    try {
      final expenses =
          await (widget.db.select(widget.db.expenses)
                ..where((tbl) => tbl.date.isBetweenValues(_startDate, _endDate))
                ..orderBy([
                  (tbl) => OrderingTerm(
                    expression: tbl.date,
                    mode: OrderingMode.desc,
                  ),
                ]))
              .get();

      setState(() {
        _expenses = expenses;
        _filteredExpenses = expenses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في تحميل المصروفات: $e')));
      }
    }
  }

  void _filterExpenses() {
    setState(() {
      _filteredExpenses = _expenses.where((expense) {
        final matchesSearch = expense.description.toLowerCase().contains(
          _searchController.text.toLowerCase(),
        );
        final matchesCategory =
            _selectedCategory == 'الكل' ||
            expense.category == _selectedCategory;
        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  List<String> _getCategories() {
    final categories = _expenses
        .map((e) => e.category)
        .whereType<String>()
        .toSet()
        .toList();
    categories.insert(0, 'الكل');
    return categories;
  }

  double _getTotalExpenses() {
    return _filteredExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
  }

  Future<void> _exportToExcel() async {
    try {
      await ExportService.exportExpensesToExcel(
        _filteredExpenses,
        startDate: _startDate,
        endDate: _endDate,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تصدير التقرير بنجاح')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في التصدير: $e')));
      }
    }
  }

  Future<void> _printReport() async {
    try {
      final reportData = {
        'title': 'تقرير المصروفات',
        'period':
            '${DateFormat('yyyy-MM-dd').format(_startDate)} إلى ${DateFormat('yyyy-MM-dd').format(_endDate)}',
        'total': _getTotalExpenses(),
        'expenses': _filteredExpenses
            .map(
              (e) => {
                'date': DateFormat('yyyy-MM-dd').format(e.date),
                'description': e.description,
                'category': e.category,
                'amount': e.amount,
              },
            )
            .toList(),
      };

      await PrinterService.printExpensesReport(reportData);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم طباعة التقرير بنجاح')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير المصروفات'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printReport,
            tooltip: 'طباعة التقرير',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportToExcel,
            tooltip: 'تصدير إلى Excel',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        title: const Text('من تاريخ'),
                        subtitle: Text(
                          DateFormat('yyyy-MM-dd').format(_startDate),
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: _selectStartDate,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: ListTile(
                        title: const Text('إلى تاريخ'),
                        subtitle: Text(
                          DateFormat('yyyy-MM-dd').format(_endDate),
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: _selectEndDate,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const Gap(16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'البحث عن مصروف',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _filterExpenses(),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'التصنيف',
                          border: OutlineInputBorder(),
                        ),
                        items: _getCategories().map((category) {
                          return DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedCategory = value!);
                          _filterExpenses();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Summary Cards
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'إجمالي المصروفات',
                            style: TextStyle(fontSize: 16),
                          ),
                          const Gap(8),
                          Text(
                            CurrencyHelper.formatCurrency(_getTotalExpenses()),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'عدد المصروفات',
                            style: TextStyle(fontSize: 16),
                          ),
                          const Gap(8),
                          Text(
                            '${_filteredExpenses.length}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Expenses List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredExpenses.isEmpty
                ? const Center(child: Text('لا توجد مصروفات في الفترة المحددة'))
                : ListView.builder(
                    itemCount: _filteredExpenses.length,
                    itemBuilder: (context, index) {
                      final expense = _filteredExpenses[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.shade100,
                            child: Icon(
                              Icons.receipt_long,
                              color: Colors.red.shade700,
                            ),
                          ),
                          title: Text(
                            expense.description,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(expense.category),
                              Text(
                                DateFormat(
                                  'yyyy-MM-dd HH:mm',
                                ).format(expense.date),
                              ),
                            ],
                          ),
                          trailing: Text(
                            CurrencyHelper.formatCurrency(expense.amount),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() => _startDate = date);
      _loadExpenses();
    }
  }

  Future<void> _selectEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() => _endDate = date);
      _loadExpenses();
    }
  }
}
