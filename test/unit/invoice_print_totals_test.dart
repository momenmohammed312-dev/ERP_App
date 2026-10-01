import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart';

/// Invoice print summary box: discount shown when present, paid shown,
/// remaining never double-subtracts the discount (subtotal is net).
void main() {
  InvoiceItem line({
    required int qty,
    required double price,
    required double total,
  }) =>
      InvoiceItem(
        id: 0,
        invoiceId: 0,
        description: 'x',
        unit: 'قطعة',
        quantity: qty,
        unitPrice: price,
        totalPrice: total,
      );

  group('invoiceSummaryTotals', () {
    test('discount + partial payment (screenshot case)', () {
      // Line: 1 × 243, net total 233 (10 discount), paid 120.
      final (discount, paid, remaining) =
          UnifiedPrintService.invoiceSummaryTotals(
        items: [line(qty: 1, price: 243, total: 233)],
        subtotal: 233,
        paid: 120,
      );
      expect(discount, 10.0);
      expect(paid, 120.0);
      expect(remaining, 113.0);
    });

    test('no discount, unpaid', () {
      final (discount, paid, remaining) =
          UnifiedPrintService.invoiceSummaryTotals(
        items: [line(qty: 2, price: 50, total: 100)],
        subtotal: 100,
        paid: 0,
      );
      expect(discount, 0.0);
      expect(paid, 0.0);
      expect(remaining, 100.0);
    });

    test('fully paid nets to zero, never negative from discount', () {
      final (discount, paid, remaining) =
          UnifiedPrintService.invoiceSummaryTotals(
        items: [line(qty: 1, price: 100, total: 90)],
        subtotal: 90,
        paid: 90,
      );
      expect(discount, 10.0);
      expect(remaining, 0.0);
    });
  });
}
