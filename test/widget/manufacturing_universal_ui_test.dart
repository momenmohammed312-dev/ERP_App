import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_inspections_table.dart';
import 'package:pos_offline_desktop/core/database/tables/routing_tables.dart';
import 'package:pos_offline_desktop/ui/manufacturing/reports/widgets/manufacturing_yield_quality_tab.dart';
import 'package:pos_offline_desktop/ui/manufacturing/routing_templates_screen.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/mo_costing_approvals_section.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/mo_routing_quality_section.dart';

import '../helpers/license_grant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  late AppDatabase db;
  late int orderId;
  late ManufacturingOrder order;
  late List<ManufacturingStage> stages;
  late Map<int, String> productNames;

  setUp(() async {
    grantLicensedModules();
    db = AppDatabase(NativeDatabase.memory());

    await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'cust-ui-1', name: 'عميل واجهات التصنيع'),
        );
    final finId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'جاكيت مطبوع مبطن',
            price: 300,
            costPrice: const Value(180),
            quantity: 0,
          ),
        );
    final rawId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'قماش وتربروف',
            price: 90,
            costPrice: const Value(65),
            quantity: 50,
          ),
        );
    final extraId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'سوستة معدنية ثقيلة',
            price: 15,
            costPrice: const Value(10),
            quantity: 100,
          ),
        );
    final bomId = await db.bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finId),
        name: const Value('BOM Jacket'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(rawId),
          quantityRequired: const Value(2.0),
        ),
      ],
    );
    orderId = await db.manufacturingOrderDao.createOrder(
      ManufacturingOrdersCompanion(
        orderNumber: const Value('MO-UI-2026'),
        bomId: Value(bomId),
        finishedProductId: Value(finId),
        plannedQuantity: const Value(40),
        orderType: const Value('for_others'),
        customerId: const Value('cust-ui-1'),
        serviceUnitPrice: const Value(75),
      ),
    );

    final tplId = await db.routingDao.createTemplate(
      code: 'RT-JACKET-01',
      name: 'مسار الجاكيت المتكامل',
    );
    final cutNode = await db.routingDao.addTemplateNode(
      templateId: tplId,
      stageOrder: 1,
      name: 'القص',
      operationType: RoutingOperationType.machining,
      defaultLaborRate: 30,
    );
    await db.routingDao.addTemplateNode(
      templateId: tplId,
      parentNodeId: cutNode,
      stageOrder: 2,
      name: 'تقفيل نهائي',
      operationType: RoutingOperationType.finishing,
      defaultLaborRate: 25,
      isTerminal: true,
    );
    await db.routingDao.applyTemplateToOrder(templateId: tplId, orderId: orderId);

    stages = await db.manufacturingStageDao.getStagesForOrder(orderId);
    await db.externalOperationDao.insertExternalOperationRecord(
      manufacturingOrderId: orderId,
      operationId: stages.first.id,
      vendor: 'ورشة النور للكي',
      sentQty: 20,
      receivedQty: 15,
      cost: 120,
    );
    await db.manufacturingInspectionDao.recordInspection(
      orderId: orderId,
      stageId: stages.last.id,
      productId: finId,
      inspectedBy: 'المشرف طارق',
      result: InspectionResult.accepted,
      quantity: 38,
    );
    final req = await db.manufacturingCostingDao.requestExtraMaterial(
      orderId: orderId,
      productId: extraId,
      quantity: 5,
      requestedBy: 'المشرف طارق',
    );
    await db.manufacturingCostingDao.approveExtraMaterial(
      approvalId: req.id,
      approvedBy: 'العميل',
      authorizationRef: 'AUTH-99',
    );

    order = (await db.manufacturingOrderDao.getById(orderId))!;
    productNames = {
      finId: 'جاكيت مطبوع مبطن',
      rawId: 'قماش وتربروف',
      extraId: 'سوستة معدنية ثقيلة',
    };
  });

  tearDown(() async {
    revokeLicensedModules();
    await db.close();
  });

  Widget wrapResponsive(ThemeData theme, Widget child) {
    return MaterialApp(
      theme: theme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );
  }

  Future<void> pumpDriftUi(WidgetTester tester) async {
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  for (final spec in [
    (name: 'Mobile Light', size: const Size(360, 800), theme: ThemeData.light()),
    (name: 'Mobile Dark', size: const Size(360, 800), theme: ThemeData.dark()),
    (name: 'Desktop Light', size: const Size(1200, 800), theme: ThemeData.light()),
    (name: 'Desktop Dark', size: const Size(1200, 800), theme: ThemeData.dark()),
  ]) {
    testWidgets('RoutingTemplatesScreen renders cleanly on ${spec.name}', (tester) async {
      tester.view.physicalSize = spec.size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: spec.theme,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: RoutingTemplatesScreen(db: db),
          ),
        ),
      );
      await pumpDriftUi(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('قوالب مسارات الإنتاج (Routing)'), findsOneWidget);
      expect(find.text('مسار الجاكيت المتكامل'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });

    testWidgets('MoRoutingQualitySection + MoCostingApprovalsSection + YieldQualityTab render without overflow on ${spec.name}', (tester) async {
      tester.view.physicalSize = spec.size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        wrapResponsive(
          spec.theme,
          SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                MoRoutingQualitySection(
                  db: db,
                  order: order,
                  stages: stages,
                  onDataChanged: () {},
                ),
                const SizedBox(height: 16),
                MoCostingApprovalsSection(
                  db: db,
                  order: order,
                  balanceProductNames: productNames,
                  onDataChanged: () {},
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 600,
                  child: ManufacturingYieldQualityTab(
                    db: db,
                    range: DateTimeRange(
                      start: DateTime.now().subtract(const Duration(days: 7)),
                      end: DateTime.now().add(const Duration(days: 1)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await pumpDriftUi(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('التوجيه العام، الورش الخارجية والجودة'), findsOneWidget);
      expect(find.text('ورشة النور للكي'), findsOneWidget);
      expect(find.text('سوستة معدنية ثقيلة'), findsOneWidget);
      expect(find.text('معتمد للفاتورة'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  }
}
