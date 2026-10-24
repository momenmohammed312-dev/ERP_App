import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/platform/responsive.dart';
import 'package:pos_offline_desktop/ui/widgets/custom_button.dart';

class PaymentDialog extends StatefulWidget {
  final double totalAmount;
  final Function(String) onPaymentComplete;

  const PaymentDialog({
    super.key,
    required this.totalAmount,
    required this.onPaymentComplete,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  String selectedPaymentMethod = 'cash';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        width: dialogWidth(context, 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: dialogMaxHeight(context)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'طريقة الدفع',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Gap(20),

                // Payment Methods
                Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedPaymentMethod = 'cash';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: selectedPaymentMethod == 'cash'
                              ? Colors.blue.shade50
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.radio_button_checked,
                              color: selectedPaymentMethod == 'cash'
                                  ? Colors.blue
                                  : Colors.grey,
                              size: 20,
                            ),
                            const Gap(8),
                            const Text('كاش'),
                          ],
                        ),
                      ),
                    ),
                    const Gap(8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedPaymentMethod = 'credit';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: selectedPaymentMethod == 'credit'
                              ? Colors.blue.shade50
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.radio_button_unchecked,
                              color: selectedPaymentMethod == 'credit'
                                  ? Colors.blue
                                  : Colors.grey,
                              size: 20,
                            ),
                            const Gap(8),
                            const Text('آجل'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const Gap(20),

                // Total Amount
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'الإجمالي',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${widget.totalAmount.toStringAsFixed(2)} ر.س',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                const Gap(20),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        title: 'إلغاء',
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        backgroundColor: Colors.grey,
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: CustomButton(
                        title: 'دفع',
                        onPressed: () {
                          widget.onPaymentComplete(selectedPaymentMethod);
                          Navigator.of(context).pop();
                        },
                        backgroundColor: Colors.blue,
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
