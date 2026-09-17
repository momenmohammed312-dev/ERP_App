import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';

/// Bug 3: one ID-derived display format, no timestamp numbering.
///
/// - Customer invoices display `Invoices.id` zero-padded to 6.
/// - Supplier invoices use their own `PUR-` + zero-padded series.
/// - Legacy stored numbers are preserved; receiptNumber stays `INV<id>`
///   so `_extractInvoiceId` and every receipt parser keep working.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  group('InvoiceNumberFormatter', () {
    test('pads customer ids to 6 digits without truncating', () {
      expect(formatInvoiceNumber(1), '000001');
      expect(formatInvoiceNumber(2), '000002');
      expect(formatInvoiceNumber(123), '000123');
      expect(formatInvoiceNumber(1000000), '1000000');
    });

    test('supplier series never collides with customer values', () {
      expect(formatPurchaseNumber(1), 'PUR-000001');
      expect(formatPurchaseNumber(123), 'PUR-000123');
      expect(parsePurchaseNumber('PUR-000123'), 123);
      expect(parsePurchaseNumber('PUR-1750000000000'), 1750000000000);
      expect(parsePurchaseNumber('000123'), isNull);
      expect(parsePurchaseNumber(null), isNull);
    });

    test('canonical means exactly 6 digits', () {
      expect(isCanonicalInvoiceNumber('000001'), isTrue);
      expect(isCanonicalInvoiceNumber('INV2'), isFalse);
      expect(isCanonicalInvoiceNumber('DRAFT_1'), isFalse);
      expect(isCanonicalInvoiceNumber('PUR-000001'), isFalse);
      expect(isCanonicalInvoiceNumber('12345'), isFalse);
      expect(isCanonicalInvoiceNumber(null), isFalse);
    });
  });

  group('InvoiceService numbering', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    Future<CreateInvoiceResult> sell({
      String? customerId,
      String customerName = 'عميل',
      double total = 100,
      double paid = 100,
      String? number,
    }) =>
        InvoiceService(database).createInvoice(
          customerId: customerId,
          customerName: customerName,
          paymentMethod: 'cash',
          totalAmount: total,
          paidAmount: paid,
          status: 'paid',
          invoiceNumber: number,
          items: const [],
        );

    test('fresh DB numbers sequentially from 000001', () async {
      final first = await sell();
      final second = await sell();
      expect(first.invoiceId, 1);
      expect(first.invoice.invoiceNumber, '000001');
      expect(second.invoice.invoiceNumber, '000002');

      // Stored values are canonical.
      final rows = await database.select(database.invoices).get();
      expect(
        rows.map((r) => r.invoiceNumber).toList(),
        ['000001', '000002'],
      );
    });

    test('legacy caller-supplied numbers are preserved, never rewritten',
        () async {
      final legacy = await sell(number: 'INV9');
      expect(legacy.invoice.invoiceNumber, 'INV9');
      final next = await sell();
      // Next id-derived value continues from the row id, not from legacy.
      expect(next.invoice.invoiceNumber, '000002');
    });

    test('receipt linkage stays INV<id> for parsers', () async {
      await database.into(database.customers).insert(
            CustomersCompanion.insert(id: 'c1', name: 'عميل آجل'),
          );
      final r = await InvoiceService(database).createInvoice(
        customerId: 'c1',
        customerName: 'عميل آجل',
        paymentMethod: 'credit',
        totalAmount: 200,
        paidAmount: 50,
        status: 'partial',
        items: const [],
      );
      final rows = await database.ledgerDao.getTransactionsByReceiptNumber(
        'INV${r.invoiceId}',
      );
      expect(rows, isNotEmpty);
      expect(isCanonicalInvoiceNumber(r.invoice.invoiceNumber), isTrue);
      // Bug 2 wording: sale/payment rows use فاتورة/سداد + short number.
      final sale = rows.firstWhere((t) => t.origin == 'sale');
      final pay = rows.firstWhere((t) => t.origin == 'payment');
      expect(sale.description, 'فاتورة ${r.invoice.invoiceNumber}');
      expect(pay.description, 'سداد ${r.invoice.invoiceNumber}');
    });
  });
}
