import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/supplier_dao.dart';
import 'package:pos_offline_desktop/core/services/purchase_print_service_simple.dart';
import '../../home/widgets/transaction_expansion_tile.dart';

class SupplierStatementDialog extends StatefulWidget {
  final AppDatabase database;
  final Supplier supplier;

  const SupplierStatementDialog({
    super.key,
    required this.database,
    required this.supplier,
  });

  @override
  State<SupplierStatementDialog> createState() =>
      _SupplierStatementDialogState();
}

class _SupplierStatementDialogState extends State<SupplierStatementDialog> {
  bool _isLoading = true;
  List<LedgerTransaction> _transactions = [];
  double _currentBalance = 0.0;
  late final SupplierDao _supplierDao;

  @override
  void initState() {
    super.initState();
    _supplierDao = SupplierDao(widget.database);
    _loadStatement();
  }

  Future<void> _loadStatement() async {
    try {
      final transactions = await widget.database
          .customSelect(
            '''SELECT * FROM ledger_transactions 
           WHERE entity_type = 'Supplier' AND ref_id = ?
           ORDER BY date DESC''',
            variables: [drift.Variable.withString(widget.supplier.id)],
          )
          .get();

      final balance = await _supplierDao.getSupplierBalance(widget.supplier.id);

      setState(() {
        _transactions = transactions
            .map((row) => widget.database.ledgerTransactions.map(row.data))
            .toList();
        _currentBalance = balance;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل كشف الحساب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'كشف حساب المورد',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                        Text(
                          widget.supplier.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                        Text(
                          'كود المورد: ${widget.supplier.id}',
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'الرصيد الحالي',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        '${_currentBalance.toStringAsFixed(2)} ج.م',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _currentBalance > 0
                                  ? Colors.red
                                  : Colors.green,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Transactions List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _transactions.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'لا توجد معاملات',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _transactions.length,
                      itemBuilder: (context, index) {
                        final transaction = _transactions[index];
                        final isPurchase = transaction.credit > 0;

                        return TransactionExpansionTile(
                          transaction: transaction,
                          entityType: 'Supplier',
                          isPurchase: isPurchase,
                          isSale: false,
                          db: widget.database,
                        );
                      },
                    ),
            ),

            // Footer
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'إجمالي المعاملات: ${_transactions.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          // Print supplier statement
                          final printService = PurchasePrintService(
                            widget.database,
                          );
                          printService.printSupplierStatement(
                            int.parse(widget.supplier.id),
                          );
                        },
                        icon: const Icon(Icons.print),
                        label: const Text('طباعة'),
                      ),
                      const SizedBox(width: 8),
                      /* ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('إغلاق'),
                      ), */
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
