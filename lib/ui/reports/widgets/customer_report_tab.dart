import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:intl/intl.dart';
import 'customer_monthly_report_page.dart';

class CustomerReportTab extends StatefulWidget {
  final AppDatabase db;

  const CustomerReportTab({super.key, required this.db});

  @override
  State<CustomerReportTab> createState() => _CustomerReportTabState();
}

class _CustomerReportTabState extends State<CustomerReportTab> {
  List<CustomerWithBalance> _customers = [];
  List<CustomerWithBalance> _filteredCustomers = [];
  bool _isLoading = false;
  bool _showOnlyDues = false;
  DateTime _reportStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _reportEnd = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final TextEditingController _searchController = TextEditingController();
  final ExportService _exportService = ExportService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final customers = await widget.db.customerDao.getAllCustomers();
      final List<CustomerWithBalance> result = [];

      for (final customer in customers) {
        // use getCustomerBalance from LedgerDao
        // Note: LedgerDao returns Debit - Credit.
        // Debit = Sales, Credit = Payments.
        // Balance = Sales - Payments.
        // Positive = They owe us (Receivable).
        // Negative = We owe them (Payable).
        final rawBalance = await widget.db.ledgerDao.getCustomerBalance(
          customer.id,
        );
        // Add opening balance from Customer entity
        final totalBalance = rawBalance + customer.openingBalance;

        result.add(
          CustomerWithBalance(customer: customer, balance: totalBalance),
        );
      }

