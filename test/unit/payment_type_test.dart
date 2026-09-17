import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/enhanced_new_invoice_page.dart';

/// Payment-type selection on the CURRENT invoice UI (replaces the obsolete
/// full-app `MyApp` navigation flow):
/// - day closed  -> page refuses entry and returns to previous screen;
/// - cash (نقدي) -> completing persists a canonical 6-digit, fully paid sale;
/// - credit (آجل) -> paid resets to 0.00 and completing without a customer
///   is refused with nothing persisted.
void main() {
  late AppDatabase db;

  setUp(() async {
    // App entry moved main.dart -> PosApp (app_bootstrap); providers and the
    // router read the flavor (production initializes it at startup).
    AppFlavor.initialize(Flavor.base);
    SharedPreferences.setMockInitialValues({});
    await SettingsService.setBusinessName('مخبز النور');
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Test Product',
            price: 10.0,
            quantity: 100,
            category: const Value('General'),
          ),
        );
    await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'c1', name: 'عميل آجل'),
        );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // Desktop UI: give the harness a desktop-sized surface (avoids
    // RenderFlex overflows that only exist on the 800x600 default).
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EnhancedNewInvoicePage(db: db),
                  ),
                ),
                child: const Text('open invoice page'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('open invoice page'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> addOneProduct(WidgetTester tester) async {
    await tester.tap(find.text('Test Product').first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Add to Invoice'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('Payment Type Selection Tests', () {
    testWidgets('day closed refuses entry and returns to previous screen',
        (WidgetTester tester) async {
      await pumpPage(tester);
      // Current intended gate: snackbar + pop (DayClosedDialog covers
      // mid-session closure via _checkDayStatus).
      expect(
        find.text('يجب فتح اليوم أولاً من تبويب الكاشير'),
        findsOneWidget,
      );
      expect(find.text('open invoice page'), findsOneWidget);
      expect(find.byType(EnhancedNewInvoicePage), findsNothing);
    });

    testWidgets('cash selection auto-sets paid and completes canonically',
        (WidgetTester tester) async {
      await db.dayDao.openDay(openingBalance: 100.0);
      await pumpPage(tester);

      await tester.tap(find.text('نقدي'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('فاتورة جديدة'), findsAtLeastNWidgets(1));
      expect(find.text('Test Product'), findsWidgets);

      await addOneProduct(tester);
      // Cash hides the paid field; totals prove the line landed.
      expect(find.text('الإجمالي الكلي:'), findsOneWidget);
      expect(find.text('10.00'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('إكمال والطباعة'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Print may fail in tests (no printer) but the invoice must persist:
      // canonical number, fully paid cash sale.
      final invoices = await db.select(db.invoices).get();
      expect(invoices.length, 1);
      expect(invoices.first.status, 'paid');
      expect(invoices.first.paidAmount, 10.0);
      expect(
        RegExp(r'^\d{6}$').hasMatch(invoices.first.invoiceNumber ?? ''),
        isTrue,
      );
    });

    testWidgets('credit selection resets paid and requires a customer',
        (WidgetTester tester) async {
      await db.dayDao.openDay(openingBalance: 100.0);
      await pumpPage(tester);

      await tester.tap(find.text('آجل'));
      await tester.pump(const Duration(milliseconds: 500));

      // Paid field exists and is reset to zero for credit.
      final paidField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, '0.00'),
      );
      expect(paidField.controller?.text, '0.00');

      await addOneProduct(tester);
      // Nothing auto-paid: remaining shows the full total.
      expect(find.text('10.00 ج.م'), findsAtLeastNWidgets(1));

      // Completing without a customer is refused; nothing is persisted.
      await tester.tap(find.text('إكمال والطباعة'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('يرجى اختيار عميل للفاتورة الآجلة'),
        findsOneWidget,
      );
      final invoices = await db.select(db.invoices).get();
      expect(invoices, isEmpty);
    });
  });
}
