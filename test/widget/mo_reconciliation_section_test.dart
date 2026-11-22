import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/reconciliation_dao.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/mo_reconciliation_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildHarness({
    required ThemeData theme,
    List<String> violations = const [],
  }) {
    final now = DateTime(2026, 11, 22, 14, 30);
    final order = ManufacturingOrder(
      id: 1,
      orderNumber: 'MO-2026-0099',
      bomId: 1,
      finishedProductId: 10,
      plannedQuantity: 100,
      producedQuantity: 90,
      status: 'completed',
      orderType: 'for_others',
      customerId: 'cust-1',
      pricingMode: 'inclusive',
      scrapPolicy: 'customer_bears',
      pieceUnitValue: 50,
      serviceUnitPrice: 20,
      deliveryStatus: 'partially_delivered',
      productionCompletedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    final customer = Customer(
      id: 'cust-1',
      name: 'مصنع النور للمنسوجات — اسم عميل طويل لاختبار الالتفاف',
      openingBalance: 0,
      totalDebt: 0,
      totalPaid: 0,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    final orderMovements = [
      CustomerStockMovement(
        id: 11,
        customerId: 'cust-1',
        productId: 5,
        movementType: 'issued_to_order',
        quantity: -200,
        referenceType: 'manufacturing_order',
        referenceId: 'MO-2026-0099',
        createdAt: now,
      ),
    ];
    final balances = [
      CustomerStockBalance(
        id: 21,
        customerId: 'cust-1',
        productId: 5,
        color: 'أزرق',
        size: 'L',
        quantityOnHand: 45,
        quantityAllocated: 5,
        updatedAt: now,
      ),
    ];
    final summary = ReconciliationSummary(
      custody: {
        5: CustodyLine(
          productId: 5,
          issued: 200,
          consumed: 180,
          returnedExcess: 10,
        ),
      },
      returnedOutputs: 0,
      scrapped: 0,
      atVendor: 0,
      produced: 90,
      remainingWip: 0,
      hasReconciliationData: false,
    );
    final consumptionRecords = [
      ConsumptionRecord(
        id: 31,
        manufacturingOrderId: 1,
        materialProductId: 5,
        ownershipType: 'customer_owned',
        unit: 'متر',
        plannedQty: 200,
        actualQty: 180,
        unitCostSnapshot: 0,
        customerStockMovementId: 11,
        performedAt: now,
      ),
      ConsumptionRecord(
        id: 32,
        manufacturingOrderId: 1,
        materialProductId: 6,
        ownershipType: 'factory_owned',
        unit: 'علبة',
        plannedQty: 5,
        actualQty: 5,
        unitCostSnapshot: 40,
        stockMovementId: 77,
        performedAt: now,
      ),
    ];

    return MaterialApp(
      theme: theme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MoReconciliationSection(
              db: db,
              order: order,
              customer: customer,
              deliveredQty: 40,
              orderMovements: orderMovements,
              customerBalances: balances,
              orderBalanceIds: const {5},
              balanceProductNames: const {
                5: 'قماش قطن مشطّب ممتاز',
                6: 'حبر طباعة سلك سكرين',
              },
              reconciliationSummary: summary,
              custodyViolations: violations,
              consumptionRecords: consumptionRecords,
              onDataChanged: () {},
            ),
          ),
        ),
      ),
    );
  }

  for (final spec in [
    (name: 'Mobile Light', size: const Size(360, 800), theme: ThemeData.light(), isMobile: true),
    (name: 'Mobile Dark', size: const Size(360, 800), theme: ThemeData.dark(), isMobile: true),
    (name: 'Desktop Light', size: const Size(1200, 800), theme: ThemeData.light(), isMobile: false),
    (name: 'Desktop Dark', size: const Size(1200, 800), theme: ThemeData.dark(), isMobile: false),
  ]) {
    testWidgets('renders cleanly without overflow on ${spec.name}', (tester) async {
      tester.view.physicalSize = spec.size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildHarness(
          theme: spec.theme,
          violations: const ['Custody violation test sample'],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.text('بطاقة مطابقة الخامات والتشغيل (Reconciliation)'),
        findsOneWidget,
      );
      expect(find.text('قماش قطن مشطّب ممتاز'), findsWidgets);
      expect(find.textContaining('#C-11', findRichText: true), findsOneWidget);
      expect(find.textContaining('#I-77', findRichText: true), findsOneWidget);
      expect(
        find.text(spec.isMobile ? 'إرجاع فائض للعهدة' : 'إرجاع فائض'),
        findsOneWidget,
      );
      expect(find.text('رد للعميل'), findsOneWidget);
    });
  }

  testWidgets('excess return dialog opens cleanly without overflow on Mobile Dark (360x800)', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildHarness(theme: ThemeData.dark()));
    await tester.pumpAndSettle();

    final btn = find.text('إرجاع فائض للعهدة');
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('إرجاع فائض خامات للعهدة'), findsOneWidget);
    expect(find.text('تأكيد الإرجاع'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
  });
}
