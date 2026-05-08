import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/backup_service.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';
import 'dart:async';

class CloseDayDialog extends ConsumerStatefulWidget {
  const CloseDayDialog({super.key});

  @override
  ConsumerState<CloseDayDialog> createState() => _CloseDayDialogState();
}

class _CloseDayDialogState extends ConsumerState<CloseDayDialog> {
  final _formKey = GlobalKey<FormState>();
  final _actualBalanceController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _daySummary;
  double _expectedBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDaySummary();
    _actualBalanceController.addListener(_calculateDifference);
  }

  @override
  void dispose() {
    _actualBalanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDaySummary() async {
    setState(() => _isLoading = true);

    try {
      final db = ref.read(appDatabaseProvider);
      final today = await db.dayDao.getTodayDay();

      if (today == null) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد يوم مفتوح لإقفاله'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Calculate day totals
      final summary = await _calculateDayTotals(db);

      setState(() {
        _daySummary = summary;
        _expectedBalance = summary['expected_balance'] as double;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل ملخص اليوم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _calculateDayTotals(AppDatabase db) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      // Sales totals
      final salesResult = await db
          .customSelect(
            '''
        SELECT 
          SUM(CASE WHEN payment_method = 'cash' THEN total_amount ELSE 0 END) as cash_sales,
          SUM(CASE WHEN payment_method != 'cash' THEN total_amount ELSE 0 END) as credit_sales,
          SUM(total_amount) as total_sales
        FROM invoices 
        WHERE created_at >= ? AND created_at <= ? AND status = 'active'
      ''',
            variables: [
              drift.Variable.withDateTime(startOfDay),
              drift.Variable.withDateTime(endOfDay),
            ],
          )
          .getSingle();

      // Purchase totals
      final purchasesResult = await db
          .customSelect(
            '''
        SELECT 
          SUM(CASE WHEN payment_method = 'cash' THEN total_amount ELSE 0 END) as cash_purchases,
          SUM(CASE WHEN payment_method != 'cash' THEN total_amount ELSE 0 END) as credit_purchases,
          SUM(total_amount) as total_purchases
        FROM purchases 
        WHERE purchase_date >= ? AND purchase_date <= ? AND is_deleted = 0
      ''',
            variables: [
              drift.Variable.withDateTime(startOfDay),
              drift.Variable.withDateTime(endOfDay),
            ],
          )
          .getSingle();

      // Customer payments
      final customerPaymentsResult = await db
          .customSelect(
            '''
        SELECT SUM(debit) as total_payments
        FROM ledger_transactions 
        WHERE entity_type = 'Customer' AND date >= ? AND date <= ?
      ''',
            variables: [
              drift.Variable.withDateTime(startOfDay),
              drift.Variable.withDateTime(endOfDay),
            ],
          )
          .getSingle();

      // Supplier payments
      final supplierPaymentsResult = await db
          .customSelect(
            '''
        SELECT SUM(debit) as total_payments
        FROM ledger_transactions 
        WHERE entity_type = 'Supplier' AND date >= ? AND date <= ?
      ''',
            variables: [
              drift.Variable.withDateTime(startOfDay),
              drift.Variable.withDateTime(endOfDay),
            ],
          )
          .getSingle();

      // Expenses
      final expensesResult = await db
          .customSelect(
            '''
        SELECT SUM(amount) as total_expenses
        FROM expenses 
        WHERE created_at >= ? AND created_at <= ?
      ''',
            variables: [
              drift.Variable.withDateTime(startOfDay),
              drift.Variable.withDateTime(endOfDay),
            ],
          )
          .getSingle();

      final cashSales = salesResult.read<double>('cash_sales');
      final creditSales = salesResult.read<double>('credit_sales');
      final totalSales = salesResult.read<double>('total_sales');

      final cashPurchases = purchasesResult.read<double>('cash_purchases');
      final creditPurchases = purchasesResult.read<double>('credit_purchases');
      final totalPurchases = purchasesResult.read<double>('total_purchases');

      final customerPayments = customerPaymentsResult.read<double>(
        'total_payments',
      );
      final supplierPayments = supplierPaymentsResult.read<double>(
        'total_payments',
      );
      final expenses = expensesResult.read<double>('total_expenses');

      // Get opening balance
      final today = await db.dayDao.getTodayDay();
      final openingBalance = today?['opening_balance'] as double?;

      // Calculate expected balance
      final expectedBalance =
          (openingBalance ?? 0.0) +
          cashSales +
          customerPayments -
          cashPurchases -
          supplierPayments -
          expenses;

      return {
        'opening_balance': openingBalance,
        'cash_sales': cashSales,
        'credit_sales': creditSales,
        'total_sales': totalSales,
        'cash_purchases': cashPurchases,
        'credit_purchases': creditPurchases,
        'total_purchases': totalPurchases,
        'customer_payments': customerPayments,
        'supplier_payments': supplierPayments,
        'expenses': expenses,
        'expected_balance': expectedBalance,
      };
    } catch (e) {
      // Return default values on error
      return {
        'opening_balance': 0.0,
        'cash_sales': 0.0,
        'credit_sales': 0.0,
        'total_sales': 0.0,
        'cash_purchases': 0.0,
        'credit_purchases': 0.0,
        'total_purchases': 0.0,
        'customer_payments': 0.0,
        'supplier_payments': 0.0,
        'expenses': 0.0,
        'expected_balance': 0.0,
      };
    }
  }

  void _calculateDifference() {
    setState(() {});
  }

  double get _difference {
    final actual = double.tryParse(_actualBalanceController.text) ?? 0.0;
    return actual - _expectedBalance;
  }

  Future<void> _closeDay() async {
    if (_formKey.currentState?.validate() == true) {
      setState(() => _isLoading = true);

      try {
        final db = ref.read(appDatabaseProvider);
        final today = await db.dayDao.getTodayDay();

        if (today == null) {
          throw Exception('لا يوجد يوم مفتوح');
        }

        final actualBalance =
            double.tryParse(_actualBalanceController.text) ?? 0.0;

        await db.dayDao.closeDay(
          dayId: today['id'] as int,
          closingBalance: actualBalance,
          notes: _notesController.text.trim(),
        );

        unawaited(
          BackupService(db)
              .createBackup(
                type: 'day_close',
                description:
                    'نسخة إغلاق يوم ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
              )
              .then((_) {})
              .catchError((e) {
                AppLogger.e('Day-close backup failed: $e');
              }),
        );

        if (mounted) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إقفال اليوم بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في إقفال اليوم: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _daySummary == null) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('جاري تحميل ملخص اليوم...'),
            ],
          ),
        ),
      );
    }

    final summary = _daySummary!;
    final difference = _difference;

    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 32,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إقفال اليوم المالي',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                        Text(
                          DateFormat(
                            'EEEE, yyyy-MM-dd',
                            'ar',
                          ).format(DateTime.now()),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            'رصيد الافتتاح',
                            '${summary['opening_balance'].toStringAsFixed(2)} ج.م',
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryCard(
                            'المبيعات النقدية',
                            '${summary['cash_sales'].toStringAsFixed(2)} ج.م',
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            'المبيعات الآجلة',
                            '${summary['credit_sales'].toStringAsFixed(2)} ج.م',
                            Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryCard(
                            'المشتريات النقدية',
                            '${summary['cash_purchases'].toStringAsFixed(2)} ج.م',
                            Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            'المشتريات الآجلة',
                            '${summary['credit_purchases'].toStringAsFixed(2)} ج.م',
                            Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryCard(
                            'المصروفات',
                            '${summary['expenses'].toStringAsFixed(2)} ج.م',
                            Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            'مدفوعات العملاء',
                            '${summary['customer_payments'].toStringAsFixed(2)} ج.م',
                            Colors.teal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryCard(
                            'مدفوعات الموردين',
                            '${summary['supplier_payments'].toStringAsFixed(2)} ج.م',
                            Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Expected Balance
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'الرصيد المتوقع:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_expectedBalance.toStringAsFixed(2)} ج.م',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Close Day Form
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'بيانات الإقفال',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _actualBalanceController,
                            decoration: const InputDecoration(
                              labelText: 'الرصيد الفعلي في الخزينة *',
                              border: OutlineInputBorder(),
                              prefixText: 'ج.م ',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'يجب إدخال الرصيد الفعلي';
                              }
                              final amount = double.tryParse(value);
                              if (amount == null) {
                                return 'يجب إدخال مبلغ صحيح';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Difference Display
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: difference.abs() > 0.01
                                  ? (difference > 0
                                        ? Colors.red.withValues(alpha: 0.1)
                                        : Colors.green.withValues(alpha: 0.1))
                                  : Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: difference.abs() > 0.01
                                    ? (difference > 0
                                          ? Colors.red
                                          : Colors.green)
                                    : Colors.grey,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'الفرق:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${difference.toStringAsFixed(2)} ج.م',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: difference.abs() > 0.01
                                        ? (difference > 0
                                              ? Colors.red
                                              : Colors.green)
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _notesController,
                            decoration: const InputDecoration(
                              labelText: 'ملاحظات الإقفال',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _closeDay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('إقفال اليوم'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
