import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/ui/customer/services/enhanced_customer_statement_generator.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'customers_summary_widget.dart';
import '../../customer/add_edit_customer_page.dart';
import 'transaction_expansion_tile.dart';
import 'transaction_detail_dialog.dart';

class CustomerTransactionsWidget extends ConsumerStatefulWidget {
  final AppDatabase db;

  const CustomerTransactionsWidget({super.key, required this.db});

  @override
  ConsumerState<CustomerTransactionsWidget> createState() =>
      _CustomerTransactionsWidgetState();
}

class _CustomerTransactionsWidgetState
    extends ConsumerState<CustomerTransactionsWidget> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: StreamBuilder<List<Customer>>(
        stream: widget.db.customerDao.watchAllCustomers(),
        builder: (context, snapshot) {
          final slivers = <Widget>[
            SliverToBoxAdapter(child: CustomersSummaryWidget(db: widget.db)),
            const SliverToBoxAdapter(child: Gap(16)),
            SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        labelText: context.l10n.search_customer_hint,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const Gap(16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddEditCustomerPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_add),
                    label: Text(context.l10n.add_customer),
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: Gap(20)),
          ];

          if (snapshot.connectionState == ConnectionState.waiting) {
            slivers.add(
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
            );
            return CustomScrollView(slivers: slivers);
          }

          final allCustomers = snapshot.data ?? [];
          final query = _searchQuery.toLowerCase();
          final filteredCustomers = allCustomers.where((customer) {
            final name = customer.name.toLowerCase();
            final phone = (customer.phone ?? '').toLowerCase();
            return name.contains(query) || phone.contains(query);
          }).toList();

          if (filteredCustomers.isEmpty) {
            slivers.add(
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const Gap(16),
                      Text(context.l10n.no_customers),
                      Text(
                        context.l10n.add_new_customers_to_start,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            );
            return CustomScrollView(slivers: slivers);
          }

          slivers.add(
            SliverList.builder(
              itemCount: filteredCustomers.length,
              itemBuilder: (context, index) {
                final customer = filteredCustomers[index];
                return FutureBuilder<double>(
                  future: widget.db.ledgerDao.getCustomerBalance(customer.id),
                  builder: (context, balanceSnapshot) {
                    final balance = balanceSnapshot.data ?? 0.0;
                    return _CustomerTransactionCard(
                      customer: customer,
                      totalPurchases: balance > 0 ? balance : 0.0,
                      totalPaid: balance < 0 ? -balance : 0.0,
                      db: widget.db,
                    );
                  },
                );
              },
            ),
          );

          return CustomScrollView(slivers: slivers);
        },
      ),
    );
  }
}

class _CustomerTransactionCard extends StatefulWidget {
  final Customer customer;
  final double totalPurchases;
  final double totalPaid;
  final AppDatabase db;

  const _CustomerTransactionCard({
    required this.customer,
    required this.totalPurchases,
    required this.totalPaid,
    required this.db,
  });

  @override
  State<_CustomerTransactionCard> createState() =>
      _CustomerTransactionCardState();
}