      setState(() {
        _customers = result;
        _filteredCustomers = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.error_loading_data_with_error(e)),
          ),
        );
      }
    }
  }

  void _filterCustomers() {
    setState(() {
      _filteredCustomers = _customers.where((customer) {
        // Apply search filter
        final matchesSearch =
            _searchController.text.isEmpty ||
            customer.customer.name.toLowerCase().contains(
              _searchController.text.toLowerCase(),
            ) ||
            (customer.customer.phone?.toLowerCase().contains(
                  _searchController.text.toLowerCase(),
                ) ??
                false);

        // Apply dues filter
        final hasDues = customer.balance > 0;
        final passesDuesFilter = !_showOnlyDues || hasDues;

        return matchesSearch && passesDuesFilter;
      }).toList();
    });
  }

  Future<void> _exportPDF() async {
    try {
      final customersToExport = _showOnlyDues
          ? _filteredCustomers.where((c) => c.balance > 0).toList()
          : _filteredCustomers;

      final data = customersToExport.map((c) {
        return {
          'name': c.customer.name,
          'phone': c.customer.phone ?? '',
          'balance':
              c.balance, // This will trigger red coloring for positive values
        };
      }).toList();

      await _exportService.exportToPDF(
        title: context.l10n.customer_balances_tab,
        data: data,
        headers: [
          context.l10n.customer,
          context.l10n.phone,
          context.l10n.receivable_balance,
        ],
        columns: [
          'name',
          'phone',
          'balance',
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    }
  }






  Future<void> _exportExcel() async {
    try {
      final customersToExport = _showOnlyDues
          ? _filteredCustomers.where((c) => c.balance > 0).toList()
          : _filteredCustomers;

      final data = customersToExport.map((c) {
        return {
          context.l10n.customer: c.customer.name,
          context.l10n.phone: c.customer.phone ?? '',
          context.l10n.receivable_balance: c.balance,
        };
      }).toList();

      await _exportService.exportToExcel(
        title: context.l10n.customer_balances_tab,
        data: data,
        headers: [
          context.l10n.customer,
          context.l10n.phone,
          context.l10n.receivable_balance,
        ],
        columns: [
          context.l10n.customer,
          context.l10n.phone,
          context.l10n.receivable_balance,
        ],
        fileName:
            'customers_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    }
  }

  Future<void> _showStatementDialog(Customer customer) async {
    DateTime start = DateTime.now().subtract(const Duration(days: 30));
    DateTime end = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('كشف حساب: ${customer.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('الفترة'),
                    subtitle: Text(
                      '${DateFormat('yyyy/MM/dd').format(start)} - ${DateFormat('yyyy/MM/dd').format(end)}',
                    ),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: DateTimeRange(start: start, end: end),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          start = picked.start;
                          end = picked.end;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _exportStatement(customer, start, end);
                  },
                  icon: const Icon(Icons.print),
                  label: const Text('طباعة الكشف'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportStatement(
    Customer customer,
    DateTime start,
    DateTime end,
  ) async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch transactions with running balance
      final transactions = await widget.db.ledgerDao
          .getTransactionsWithRunningBalance(
            'Customer',
            customer.id,
            start,
            end,
          );

      // 2. Map to format expected by ExportService
      final mappedTransactions = transactions.map((tb) {
        final t = tb.transaction;
        return {
          'date': t.date,
          'receiptNumber': t.id.substring(0, 8), // Short ID
          'description': t.description,
          'debit': t.debit,
          'credit': t.credit,
          'balance': tb.runningBalance,
        };
      }).toList();

      // 3. Get opening balance (balance before start date)
      // The first running balance includes the transaction effect.
      // So opening balance = first running balance - (firstDebit - firstCredit) ?
      // actually getTransactionsWithRunningBalance handles internal logic.
      // But we need to pass strict opening/current balance to export function if it asks for it.
      // ExportService asks for 'openingBalance' and 'currentBalance'.
      // We can calculate them from the fetched data or re-query.
      final openingBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        customer.id,
        upToDate: start.subtract(const Duration(days: 1)),
      );

      final currentBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        customer.id,
        upToDate: end,
      );

      // 4. Export
      await _exportService.exportCustomerStatement(
        db: widget.db,
        customerName: customer.name,
        transactions: mappedTransactions,
        openingBalance: openingBalance,
        currentBalance: currentBalance,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate totals from filtered customers
    final totalDue = _filteredCustomers.fold(
      0.0,
      (sum, item) => sum + (item.balance > 0 ? item.balance : 0),
    );
    final totalCredited = _filteredCustomers.fold(
      0.0,
      (sum, item) => sum + (item.balance < 0 ? -item.balance : 0),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('تقرير العملاء'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: Theme.of(context).appBarTheme.elevation,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search Bar
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'البحث عن عميل...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        suffixIcon: _showOnlyDues
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'فقط المدينين',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      onChanged: (value) => _filterCustomers(),
                    ),
                    if (_showOnlyDues)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.filter_list,
                              color: Colors.orange,
                              size: 16,
                            ),
                            const Gap(4),
                            Text(
                              'يتم عرض العملاء المدينين فقط',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CustomerMonthlyReportPage(
                              db: widget.db,
                              start: _reportStart,
                              end: _reportEnd,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.assessment),
                      label: const Text('تقرير كامل مع الحركات'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC9A84C),
                        foregroundColor: Colors.black87,
                      ),
                    ),
                    const Gap(8),
                    ElevatedButton.icon(
                      onPressed: _exportPDF,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(context.l10n.pdf_label),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const Gap(8),
                    ElevatedButton.icon(
                      onPressed: _exportExcel,
                      icon: const Icon(Icons.table_chart),
                      label: Text(context.l10n.excel_label),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // Date Range Selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.date_range, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'الفترة: ${DateFormat('yyyy/MM/dd').format(_reportStart)} - ${DateFormat('yyyy/MM/dd').format(_reportEnd)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: DateTimeRange(
                            start: _reportStart, end: _reportEnd),
                        );
                        if (picked != null) {
                          setState(() {
                            _reportStart = picked.start;
                            _reportEnd = picked.end;
                          });
                        }
                      },
                      icon: const Icon(Icons.edit_calendar, size: 18),
                      label: const Text('تغيير الفترة'),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // Summary Cards
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showOnlyDues = !_showOnlyDues;
                        _filterCustomers();
                      });
                    },
                    child: _SummaryCard(
                      title: context.l10n.total_receivables_us,
                      value: totalDue,
                      color: _showOnlyDues ? Colors.orange : Colors.red,
                      icon: Icons.trending_up,
                    ),
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showOnlyDues = false;
                        _filterCustomers();
                      });
                    },
                    child: _SummaryCard(
                      title: context.l10n.total_payables_us,
                      value: totalCredited,
                      color: Colors.green,
                      icon: Icons.trending_down,
                    ),
                  ),
                ),
                const Gap(16),
                Expanded(child: Container()), // Spacer
              ],
            ),
            const Gap(16),

            // Data Table
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : List.from(_filteredCustomers).isEmpty
                  ? Center(child: Text(context.l10n.no_customers))
                  : SingleChildScrollView(
                      child: SizedBox(
                        width: double.infinity,
                        child: Card(
                          child: DataTable(
                            showCheckboxColumn: false, // Make rows clickable
                            headingRowColor: WidgetStateProperty.all(
                              Colors.purple.withValues(alpha: 0.05),
                            ),
                            columns: [
                              DataColumn(label: Text(context.l10n.customer)),
                              DataColumn(label: Text(context.l10n.phone)),
                              DataColumn(
                                label: Text(
                                  context.l10n.receivable_balance,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            rows: _filteredCustomers.map((c) {
                              return DataRow(
                                onSelectChanged: (selected) {
                                  if (selected == true) {
                                    _showStatementDialog(c.customer);
                                  }
                                },
                                cells: [
                                  DataCell(Text(c.customer.name)),
                                  DataCell(Text(c.customer.phone ?? '')),
                                  DataCell(
                                    Text(
                                      '${c.balance.toStringAsFixed(2)} ${context.l10n.currency_symbol}',
                                      style: TextStyle(
                                        color: c.balance > 0
                                            ? Colors.red
                                            : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerWithBalance {
  final Customer customer;
  final double balance;

  CustomerWithBalance({required this.customer, required this.balance});
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const Gap(16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
                Text(
                  '${value.toStringAsFixed(2)} ${context.l10n.currency_symbol}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
