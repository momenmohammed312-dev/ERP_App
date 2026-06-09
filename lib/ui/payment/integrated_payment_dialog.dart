import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';

class IntegratedPaymentDialog extends StatefulWidget {
  final AppDatabase db;
  final double totalAmount;
  final String customerId;
  final String customerName;
  final Function(Map<String, dynamic>) onPaymentComplete;

  const IntegratedPaymentDialog({
    super.key,
    required this.db,
    required this.totalAmount,
    required this.customerId,
    required this.customerName,
    required this.onPaymentComplete,
  });

  @override
  State<IntegratedPaymentDialog> createState() =>
      _IntegratedPaymentDialogState();
}

class _IntegratedPaymentDialogState extends State<IntegratedPaymentDialog> {
  String _selectedPaymentMethod = 'cash';
  double _paidAmount = 0.0;
  double _remainingAmount = 0.0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _paidAmount = widget.totalAmount;
    _remainingAmount = 0.0;
  }

  Future<void> _processPayment() async {
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
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final paymentData = {
        'amount': _paidAmount,
        'paymentMethod': _selectedPaymentMethod,
        'remainingAmount': _remainingAmount,
        'customerId': widget.customerId,
        'customerName': widget.customerName,
        'date': DateTime.now(),
      };

      // Create ledger transaction for the payment
      await widget.db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_payment',
          entityType: 'Customer',
          refId: widget.customerId,
          date: DateTime.now(),
          description: 'دفعة فاتورة - ${widget.customerName}',
          debit: Value(_paidAmount),
          credit: const Value(0.0),
          origin: 'payment',
          paymentMethod: Value(_selectedPaymentMethod),
        ),
      );

      widget.onPaymentComplete(paymentData);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تسجيل الدفعة بنجاح: ${_paidAmount.toStringAsFixed(2)} ج.م',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في معالجة الدفعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.payment,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                    const Gap(12),
                    Text(
                      'تسديد فاتورة',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Gap(24),

                // Customer Info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'العميل: ${widget.customerName}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Gap(8),
                      Text(
                        'المبلغ الإجمالي: ${widget.totalAmount.toStringAsFixed(2)} ج.م',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(24),

                // Payment Method Selection
                Text(
                  'طريقة الدفع',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedPaymentMethod = 'cash'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _selectedPaymentMethod == 'cash'
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedPaymentMethod == 'cash'
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _selectedPaymentMethod == 'cash'
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.shade600,
                                    width: 2,
                                  ),
                                ),
                                child: _selectedPaymentMethod == 'cash'
                                    ? Center(
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const Gap(8),
                              const Text('كاش'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedPaymentMethod = 'visa'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _selectedPaymentMethod == 'visa'
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedPaymentMethod == 'visa'
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _selectedPaymentMethod == 'visa'
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.shade600,
                                    width: 2,
                                  ),
                                ),
                                child: _selectedPaymentMethod == 'visa'
                                    ? Center(
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const Gap(8),
                              const Text('فيزا'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedPaymentMethod = 'transfer'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _selectedPaymentMethod == 'transfer'
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedPaymentMethod == 'transfer'
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _selectedPaymentMethod == 'transfer'
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey.shade600,
                                    width: 2,
                                  ),
                                ),
                                child: _selectedPaymentMethod == 'transfer'
                                    ? Center(
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const Gap(8),
                              const Text('تحويل'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(24),

                // Amount Input
                Text(
                  'المبلغ المدفوع',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(12),
                TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'المبلغ المدفوع (ج.م)',
                    border: const OutlineInputBorder(),
                    prefixText: 'ج.م ',
                    suffixText: widget.totalAmount.toStringAsFixed(2),
                  ),
                  onChanged: (value) {
                    final amount = double.tryParse(value) ?? 0.0;
                    setState(() {
                      _paidAmount = amount;
                      _remainingAmount = widget.totalAmount - amount;
                    });
                  },
                  controller: TextEditingController(
                    text: _paidAmount.toStringAsFixed(2),
                  ),
                ),
                const Gap(16),

                // Remaining Amount Display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _remainingAmount > 0
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _remainingAmount > 0
                          ? Colors.red.withValues(alpha: 0.3)
                          : Colors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'المبلغ المتبقي:',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_remainingAmount.toStringAsFixed(2)} ج.م',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _remainingAmount > 0
                                  ? Colors.red
                                  : Colors.green,
                            ),
                      ),
                    ],
                  ),
                ),
                const Gap(24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading || _paidAmount <= 0
                            ? null
                            : _processPayment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text('تأكيد الدفع'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
