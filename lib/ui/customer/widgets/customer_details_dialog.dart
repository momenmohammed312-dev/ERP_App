import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/customer/widgets/enhanced_customer_statement_button.dart';
import '../../payment/integrated_payment_dialog.dart';

class CustomerDetailsDialog extends StatefulWidget {
  final Customer customer;
  final AppDatabase db;
  final Function() onDataChanged;

  const CustomerDetailsDialog({
    super.key,
    required this.customer,
    required this.db,
    required this.onDataChanged,
  });

  @override
  State<CustomerDetailsDialog> createState() => _CustomerDetailsDialogState();
}

class _CustomerDetailsDialogState extends State<CustomerDetailsDialog> {
  List<LedgerTransaction> _transactions = [];
  DateTimeRange? _dateRange;
  bool _isLoading = false;
  double _currentBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Get all transactions first to calculate correct opening balance if filtered
      // Or just get simple list for now as filters usually apply to VIEW not BALANCE calculation
      // But for statement, we want transactions in range.

      // Let's simplified: Get ALL transactions, then filter in memory for display,
      // but keep running balance correct.
      final allTransactions = await widget.db.ledgerDao.getTransactionsByEntity(
        'Customer',
        widget.customer.id,
      );

      // Current total balance
      _currentBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        widget.customer.id,
      );

      // Filter if needed
      var displayTransactions = allTransactions;
      if (_dateRange != null) {
        displayTransactions = allTransactions.where((t) {
          return t.date.isAfter(_dateRange!.start) &&
              t.date.isBefore(_dateRange!.end.add(const Duration(days: 1)));
        }).toList();
      }

      setState(() {
        _transactions = displayTransactions;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _loadData();
    }
  }

  void _showPaymentDialog() {
    showDialog(
      context: context,
      builder: (context) => IntegratedPaymentDialog(
        db: widget.db,
        totalAmount: _currentBalance > 0
            ? _currentBalance
            : 0.0, // Default to full debt
        customerId: widget.customer.id,
        customerName: widget.customer.name,
        onPaymentComplete: (paymentData) {
          widget.onDataChanged();
          _loadData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.customer.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${l10n.current_balance}: ${_currentBalance.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: _currentBalance > 0 ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.calendar_month),
                      onPressed: _pickDateRange,
                      tooltip: l10n.date_filter,
                    ),
                    if (_dateRange != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _dateRange = null);
                          _loadData();
                        },
                      ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _showPaymentDialog,
                      icon: const Icon(Icons.payment),
                      label: Text(l10n.pay), // "Pay"
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    EnhancedCustomerStatementButton(
                      customer: widget.customer,
                      db: widget.db,
                      onSuccess: () {
                        widget.onDataChanged();
                        _loadData();
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),

            // Table
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: DataTable(
                        columns: [
                          DataColumn(
                            label: Text(l10n.invoice_number),
                          ), // Invoice # / Receipt #
                          DataColumn(label: Text(l10n.type)), // Type
                          DataColumn(label: Text(l10n.date)), // Date
                          DataColumn(
                            label: Text(l10n.total_amount),
                          ), // Debit (Amount)
                          DataColumn(
                            label: Text(l10n.paid_amount),
                          ), // Credit (Paid)
                          DataColumn(
                            label: Text(l10n.remaining_amount),
                          ), // Running Balance
                        ],
                        rows: _buildTransactionRows(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<DataRow> _buildTransactionRows() {
    // Sort chronologically (oldest first) for running balance calculation
    final sorted = List<LedgerTransaction>.from(_transactions)
      ..sort((a, b) => a.date.compareTo(b.date));

    double runningBalance = 0;
    final rows = <DataRow>[];

    for (final t in sorted) {
      runningBalance += t.debit - t.credit;
      rows.add(
        DataRow(
          cells: [
            DataCell(Text(t.receiptNumber ?? '-')),
            DataCell(Text(t.origin)),
            DataCell(Text(DateFormat('yyyy-MM-dd HH:mm').format(t.date))),
            DataCell(Text(t.debit > 0 ? t.debit.toStringAsFixed(2) : '-')),
            DataCell(Text(t.credit > 0 ? t.credit.toStringAsFixed(2) : '-')),
            DataCell(
              Text(
                runningBalance.toStringAsFixed(2),
                style: TextStyle(
                  color: runningBalance > 0 ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return rows;
  }
}
