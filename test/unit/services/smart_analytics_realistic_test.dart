import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/smart_analytics/predictive_stock_service.dart';
import 'package:pos_offline_desktop/core/services/smart_analytics/financial_anomaly_service.dart';
import 'package:pos_offline_desktop/core/services/smart_analytics/customer_retention_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_offline_desktop/core/services/smart_analytics/smart_advisor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    await db.dayDao.getOrCreateTodayDay(openingBalance: 0, openedBy: 'tester');
  });

  tearDown(() async {
    await db.close();
  });

  group('PredictiveStockService — Realistic Stock Run-Rate & Velocity', () {
    test('accurately calculates velocity, days to stockout, and filters raw materials/inactive', () async {
      final now = DateTime.now();

      // 1. Fast seller: Current stock 10, sells 5 per day -> ~2 days until stockout (Critical)
      final p1 = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'سكر أبيض 1 كجم',
              price: 35.0,
              quantity: 10,
              status: const Value('Active'),
            ),
          );

      // 2. Out of stock item: Current stock 0, sells regularly -> (out_of_stock)
      final p2 = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'زيت عباد 800 مل',
              price: 70.0,
              quantity: 0,
              status: const Value('Active'),
            ),
          );

      // 3. Healthy item: Current stock 200, sells 2 per day -> 100 days (Healthy)
      final p3 = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'أرز فاخر 5 كجم',
              price: 180.0,
              quantity: 200,
              status: const Value('Active'),
            ),
          );

      // 4. Raw material: should be excluded from retail stock prediction
      final p4 = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'دقيق خام للتصنيع',
              price: 20.0,
              quantity: 5,
              status: const Value('Active'),
              productType: const Value('raw_material'),
            ),
          );

      // 5. Inactive product: should be excluded
      final p5 = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'منتج قديم موقوف',
              price: 10.0,
              quantity: 1,
              status: const Value('Inactive'),
            ),
          );

      // Simulate realistic daily sales over past 10 days
      for (int day = 0; day < 10; day++) {
        final invoiceDate = now.subtract(Duration(days: day));
        final invId = await db.into(db.invoices).insert(
              InvoicesCompanion.insert(
                invoiceNumber: Value('INV-TEST-$day'),
                totalAmount: const Value(350.0),
                date: Value(invoiceDate),
                status: const Value('paid'),
              ),
            );

        // P1: 5 units daily
        await db.into(db.invoiceItems).insert(
              InvoiceItemsCompanion.insert(
                invoiceId: invId,
                productId: p1,
                quantity: const Value(5),
                price: 35.0,
              ),
            );

        // P2: 2 units daily
        await db.into(db.invoiceItems).insert(
              InvoiceItemsCompanion.insert(
                invoiceId: invId,
                productId: p2,
                quantity: const Value(2),
                price: 70.0,
              ),
            );

        // P3: 2 units daily
        await db.into(db.invoiceItems).insert(
              InvoiceItemsCompanion.insert(
                invoiceId: invId,
                productId: p3,
                quantity: const Value(2),
                price: 180.0,
              ),
            );
      }

      // Add a voided invoice with huge quantity — must NOT inflate velocity
      final voidedInvId = await db.into(db.invoices).insert(
            InvoicesCompanion.insert(
              invoiceNumber: const Value('INV-VOIDED-1'),
              totalAmount: const Value(3500.0),
              date: Value(now.subtract(const Duration(days: 1))),
              status: const Value('voided'),
            ),
          );
      await db.into(db.invoiceItems).insert(
            InvoiceItemsCompanion.insert(
              invoiceId: voidedInvId,
              productId: p1,
              quantity: const Value(100),
              price: 35.0,
            ),
          );

      final service = PredictiveStockService(db);
      final results = await service.analyzeStockRunRate();

      // Verify raw material and inactive products are excluded
      expect(results.any((r) => r.productId == p4), isFalse);
      expect(results.any((r) => r.productId == p5), isFalse);

      // Verify P2 is out_of_stock
      final p2Result = results.firstWhere((r) => r.productId == p2);
      expect(p2Result.urgency, equals('out_of_stock'));
      expect(p2Result.suggestedReorderQuantity, greaterThan(0));

      // Verify P1 is critical (10 stock / 5 daily = ~2 days)
      final p1Result = results.firstWhere((r) => r.productId == p1);
      expect(p1Result.urgency, equals('critical'));
      expect(p1Result.daysUntilStockout, inInclusiveRange(1.5, 3.0));
      expect(p1Result.dailyVelocity, inInclusiveRange(4.0, 5.5)); // Unaffected by 100 voided units!

      // Verify P3 is healthy
      final p3Result = results.firstWhere((r) => r.productId == p3);
      expect(p3Result.urgency, equals('healthy'));
    });

    test('supports product variants accurately', () async {
      final now = DateTime.now();

      final parentProduct = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'قميص رجالي',
              price: 250.0,
              quantity: 102, // Total parent stock
              status: const Value('Active'),
            ),
          );

      // Variant 1: Size L (Best seller, only 2 left)
      final vL = await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              productId: parentProduct,
              name: 'مقاس L أزرق',
              quantity: const Value(2),
              price: const Value(250.0),
            ),
          );

      // Variant 2: Size XXL (Dead stock, 100 left)
      final vXXL = await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              productId: parentProduct,
              name: 'مقاس XXL أصفر',
              quantity: const Value(100),
              price: const Value(250.0),
            ),
          );

      // Simulate sales for Variant L only
      for (int day = 0; day < 5; day++) {
        final invId = await db.into(db.invoices).insert(
              InvoicesCompanion.insert(
                invoiceNumber: Value('INV-VAR-$day'),
                totalAmount: const Value(500.0),
                date: Value(now.subtract(Duration(days: day))),
                status: const Value('paid'),
              ),
            );
        await db.into(db.invoiceItems).insert(
              InvoiceItemsCompanion.insert(
                invoiceId: invId,
                productId: parentProduct,
                variantId: Value(vL),
                quantity: const Value(2),
                price: 250.0,
              ),
            );
      }

      final service = PredictiveStockService(db);
      final results = await service.analyzeStockRunRate();

      final vLResult = results.firstWhere((r) => r.variantId == vL);
      final vXXLResult = results.firstWhere((r) => r.variantId == vXXL);

      expect(vLResult.urgency, equals('critical')); // 2 in stock, 2 sold daily = ~1 day!
      expect(vXXLResult.urgency, equals('healthy')); // 100 in stock, 0 sold
    });
  });

  group('FinancialAnomalyService — Adaptive Shift Anomaly Detection', () {
    test('detects high return rate spikes and sequential refunds in shift', () async {
      final now = DateTime.now();
      final shiftStart = now.subtract(const Duration(hours: 3));

      // 1. Seed historical 30-day baseline: 50 invoices, low return rate (~2%)
      for (int i = 1; i <= 50; i++) {
        await db.into(db.invoices).insert(
              InvoicesCompanion.insert(
                invoiceNumber: Value('HIST-$i'),
                totalAmount: const Value(500.0),
                date: Value(now.subtract(Duration(days: 5 + (i % 20)))),
                status: const Value('paid'),
                returnedAmount: Value(i == 10 ? 100.0 : 0.0),
              ),
            );
      }

      // 2. Shift with severe return spike: Total sales 2,000, but returns 1,200 (return rate ~ 37%)
      for (int i = 1; i <= 6; i++) {
        await db.into(db.invoices).insert(
              InvoicesCompanion.insert(
                invoiceNumber: Value('SHIFT-SALE-$i'),
                totalAmount: const Value(400.0),
                date: Value(shiftStart.add(Duration(minutes: i * 20))),
                status: const Value('paid'),
              ),
            );
      }

      // 3 rapid consecutive refunds within 25 minutes
      for (int i = 1; i <= 3; i++) {
        await db.into(db.invoices).insert(
              InvoicesCompanion.insert(
                invoiceNumber: Value('SHIFT-RET-$i'),
                totalAmount: const Value(0.0),
                returnedAmount: const Value(400.0),
                date: Value(shiftStart.add(Duration(minutes: 70 + (i * 8)))),
                status: const Value('paid'),
              ),
            );
      }

      final service = FinancialAnomalyService(db);
      final anomalies = await service.checkSessionAnomalies(
        sessionStartTime: shiftStart,
        sessionEndTime: now,
      );

      expect(anomalies, isNotEmpty);
      expect(anomalies.any((a) => a.type == 'high_returns'), isTrue);
      expect(anomalies.any((a) => a.type == 'sequential_refunds'), isTrue);
    });

    test('ignores small sample sizes without triggering false alarms', () async {
      final now = DateTime.now();
      final shiftStart = now.subtract(const Duration(minutes: 30));

      // Only 2 invoices in total (1 sale, 1 return). Must NOT trigger false alarm.
      await db.into(db.invoices).insert(
            InvoicesCompanion.insert(
              invoiceNumber: const Value('INV-SMALL-1'),
              totalAmount: const Value(100.0),
              date: Value(shiftStart.add(const Duration(minutes: 5))),
              status: const Value('paid'),
            ),
          );
      await db.into(db.invoices).insert(
            InvoicesCompanion.insert(
              invoiceNumber: const Value('INV-SMALL-2'),
              totalAmount: const Value(0.0),
              returnedAmount: const Value(100.0),
              date: Value(shiftStart.add(const Duration(minutes: 10))),
              status: const Value('paid'),
            ),
          );

      final service = FinancialAnomalyService(db);
      final anomalies = await service.checkSessionAnomalies(
        sessionStartTime: shiftStart,
        sessionEndTime: now,
      );

      expect(anomalies, isEmpty);
    });
  });

  group('CustomerRetentionService — Individual Cadence Fingerprinting', () {
    test('detects customers who broke their buying cadence with outstanding debt', () async {
      final now = DateTime.now();

      // Customer 1: Regular restaurant client, buys every 3 days. Last buy was 20 days ago!
      await db.into(db.customers).insert(
            CustomersCompanion.insert(
              id: 'CUST-REGULAR-1',
              name: 'مطعم الأهرام',
              phone: const Value('01011112222'),
              totalDebt: const Value(1500.0),
              totalPaid: const Value(200.0), // Net debt 1,300
              status: const Value('Active'),
            ),
          );

      // Invoices spaced 3 days apart (50 to 20 days ago)
      for (int i = 0; i < 6; i++) {
        await db.into(db.invoices).insert(
              InvoicesCompanion.insert(
                customerId: const Value('CUST-REGULAR-1'),
                totalAmount: const Value(800.0),
                date: Value(now.subtract(Duration(days: 38 - (i * 3)))), // Last was 20 days ago
                status: const Value('paid'),
              ),
            );
      }

      // Customer 2: Monthly wholesale buyer, buys every 28 days. Last buy was 15 days ago (normal!).
      await db.into(db.customers).insert(
            CustomersCompanion.insert(
              id: 'CUST-MONTHLY-2',
              name: 'تاجر التجزئة الحديث',
              totalDebt: const Value(0.0),
              totalPaid: const Value(0.0),
              status: const Value('Active'),
            ),
          );

      await db.into(db.invoices).insert(
            InvoicesCompanion.insert(
              customerId: const Value('CUST-MONTHLY-2'),
              totalAmount: const Value(5000.0),
              date: Value(now.subtract(const Duration(days: 43))),
              status: const Value('paid'),
            ),
          );
      await db.into(db.invoices).insert(
            InvoicesCompanion.insert(
              customerId: const Value('CUST-MONTHLY-2'),
              totalAmount: const Value(5000.0),
              date: Value(now.subtract(const Duration(days: 15))),
              status: const Value('paid'),
            ),
          );

      final service = CustomerRetentionService(db);
      final atRisk = await service.analyzeCustomerCadences();

      // Customer 1 must be flagged
      expect(atRisk.any((c) => c.customerId == 'CUST-REGULAR-1'), isTrue);
      final c1 = atRisk.firstWhere((c) => c.customerId == 'CUST-REGULAR-1');
      expect(c1.riskLevel, equals('high'));
      expect(c1.outstandingDebt, equals(1300.0));

      // Customer 2 is on schedule, must NOT be flagged
      expect(atRisk.any((c) => c.customerId == 'CUST-MONTHLY-2'), isFalse);
    });
  });

  group('SmartAdvisorService — Orchestration, Deduplication & Briefing', () {
    test('runs suite, updates notifications without duplicating, marks read and generates brief', () async {
      final now = DateTime.now();

      // Seed a low stock product
      final p = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'جبنة شيدر مستوردة',
              price: 120.0,
              quantity: 1, // Only 1 left
              status: const Value('Active'),
            ),
          );

      // Seed sales
      for (int i = 0; i < 5; i++) {
        final invId = await db.into(db.invoices).insert(
              InvoicesCompanion.insert(
                totalAmount: const Value(240.0),
                date: Value(now.subtract(Duration(days: i))),
                status: const Value('paid'),
              ),
            );
        await db.into(db.invoiceItems).insert(
              InvoiceItemsCompanion.insert(
                invoiceId: invId,
                productId: p,
                quantity: const Value(2),
                price: 120.0,
              ),
            );
      }

      final advisor = SmartAdvisorService(db);

      // First run: should generate notifications
      await advisor.runAutomaticAnalysis(force: true);
      final alerts1 = await advisor.getActiveAlerts();
      expect(alerts1, isNotEmpty);
      final initialCount = alerts1.length;

      // Second run: must deduplicate and NOT create double rows
      await advisor.runAutomaticAnalysis(force: true);
      final alerts2 = await advisor.getActiveAlerts();
      expect(alerts2.length, equals(initialCount));

      // Test mark as read
      final firstAlert = alerts2.first;
      await advisor.markAlertAsRead(firstAlert.id);
      final unreadCount = await advisor.getUnreadCount();
      expect(unreadCount, equals(initialCount - 1));

      // Test executive brief generation (100% offline fallback)
      final brief = await advisor.generateExecutiveBrief();
      expect(brief, contains('ملخص الأداء والمستشار الذكي'));
      expect(brief, contains('جبنة شيدر'));
    });
  });
}
