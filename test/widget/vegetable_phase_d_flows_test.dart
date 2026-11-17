import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/expenses_table.dart';
import 'package:pos_offline_desktop/core/database/tables/supplier_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/shipment_allocation_service.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/customer/customer_debt_list_screen.dart';
import 'package:pos_offline_desktop/ui/day/close_day_dialog.dart';
import 'package:pos_offline_desktop/ui/empty_barnika/empty_barnika_screen.dart';
import 'package:pos_offline_desktop/ui/expense/expense_page.dart';
import 'package:pos_offline_desktop/ui/home/modern_home.dart';
import 'package:pos_offline_desktop/ui/invoice/quick_sale_screen.dart';
import 'package:pos_offline_desktop/ui/shipments/shipments_screen.dart';
import 'package:pos_offline_desktop/ui/shipments/widgets/shipment_detail_screen.dart';

Widget _wrapTestApp(AppDatabase db, Widget home, {ThemeMode themeMode = ThemeMode.light}) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(
      themeMode: themeMode,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ar'),
      home: home,
    ),
  );
}

Future<void> _pumpAsync(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _seedOpenDay(AppDatabase db) async {
  await db.dayDao.openDay(openingBalance: 1000.0, openedBy: 'test');
}

void main() {
  setUp(() {
    AppFlavor.initialize(Flavor.vegetable);
  });

  tearDown(() {
    AppFlavor.initialize(Flavor.base);
  });

  group('Phase D — Vegetable Market Mobile UI Flows', () {
    testWidgets(
      'QuickSaleScreen renders on 390x844, forbids empty price & oversell, records sale + atomic barnika',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));

        final shipmentId = await tester.runAsync(() async {
          await _seedOpenDay(db);
          await db.into(db.suppliers).insert(
                SuppliersCompanion.insert(
                  id: DefaultSupplier.unknownId,
                  name: DefaultSupplier.unknownName,
                ),
              );
          await db.customerDao.insertCustomer(
            CustomersCompanion.insert(id: 'C-1', name: 'إبراهيم أحمد'),
          );
          return db.vegetableShipmentDao.insertShipment(
            VegetableShipmentsCompanion.insert(
              supplierId: DefaultSupplier.unknownId,
              shipmentNumber: 'SHP-001',
              pricingMode: ShipmentPricingMode.commission,
              totalBarnikaCount: 10,
              totalCost: 0.0,
              barnikaRemainingCount: 10,
              toppingCount: const Value(2), // effective remaining = 8
              commissionPercentage: const Value(7.0),
            ),
          );
        });

        await tester.pumpWidget(_wrapTestApp(db, QuickSaleScreen(db: db)));
        await _pumpAsync(tester);

        expect(find.text('بيع سريع (سوق الخضار)'), findsOneWidget);
        expect(find.textContaining('المتاح للبيع: 8 برنيكة'), findsOneWidget);

        // Select registered customer via normalized Arabic search ("ابراهيم" -> "إبراهيم")
        await tester.tap(find.text('اضغط لاختيار أو إضافة زبون...'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'ابحث بالاسم أو الهاتف (تطبيع تلقائي للعربي)...'),
          'ابراهيم',
        );
        await tester.pumpAndSettle();
        expect(find.text('إبراهيم أحمد'), findsOneWidget);
        await tester.tap(find.text('إبراهيم أحمد'));
        await tester.pumpAndSettle();

        // Try submitting with no price -> fails form validation (manual price required)
        await tester.ensureVisible(find.textContaining('تسجيل البيعة'));
        await tester.tap(find.textContaining('تسجيل البيعة'));
        await tester.pumpAndSettle();
        expect(find.text('اكتب السعر يدوياً'), findsOneWidget);

        // Try entering quantity > effective remaining (9 > 8)
        final qtyField = find.byType(TextFormField).first;
        await tester.enterText(qtyField, '9');
        final priceField = find.widgetWithText(TextFormField, 'اكتب السعر...');
        await tester.enterText(priceField, '120');
        await tester.ensureVisible(find.textContaining('تسجيل البيعة'));
        await tester.tap(find.textContaining('تسجيل البيعة'));
        await tester.pumpAndSettle();
        expect(find.text('المتاح 8 فقط'), findsOneWidget);

        // Enter valid qty 3 @ 120 = 360, partial pay 160, barnika returned 1
        await tester.enterText(qtyField, '3');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('دفع جزئي'));
        await tester.tap(find.text('دفع جزئي'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(TextFormField, 'المدفوع الآن *'),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'المدفوع الآن *'),
          '160',
        );
        await tester.ensureVisible(
          find.widgetWithText(TextFormField, 'البرانيك المستلمة الآن'),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'البرانيك المستلمة الآن'),
          '1',
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.textContaining('تسجيل البيعة'));
        await tester.tap(find.textContaining('تسجيل البيعة'));
        await _pumpAsync(tester);

        // Verify database mutations
        final resultMap = await tester.runAsync(() async {
          final invs = await db.select(db.invoices).get();
          final shp = await db.vegetableShipmentDao.getById(shipmentId!);
          final barnikaRows = await (db.select(db.emptyBarnikaTracking)
                ..where((t) => t.customerId.equals('C-1')))
              .get();
          return {
            'invs': invs,
            'shp': shp,
            'barnikaRows': barnikaRows,
          };
        });
        final invs = resultMap!['invs']! as List<Invoice>;
        final shp = resultMap['shp'] as VegetableShipment?;
        final barnikaRows =
            resultMap['barnikaRows']! as List<EmptyBarnikaTrackingData>;
        final visibleSnack = tester
            .widgetList<Text>(find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Text),
            ))
            .map((t) => t.data)
            .join(' | ');
        expect(invs.length, 1, reason: 'SnackBar: $visibleSnack');
        expect(invs.first.totalAmount, closeTo(360.0, 0.01));
        expect(invs.first.paidAmount, closeTo(160.0, 0.01));

        expect(shp!.barnikaSoldCount, 3);
        expect(ShipmentAllocationService.effectiveRemaining(shp), 5); // 10 - 3 - 2

        expect(barnikaRows.length, 1);
        expect(barnikaRows.first.invoiceId, invs.first.id);
        expect(barnikaRows.first.quantityOut, 3);
        expect(barnikaRows.first.quantityReturned, 1);

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'ShipmentDetailScreen renders ShipmentStatement on 390x844 with supplier/topping/expense/close actions',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));

        final shipmentId = await tester.runAsync(() async {
          await db.into(db.suppliers).insert(
                SuppliersCompanion.insert(
                  id: DefaultSupplier.unknownId,
                  name: DefaultSupplier.unknownName,
                ),
              );
          return db.vegetableShipmentDao.insertShipment(
            VegetableShipmentsCompanion.insert(
              supplierId: DefaultSupplier.unknownId,
              shipmentNumber: 'SHP-777',
              pricingMode: ShipmentPricingMode.commission,
              totalBarnikaCount: 20,
              totalCost: 0.0,
              barnikaRemainingCount: 20,
              commissionPercentage: const Value(8.0),
            ),
          );
        });

        await tester.pumpWidget(
          _wrapTestApp(db, ShipmentDetailScreen(db: db, shipmentId: shipmentId!)),
        );
        await _pumpAsync(tester);

        expect(find.text('شحنة #SHP-777'), findsOneWidget);
        expect(find.textContaining('مورد غير محدد'), findsWidgets);
        expect(find.text('تعيين المورد'), findsOneWidget);
        expect(find.text('تسجيل برانيك تكميل'), findsOneWidget);
        expect(find.text('+ مصروف شحنة (نولون)'), findsOneWidget);
        expect(find.text('قفل الشحنة وترحيل للمورد'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'ExpensePage saves shipment-scoped expense cleanly on mobile without supplier double-counting',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));

        final shipmentId = await tester.runAsync(() async {
          await _seedOpenDay(db);
          await db.into(db.suppliers).insert(
                SuppliersCompanion.insert(id: 'SUP-1', name: 'الحاج محمود'),
              );
          return db.vegetableShipmentDao.insertShipment(
            VegetableShipmentsCompanion.insert(
              supplierId: 'SUP-1',
              shipmentNumber: 'SHP-99',
              pricingMode: ShipmentPricingMode.commission,
              totalBarnikaCount: 30,
              totalCost: 0.0,
              barnikaRemainingCount: 30,
              commissionPercentage: const Value(7.0),
            ),
          );
        });

        await tester.pumpWidget(_wrapTestApp(db, ExpensePage(db: db)));
        await _pumpAsync(tester);

        expect(find.text('مصروف المحل'), findsWidgets);
        expect(find.text('مصروف شحنة'), findsOneWidget);

        await tester.ensureVisible(find.text('مصروف شحنة'));
        await tester.tap(find.text('مصروف شحنة'));
        await tester.pumpAndSettle();

        // Pick the open shipment
        final shipmentDropdown = find.byType(DropdownButtonFormField<int>).first;
        await tester.ensureVisible(shipmentDropdown);
        await tester.tap(shipmentDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('#SHP-99').last);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(TextFormField, 'الوصف'));
        await tester.enterText(
          find.widgetWithText(TextFormField, 'الوصف'),
          'نولون عربية طماطم',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'المبلغ'),
          '250',
        );
        await tester.ensureVisible(find.text('إضافة مصروف'));
        await tester.tap(find.text('إضافة مصروف'));
        await _pumpAsync(tester);

        final res = await tester.runAsync(() async {
          final expenses = await db.expenseDao.getAllExpenses();
          final ledgers = await db.select(db.ledgerTransactions).get();
          return {'expenses': expenses, 'ledgers': ledgers};
        });
        final expenses = res!['expenses']! as List<Expense>;
        final ledgers = res['ledgers']! as List<LedgerTransaction>;
        expect(expenses.length, 1);
        expect(expenses.first.scope, ExpenseScope.shipment);
        expect(expenses.first.shipmentId, shipmentId);
        expect(expenses.first.amount, closeTo(250.0, 0.01));

        // Verify ledger used entityType='Expense' rather than 'Supplier'
        expect(ledgers.any((l) => l.entityType == 'Expense' && l.refId == 'shipment_$shipmentId'), isTrue);
        expect(ledgers.any((l) => l.entityType == 'Supplier'), isFalse);

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'CustomerDebtListScreen normalizes Arabic search and opens FIFO collection dialog with discount',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));

        await tester.runAsync(() async {
          await db.customerDao.insertCustomer(
            CustomersCompanion.insert(
              id: 'C-DEBT',
              name: 'أحمد الإسكندراني',
              openingBalance: const Value(500.0),
            ),
          );
          await db.into(db.invoices).insert(
                InvoicesCompanion.insert(
                  invoiceNumber: const Value('INV-10'),
                  customerId: const Value('C-DEBT'),
                  customerName: const Value('أحمد الإسكندراني'),
                  paymentMethod: const Value('credit'),
                  totalAmount: const Value(500.0),
                  paidAmount: const Value(0.0),
                  creditAmount: const Value(500.0),
                  status: const Value('pending'),
                ),
              );
          await db.emptyBarnikaTrackingDao.insertRecord(
            EmptyBarnikaTrackingCompanion.insert(
              customerId: 'C-DEBT',
              dateOut: DateTime.now(),
              quantityOut: 4,
            ),
          );
        });

        await tester.pumpWidget(_wrapTestApp(db, CustomerDebtListScreen(db: db)));
        await _pumpAsync(tester);

        expect(find.text('أحمد الإسكندراني'), findsOneWidget);
        expect(find.textContaining('برانيك: 4'), findsOneWidget);

        // Search with un-normalized alif ("احمد الاسكندراني")
        await tester.enterText(
          find.widgetWithText(TextField, 'بحث ذكي بالاسم أو الهاتف'),
          'احمد الاسكندراني',
        );
        await tester.pumpAndSettle();
        expect(find.text('أحمد الإسكندراني'), findsOneWidget);

        // Open collection dialog and collect 300 + 50 discount
        await tester.tap(find.text('تحصيل'));
        await tester.pumpAndSettle();
        expect(find.text('تحصيل من العميل: أحمد الإسكندراني'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'المبلغ المحصّل'),
          '300',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'خصم عند التحصيل (اختياري)'),
          '50',
        );
        await tester.tap(find.text('تأكيد التحصيل'));
        await _pumpAsync(tester);

        final inv = await tester.runAsync(
          () => (db.select(db.invoices)..where((t) => t.invoiceNumber.equals('INV-10'))).getSingle(),
        );
        expect(inv!.paidAmount, closeTo(350.0, 0.01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'ModernHomeScreen under Flavor.vegetable shows quick sale & vegetable KPIs and hides base-only modules',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));

        await tester.pumpWidget(_wrapTestApp(db, ModernHomeScreen(db: db)));
        await tester.pump(const Duration(milliseconds: 600));
        await _pumpAsync(tester);

        expect(AppFeatures.hasManufacturing, isFalse);
        expect(AppFeatures.hasCustodyModule, isFalse);
        expect(AppFeatures.hasStandardInventory, isFalse);
        expect(AppFeatures.hasSmartAnalytics, isFalse);
        expect(AppFeatures.hasMultiUser, isFalse);

        expect(find.text('بيع سريع'), findsWidgets);
        expect(find.text('عمولات المحل'), findsOneWidget);
        expect(find.text('مصروفات المحل'), findsOneWidget);
        expect(find.text('صافي ربح المحل'), findsOneWidget);
        expect(find.text('العهد المالية'), findsNothing);
        expect(find.text('المنتجات'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'All core vegetable phone flows render without overflow on 360x780 small phone in Dark Mode',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() => tester.runAsync(db.close));

        await tester.runAsync(() async {
          await _seedOpenDay(db);
          await db.into(db.suppliers).insert(
                SuppliersCompanion.insert(
                  id: DefaultSupplier.unknownId,
                  name: DefaultSupplier.unknownName,
                ),
              );
          await db.customerDao.insertCustomer(
            CustomersCompanion.insert(id: 'C-MOB', name: 'زبون هاتف'),
          );
          await db.emptyBarnikaTrackingDao.insertRecord(
            EmptyBarnikaTrackingCompanion.insert(
              customerId: 'C-MOB',
              dateOut: DateTime.now(),
              quantityOut: 5,
            ),
          );
          await db.vegetableShipmentDao.insertShipment(
            VegetableShipmentsCompanion.insert(
              supplierId: DefaultSupplier.unknownId,
              shipmentNumber: 'SHP-MOB',
              pricingMode: ShipmentPricingMode.commission,
              totalBarnikaCount: 25,
              totalCost: 0.0,
              barnikaRemainingCount: 25,
              commissionPercentage: const Value(7.0),
            ),
          );
        });

        // 1. ModernHomeScreen on 360x780 dark
        await tester.pumpWidget(_wrapTestApp(db, ModernHomeScreen(db: db), themeMode: ThemeMode.dark));
        await tester.pump(const Duration(milliseconds: 600));
        await _pumpAsync(tester);
        expect(tester.takeException(), isNull);

        // 2. ShipmentsScreen + ShipmentFormDialog on 360x780 dark
        await tester.pumpWidget(_wrapTestApp(db, ShipmentsScreen(db: db), themeMode: ThemeMode.dark));
        await _pumpAsync(tester);
        expect(find.text('شحنة #SHP-MOB'), findsOneWidget);
        await tester.tap(find.text('استلام شحنة جديدة'));
        await _pumpAsync(tester);
        expect(find.text('استلام شحنة جديدة'), findsWidgets);
        expect(tester.takeException(), isNull);

        // 3. QuickSaleScreen on 360x780 dark
        await tester.pumpWidget(_wrapTestApp(db, QuickSaleScreen(db: db), themeMode: ThemeMode.dark));
        await _pumpAsync(tester);
        expect(find.text('عدد البرانيك *'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 4. EmptyBarnikaScreen on 360x780 dark
        await tester.pumpWidget(_wrapTestApp(db, EmptyBarnikaScreen(db: db), themeMode: ThemeMode.dark));
        await _pumpAsync(tester);
        expect(find.text('زبون هاتف'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 5. CloseDayDialog on 360x780 dark
        await tester.pumpWidget(_wrapTestApp(db, const CloseDayDialog(), themeMode: ThemeMode.dark));
        await _pumpAsync(tester);
        expect(find.text('ملخص تسوية اليوم'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
