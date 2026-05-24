import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';

class SupplierStatementScreen extends ConsumerStatefulWidget {
  final Supplier supplier;
  const SupplierStatementScreen({super.key, required this.supplier});

  @override
  ConsumerState<SupplierStatementScreen> createState() => _SupplierStatementScreenState();
}

class _SupplierStatementScreenState extends ConsumerState<SupplierStatementScreen> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  List<LedgerTransaction> _transactions = [];
  double _openingBalance = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatement();
  }

  Future<void> _loadStatement() async {
    setState(() => _isLoading = true);
    final db = ref.read(appDatabaseProvider);
    
    // Get transactions in range
    final txs = await db.ledgerDao.getTransactionsByDateRange(
      'Supplier',
      widget.supplier.id,
      DateTime(_fromDate.year, _fromDate.month, _fromDate.day),
      DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59),
    );

    // Get balance BEFORE fromDate
    final prevBalance = await db.ledgerDao.getRunningBalance(
      'Supplier',
      widget.supplier.id,
      upToDate: _fromDate.subtract(const Duration(seconds: 1)),
    );

    setState(() {
      _transactions = txs;
      _openingBalance = prevBalance;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double runningBalance = _openingBalance;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('كشف حساب مورد: ${widget.supplier.name}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: () {
                // TODO: Implement PDF Export for supplier statement
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Date Filter
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            _fromDate = picked.start;
                            _toDate = picked.end;
                          });
                          _loadStatement();
                        }
                      },
                      icon: const Icon(Icons.date_range),
                      label: Text('من ${DateFormat('yyyy/MM/dd').format(_fromDate)} إلى ${DateFormat('yyyy/MM/dd').format(_toDate)}'),
                    ),
                  ),
                ],
              ),
            ),

            // Opening Balance Row
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('رصيد ما قبل الفترة:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '${_openingBalance.toStringAsFixed(2)} ج.م',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _openingBalance >= 0 ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
            ),

            // Table Header
            _buildTableHeader(),

            // List
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      // For suppliers, credit is (+) money we owe them, debit is (-) money we paid them
                      runningBalance += (tx.credit - tx.debit);
                      return _buildTransactionRow(tx, runningBalance);
                    },
                  ),
            ),

            // Final Balance Footer
            _buildFooter(runningBalance),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        border: const Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text('البيان', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('دائن (+)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
          Expanded(flex: 2, child: Text('مدين (-)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
          Expanded(flex: 2, child: Text('الرصيد', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(LedgerTransaction tx, double currentBalance) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey, width: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(DateFormat('MM/dd HH:mm').format(tx.date), style: const TextStyle(fontSize: 12))),
          Expanded(flex: 3, child: Text(tx.description, style: const TextStyle(fontSize: 12))),
          Expanded(flex: 2, child: Text(tx.credit > 0 ? tx.credit.toStringAsFixed(2) : '-', style: const TextStyle(color: Colors.red))),
          Expanded(flex: 2, child: Text(tx.debit > 0 ? tx.debit.toStringAsFixed(2) : '-', style: const TextStyle(color: Colors.green))),
          Expanded(flex: 2, child: Text(currentBalance.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildFooter(double finalBalance) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('مستحق للمورد حالياً:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(
            '${finalBalance.toStringAsFixed(2)} ج.م',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: finalBalance >= 0 ? Colors.red : Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}
