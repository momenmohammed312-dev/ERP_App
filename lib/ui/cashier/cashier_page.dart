import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import '../../core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';

class CashierPage extends StatefulWidget {
  final AppDatabase db;

  const CashierPage({super.key, required this.db});

  @override
  State<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends State<CashierPage> {
  DateTime? _openingDate;
  double _openingBalance = 0;
  double _totalIncome = 0;
  double _totalExpenses = 0.0;
  double _closingBalance = 0;
  List<LedgerTransaction> _transactions = [];
  bool _isDayOpen = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentDay();
  }

  Future<void> _loadCurrentDay() async {
    setState(() => _isLoading = true);
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      // Check for opening transaction
      final allTransactions = await widget.db.ledgerDao
          .getAllTransactionsByDateRange(startOfDay, today);

      final openingTransaction = allTransactions
          .where((t) => t.entityType == 'Cash' && t.origin == 'opening')
          .firstOrNull;

      if (openingTransaction != null) {
        // Day is open
        setState(() {
          _openingDate = startOfDay;
          _isDayOpen = true;
          _transactions = allTransactions;

          // Calculate totals
          _openingBalance =
              openingTransaction.debit; // Opening is strictly Debit

          // Income: All Desbit transactions (excluding Opening)
          // We care about CASH income for the drawer balance.
          // We also track Visa income separately for reporting.

          final cashTransactions = allTransactions.where(
            (t) =>
                (t.paymentMethod == 'cash' ||
                    t.paymentMethod == null ||
                    t.entityType == 'Cash') &&
                t.origin != 'opening' &&
                t.origin != 'closing',
          );

          _totalIncome = cashTransactions
              .where((t) => t.debit > 0)
              .fold(0.0, (sum, t) => sum + t.debit);

          _totalExpenses = cashTransactions
              .where((t) => t.credit > 0)
              .fold(0.0, (sum, t) => sum + t.credit);

          _closingBalance = _openingBalance + _totalIncome - _totalExpenses;
        });
      } else {
        // No open day found
        setState(() {
          _openingDate = null;
          _isDayOpen = false;
          _transactions = [];
          _openingBalance = 0;
          _totalIncome = 0;
          _totalExpenses = 0;
          _closingBalance = 0;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.error_loading_data}: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openNewDay() async {
    final l10n = AppLocalizations.of(context);
    // Show popup for entering opening balance
    final result = await _showOpeningBalanceDialog();
    if (!mounted || result == null) return; // User cancelled or unmounted

    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      // Add opening balance transaction
      await widget.db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_opening',
          entityType: 'Cash',
          refId: 'daily',
          date: startOfDay,
          description:
              '${l10n.opening_balance_drawer} ${DateFormat('yyyy/MM/dd').format(startOfDay)}',
          debit: Value(result),
          credit: const Value(0.0),
          origin: 'opening',
          paymentMethod: const Value('cash'),
        ),
      );

      await _loadCurrentDay();
      if (!mounted) return;

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.day_opened_successfully)));
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.error_opening_day(e.toString()))),
        );
      }
    }
  }

  Future<double?> _showOpeningBalanceDialog() async {
    final controller = TextEditingController();
    double? balance;

    final l10n = AppLocalizations.of(context);
    return showDialog<double>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.opening_balance_dialog_title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.opening_balance_prompt),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${l10n.opening_balance_label} (ج.م)',
                  border: const OutlineInputBorder(),
                  prefixText: 'ج.م ',
                ),
                onChanged: (value) {
                  balance = double.tryParse(value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                if (balance != null && balance! >= 0) {
                  Navigator.of(context).pop(balance);
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.invalid_amount)));
                }
              },
              child: Text(l10n.open_new_day),
            ),
          ],
        );
      },
    );
  }

  Future<void> _closeDay() async {
    // Show popup for entering closing amounts
    final result = await _showClosingBalanceDialog();
    if (result == null) return; // User cancelled

    // Check if widget is still mounted after async gap
    if (!mounted) return;

    // Get l10n after confirming mounted
    final l10n = AppLocalizations.of(context);

    try {
      final today = DateTime.now();

      // Add cash closing transaction
      await widget.db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_closing_cash',
          entityType: 'Cash',
          refId: 'daily',
          date: today,
          description:
              '${l10n.day_is_closed} - ${l10n.cash}: ${result['cash']!.toStringAsFixed(2)} ${l10n.currency}',
          debit: const Value(0.0),
          credit: Value(result['cash']!),
          origin: 'closing',
          paymentMethod: const Value('cash'),
        ),
      );

      // Add visa closing transaction if applicable
      if ((result['visa'] ?? 0.0) > 0) {
        await widget.db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${DateTime.now().millisecondsSinceEpoch}_closing_visa',
            entityType: 'Cash',
            refId: 'daily',
            date: today,
            description:
                '${l10n.day_is_closed} - ${l10n.visa}: ${result['visa']!.toStringAsFixed(2)} ${l10n.currency}',
            debit: const Value(0.0),
            credit: Value(result['visa']!),
            origin: 'closing',
            paymentMethod: const Value('visa'),
          ),
        );
      }

      setState(() {
        _isDayOpen = false;
        _openingDate = null;
        _transactions = [];
        _openingBalance = 0;
        _totalIncome = 0;
        _totalExpenses = 0;
        _closingBalance = 0;
      });

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.day_closed_successfully)));
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.error_closing_day(e.toString()))),
        );
      }
    }
  }

  Future<Map<String, double>?> _showClosingBalanceDialog() async {
    final cashController = TextEditingController();
    final visaController = TextEditingController();
    double? cashAmount;
    double? visaAmount;

    final l10n = AppLocalizations.of(context);
    return showDialog<Map<String, double>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.closing_day_dialog_title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${l10n.current_balance}: ${_closingBalance.toStringAsFixed(2)} ج.م',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: cashController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${l10n.closing_cash_label} (ج.م)',
                  border: const OutlineInputBorder(),
                  prefixText: 'ج.م ',
                ),
                onChanged: (value) {
                  cashAmount = double.tryParse(value);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: visaController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${l10n.closing_visa_label} (ج.م)',
                  border: const OutlineInputBorder(),
                  prefixText: 'ج.م ',
                ),
                onChanged: (value) {
                  visaAmount = double.tryParse(value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                if (cashAmount != null && cashAmount! >= 0) {
                  Navigator.of(
                    context,
                  ).pop({'cash': cashAmount!, 'visa': visaAmount ?? 0.0});
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.invalid_amount)));
                }
              },
              child: Text(l10n.close_day),
            ),
          ],
        );
      },
    );
  }

  void _showShiftReportDialog() {
    final TextEditingController actualCashController = TextEditingController();
    double actualCash = 0.0;
    double expectedCash = _openingBalance + _totalIncome - _totalExpenses;
    double variance = 0.0;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'تقرير الوردية',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _reportRow('الرصيد الافتتاحي', _openingBalance),
                    _reportRow('إجمالي الإيرادات (كاش)', _totalIncome),
                    _reportRow('إجمالي المصروفات', _totalExpenses),
                    const Divider(),
                    _reportRow('الرصيد المتوقع', expectedCash, isBold: true),
                    const Gap(16),
                    TextField(
                      controller: actualCashController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الرصيد الفعلي (الموجود بالدرج)',
                        border: OutlineInputBorder(),
                        prefixText: 'ج.م ',
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          actualCash = double.tryParse(value) ?? 0.0;
                          variance = actualCash - expectedCash;
                        });
                      },
                    ),
                    const Gap(16),
                    _reportRow(
                      'العجز / الزيادة',
                      variance,
                      isBold: true,
                      color: variance < 0 ? Colors.red : Colors.green,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    await PrinterService.printShiftReport(
                      date: DateTime.now(),
                      startTime: _openingDate ?? DateTime.now(),
                      endTime: DateTime.now(),
                      openingCash: _openingBalance,
                      totalRevenue: _totalIncome,
                      totalExpenses: _totalExpenses,
                      expectedCash: expectedCash,
                      actualCash: actualCash,
                      variance: variance,
                    );
                  },
                  icon: const Icon(Icons.print),
                  label: const Text('طباعة التقرير'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _reportRow(
    String label,
    double value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
          Text(
            '${value.toStringAsFixed(2)} ج.م',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cashier),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCurrentDay,
          ),
          // Shift Report Button
          IconButton(
            icon: const Icon(Icons.assignment),
            onPressed: _showShiftReportDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Day Status
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _isDayOpen
                                    ? l10n.day_is_open
                                    : l10n.day_is_closed,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _isDayOpen
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                              ),
                              if (_isDayOpen) ...[
                                ElevatedButton(
                                  onPressed: _closeDay,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(l10n.close_day),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_openingDate != null) ...[
                  const Gap(10),
                  Text(
                    '${l10n.opening_date}: ${DateFormat('yyyy/MM/dd HH:mm').format(_openingDate!)}',
                  ),
                ],
                const Gap(16),
                if (_isDayOpen) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(l10n.opening_balance_drawer),
                                  const Gap(8),
                                  Text(
                                    '${_openingBalance.toStringAsFixed(2)} ج.م',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(l10n.total_revenue),
                                  const Gap(8),
                                  Text(
                                    '${_totalIncome.toStringAsFixed(2)} ج.م',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(l10n.current_balance_drawer),
                                  const Gap(8),
                                  Text(
                                    '${_closingBalance.toStringAsFixed(2)} ج.م',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange,
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
                  const Gap(16),
                ],

                // Actions
                if (!_isDayOpen)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _openNewDay,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(l10n.open_new_day),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Recent Transactions
                if (_transactions.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l10n.recent_transactions_cashier,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ListView.builder(
                        itemCount: _transactions.length,
                        itemBuilder: (context, index) {
                          final transaction = _transactions[index];
                          return Card(
                            child: ListTile(
                              leading: Icon(
                                transaction.debit > 0
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: transaction.debit > 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              title: Text(transaction.description),
                              subtitle: Text(
                                DateFormat(
                                  'yyyy/MM/dd HH:mm',
                                ).format(transaction.date),
                              ),
                              trailing: Text(
                                '${(transaction.debit - transaction.credit).toStringAsFixed(2)} ج.م',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: transaction.debit > 0
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