class _CustomerTransactionCardState extends State<_CustomerTransactionCard> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isLoadingTransactions = false;
  List<LedgerTransaction> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadRecentTransactions();
  }

  Future<void> _loadRecentTransactions() async {
    setState(() => _isLoadingTransactions = true);
    try {
      // Get transactions with running balance for better display
      final transactionsWithBalance = await widget.db.ledgerDao
          .getTransactionsWithRunningBalance(
            'Customer',
            widget.customer.id,
            _startDate,
            _endDate,
          );

      setState(() {
        _transactions = transactionsWithBalance
            .map((tx) => tx.transaction)
            .toList()
            .reversed
            .toList();
        _isLoadingTransactions = false;
      });
    } catch (e) {
      setState(() => _isLoadingTransactions = false);
      debugPrint('Error loading transactions: $e');
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadRecentTransactions();
    }
  }

  void _showDetailDialog(BuildContext context, LedgerTransaction transaction) {
    showDialog(
      context: context,
      builder: (ctx) => TransactionDetailDialog(
        db: widget.db,
        transaction: transaction,
        entityType: 'Customer',
      ),
    );
  }

  void _showPaymentDialog(Customer customer) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('سداد قيمة للعميل: ${customer.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                border: OutlineInputBorder(),
                prefixText: 'ج.م ',
              ),
              keyboardType: TextInputType.number,
            ),
            const Gap(16),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'ملاحظة / سبب (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('الرجاء إدخال مبلغ صحيح'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              try {
                await widget.db.ledgerDao.insertTransaction(
                  LedgerTransactionsCompanion.insert(
                    id: '${DateTime.now().millisecondsSinceEpoch}_customer_payment',
                    entityType: 'Customer',
                    refId: customer.id,
                    date: DateTime.now(),
                    description: noteController.text.isNotEmpty
                        ? noteController.text
                        : 'سداد قيمة',
                    debit: const Value(0.0),
                    credit: Value(amount),
                    origin: 'payment',
                    paymentMethod: const Value('cash'),
                  ),
                );

                if (!mounted) return;
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _loadRecentTransactions();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تسجيل السداد بنجاح'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('خطأ في تسجيل السداد: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('تأكيد السداد'),
          ),
        ],
      ),
    );
  }

  void _exportCustomerReport(BuildContext context, Customer customer) async {
    try {
      // Get transactions with running balance for the selected date range
      final transactionsWithBalance = await widget.db.ledgerDao
          .getTransactionsWithRunningBalance(
            'Customer',
            customer.id,
            _startDate,
            _endDate,
          );

      final transactionData = transactionsWithBalance
          .map(
            (tx) => {
              'date': tx.transaction.date,
              'description': tx.transaction.description,
              'debit': tx.transaction.debit,
              'credit': tx.transaction.credit,
              'balance': tx.runningBalance, // Include running balance
              'receiptNumber': tx.transaction.receiptNumber,
              'paymentMethod': tx.transaction.paymentMethod,
            },
          )
          .toList();

      // Calculate opening balance before the selected period
      final openingBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        customer.id,
        upToDate: _startDate.subtract(const Duration(days: 1)),
      );

      final currentBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        customer.id,
        upToDate: _endDate,
      );

      final exportService = ExportService();
      await exportService.exportCustomerStatement(
        db: widget.db,
        customerName: customer.name,
        transactions: transactionData,
        openingBalance: openingBalance,
        currentBalance: currentBalance,
      );

      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير تقرير العميل: ${customer.name} بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير التقرير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _printCustomerStatement(BuildContext context, Customer customer) async {
    try {
      // Get transactions with running balance for the selected date range
      final transactionsWithBalance = await widget.db.ledgerDao
          .getTransactionsWithRunningBalance(
            'Customer',
            customer.id,
            _startDate,
            _endDate,
          );

      // Calculate opening balance before the selected period
      final openingBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        customer.id,
        upToDate: _startDate.subtract(const Duration(days: 1)),
      );

      final currentBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        customer.id,
        upToDate: _endDate,
      );

      // Use enhanced customer statement generator for better display
      await EnhancedCustomerStatementGenerator.generateStatement(
        db: widget.db,
        customerId: customer.id,
        customerName: customer.name,
        fromDate: _startDate,
        toDate: _endDate,
        openingBalance: openingBalance,
        currentBalance: currentBalance,
      );

      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم طباعة كشف حساب مختصر للعميل: ${customer.name} بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الطباعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEditCustomerDialog(BuildContext context, Customer customer) {
    final nameController = TextEditingController(text: customer.name);
    final phoneController = TextEditingController(text: customer.phone ?? '');
    final addressController = TextEditingController(
      text: customer.address ?? '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('تعديل بيانات العميل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم العميل',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    await widget.db.customerDao.updateCustomer(
                      CustomersCompanion(
                        id: Value(customer.id),
                        name: Value(nameController.text),
                        phone: phoneController.text.isNotEmpty
                            ? Value(phoneController.text)
                            : const Value.absent(),
                        address: addressController.text.isNotEmpty
                            ? Value(addressController.text)
                            : const Value.absent(),
                        status: const Value('Active'),
                        createdAt:
                            const Value.absent(), // Prevent createdAt update
                      ),
                    );

                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم تحديث بيانات العميل بنجاح'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('خطأ: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final remainingDebt = widget.totalPurchases - widget.totalPaid;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.1),
          child: Text(
            widget.customer.name.isNotEmpty
                ? widget.customer.name[0].toUpperCase()
                : '?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          widget.customer.name,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.customer.phone != null)
              Text(
                widget.customer.phone ?? '',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            const Gap(4),
            Text(
              'الرصيد الكلي: ${remainingDebt.toStringAsFixed(2)} ج.م',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: remainingDebt > 0 ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              remainingDebt >= 0 ? 'ديون مدين (لنا)' : 'دائن (علينا)',
              style: TextStyle(
                color: remainingDebt > 0 ? Colors.red : Colors.green,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${remainingDebt.toStringAsFixed(2)} ج.م',
              style: TextStyle(
                color: remainingDebt > 0 ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              remainingDebt >= 0 ? 'ديون مدين (لنا)' : 'دائن (علينا)',
              style: TextStyle(
                color: remainingDebt > 0 ? Colors.red : Colors.green,
                fontSize: 12,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Summary Cards
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: 150,
                        child: _SummaryCard(
                          title: 'إجمالي المشتريات',
                          value: widget.totalPurchases,
                          color: Colors.blue,
                          icon: Icons.shopping_cart,
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: _SummaryCard(
                          title: 'المدفوع',
                          value: widget.totalPaid,
                          color: Colors.green,
                          icon: Icons.payment,
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: _SummaryCard(
                          title: 'المتبقي',
                          value: remainingDebt,
                          color: remainingDebt > 0 ? Colors.red : Colors.green,
                          icon: remainingDebt > 0
                              ? Icons.money_off
                              : Icons.check_circle,
                        ),
                      ),
                    ],
                  ),

                  const Gap(20),

                  // Date Filter UI
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectDateRange(context),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.date_range,
                                  color: Colors.blue,
                                ),
                                const Gap(8),
                                Text(
                                  '${DateFormat('yyyy/MM/dd').format(_startDate)} - ${DateFormat('yyyy/MM/dd').format(_endDate)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Gap(16),
                      IconButton(
                        onPressed: _loadRecentTransactions,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'تحديث المعاملات',
                      ),
                    ],
                  ),

                  const Gap(20),

                  // Recent Transactions Table
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(8),
                              topRight: Radius.circular(8),
                            ),
                          ),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'التاريخ',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  'الوصف',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  'المبلغ',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  'الحالة',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isLoadingTransactions)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          )
                        else if (_transactions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('لا توجد معاملات في الفترة المحددة'),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 200,
                              maxHeight: 400,
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _transactions.length,
                              itemBuilder: (context, index) {
                                final transaction = _transactions[index];
                                final isSale = transaction.debit > 0;
                                final isPayment = transaction.credit > 0;

                                return TransactionExpansionTile(
                                  transaction: transaction,
                                  entityType: 'Customer',
                                  isPurchase: false,
                                  isSale: isSale,
                                  db: widget.db,
                                  onTap: () => _showDetailDialog(
                                    context, transaction),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _showPaymentDialog(widget.customer);
                          },
                          icon: const Icon(Icons.payments),
                          label: const Text('سداد قيمة'),
                        ),
                      ),
                      const Gap(16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _exportCustomerReport(context, widget.customer);
                          },
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('تصدير PDF'),
                        ),
                      ),
                      const Gap(16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _printCustomerStatement(context, widget.customer);
                          },
                          icon: const Icon(Icons.print),
                          label: const Text('طباعة'),
                        ),
                      ),
                    ],
                  ),
                  const Gap(16),
                  // Edit Customer Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _showEditCustomerDialog(context, widget.customer);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('تعديل بيانات العميل'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.blue.withValues(alpha: 0.1),
                        foregroundColor: Colors.blue,
                      ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const Gap(4),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
          const Gap(2),
          Text(
            '${value.toStringAsFixed(2)} ج.م',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
