import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class SplitPaymentResult {
  final double cash;
  final double card;
  final double credit;

  SplitPaymentResult({
    required this.cash,
    required this.card,
    required this.credit,
  });

  bool get isFullyPaid => (cash + card + credit) >= total;
  double get total => cash + card + credit;
}

class SplitPaymentDialog extends StatefulWidget {
  final double totalAmount;
  final bool isCustomerSelected;
  final String? customerName;

  const SplitPaymentDialog({
    super.key,
    required this.totalAmount,
    this.isCustomerSelected = false,
    this.customerName,
  });

  @override
  State<SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<SplitPaymentDialog> {
  final _cashController = TextEditingController();
  final _cardController = TextEditingController();
  final _creditController = TextEditingController();

  double _cashAmount = 0.0;
  double _cardAmount = 0.0;
  double _creditAmount = 0.0;

  @override
  void initState() {
    super.initState();
    // Default: Full amount in cash
    _cashAmount = widget.totalAmount;
    _cashController.text = _cashAmount.toStringAsFixed(2);
    _cardController.text = '0.00';
    _creditController.text = '0.00';
  }

  void _updateAmounts(String field, String value) {
    final val = double.tryParse(value) ?? 0.0;
    setState(() {
      if (field == 'cash') {
        _cashAmount = val;
      } else if (field == 'card') {
        _cardAmount = val;
      } else if (field == 'credit') {
        _creditAmount = val;
      }

      // Calculate remaining to balance the total
      // This is a bit tricky: which field should take the hit?
      // Let's just show the current total vs expected total.
    });
  }

  double get _currentTotal => _cashAmount + _cardAmount + _creditAmount;
  double get _remaining => widget.totalAmount - _currentTotal;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.payments, color: Colors.blue),
          SizedBox(width: 10),
          Text('تقسيم الدفع (Split Payment)'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'إجمالي الفاتورة:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${widget.totalAmount.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(20),
            if (widget.customerName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 18, color: Colors.grey),
                    const Gap(8),
                    Text(
                      'العميل: ${widget.customerName}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            
            // Cash Field
            _buildPaymentField(
              label: 'مبلغ نقدي (Cash)',
              controller: _cashController,
              icon: Icons.money,
              color: Colors.green,
              onChanged: (v) => _updateAmounts('cash', v),
            ),
            const Gap(16),
            
            // Card Field
            _buildPaymentField(
              label: 'مبلغ فيزا/ماستر (Card)',
              controller: _cardController,
              icon: Icons.credit_card,
              color: Colors.orange,
              onChanged: (v) => _updateAmounts('card', v),
            ),
            const Gap(16),
            
            // Credit Field (Deferred)
            _buildPaymentField(
              label: 'مبلغ آجل (Credit/Deferred)',
              controller: _creditController,
              icon: Icons.timer,
              color: Colors.red,
              enabled: widget.isCustomerSelected,
              onChanged: (v) => _updateAmounts('credit', v),
              helperText: !widget.isCustomerSelected ? 'يجب اختيار عميل لتفعيل الدفع الآجل' : null,
            ),
            
            const Gap(20),
            const Divider(),
            const Gap(10),
            
            _buildSummaryRow('المجموع المدفوع:', _currentTotal),
            _buildSummaryRow(
              _remaining >= 0 ? 'المتبقي لتغطية الفاتورة:' : 'المبلغ الزائد (الباقي):', 
              _remaining.abs(),
              color: _remaining == 0 ? Colors.green : (_remaining > 0 ? Colors.red : Colors.blue),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _remaining == 0 ? () {
            Navigator.pop(context, SplitPaymentResult(
              cash: _cashAmount,
              card: _cardAmount,
              credit: _creditAmount,
            ));
          } : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
          child: const Text('تأكيد الدفع'),
        ),
      ],
    );
  }

  Widget _buildPaymentField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required Color color,
    required Function(String) onChanged,
    bool enabled = true,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: enabled ? Colors.black87 : Colors.grey,
          ),
        ),
        const Gap(8),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: enabled ? color : Colors.grey),
            suffixText: 'ج.م',
            border: const OutlineInputBorder(),
            filled: !enabled,
            fillColor: Colors.grey.shade100,
            helperText: helperText,
            helperStyle: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          Text(
            '${value.toStringAsFixed(2)} ج.م',
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
