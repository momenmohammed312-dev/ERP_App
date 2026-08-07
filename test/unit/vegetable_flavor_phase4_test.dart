import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/empty_barnika_tracking_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/vegetable_shipment_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/empty_barnika_tracking_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/shipment_allocation_service.dart';
import 'package:pos_offline_desktop/core/services/shipment_pricing_service.dart';

const supplierId = 'SUP-1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  late AppDatabase db;
  late VegetableShipmentDao shipmentDao;
  late EmptyBarnikaTrackingDao emptyDao;
  late ShipmentAllocationService allocation;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    shipmentDao = db.vegetableShipmentDao;
    emptyDao = db.emptyBarnikaTrackingDao;
    allocation = ShipmentAllocationService(shipmentDao, emptyDao);
    await db.into(db.suppliers).insert(
      SuppliersCompanion.insert(id: supplierId, name: 'مورّد'),
    );
    await db.customerDao.insertCustomer(
      CustomersCompanion.insert(id: 'C-1', name: 'عميل'),
    );
  });

  tearDown(() => db.close());

  Future<int> insertShipment({
    required String number,
    required String pricingMode,
    required int total,
    DateTime? date,
    double? costPricePerBarnika,
    double? lumpSumCost,
    double? commissionPercentage,
    int? remaining,
  }) {
    return shipmentDao.insertShipment(
      VegetableShipmentsCompanion.insert(
        supplierId: supplierId,
        shipmentNumber: number,
        date: Value(date ?? DateTime(2026, 1, 1)),
        pricingMode: pricingMode,
        totalBarnikaCount: total,
        costPricePerBarnika: Value(costPricePerBarnika),
        lumpSumCost: Value(lumpSumCost),
        commissionPercentage: Value(commissionPercentage),
        totalCost: costPricePerBarnika ?? lumpSumCost ?? 0,
        barnikaRemainingCount: remaining ?? total,
      ),
    );
  }

  group('ShipmentAllocationService FIFO', () {
    test('allocates across multiple shipments oldest-first', () async {
      final a = await insertShipment(
        number: 'S-1',
        pricingMode: ShipmentPricingMode.perUnit,
        total: 10,
        date: DateTime(2026, 1, 1),
        costPricePerBarnika: 5,
      );
      await insertShipment(
        number: 'S-2',
        pricingMode: ShipmentPricingMode.perUnit,
        total: 20,
        date: DateTime(2026, 1, 2),
        costPricePerBarnika: 5,
      );

      final result = await allocation.allocate(requestedQuantity: 15);

      expect(result.length, 2, reason: 'draw from both shipments');
      expect(result.first.shipmentId, a, reason: 'oldest drawn first fully');
      expect(result.first.quantity, 10);
      expect(result.last.quantity, 5);
    });

    test('throws when total available is insufficient', () async {
      await insertShipment(
        number: 'S-3',
        pricingMode: ShipmentPricingMode.perUnit,
        total: 3,
        costPricePerBarnika: 5,
      );

      await expectLater(
        allocation.allocate(requestedQuantity: 4),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('manual override draws from one shipment only', () async {
      final a = await insertShipment(
        number: 'S-1',
        pricingMode: ShipmentPricingMode.perUnit,
        total: 10,
        costPricePerBarnika: 5,
      );
      await insertShipment(
        number: 'S-2',
        pricingMode: ShipmentPricingMode.perUnit,
        total: 20,
        costPricePerBarnika: 5,
      );

      final result = await allocation.allocate(
        requestedQuantity: 7,
        overrideShipmentId: a,
      );
      expect(result.single.shipmentId, a);
      expect(result.single.quantity, 7);
    });

    test('manual override throws when shipment insufficient', () async {
      final a = await insertShipment(
        number: 'S-1',
        pricingMode: ShipmentPricingMode.perUnit,
        total: 2,
        costPricePerBarnika: 5,
      );

      await expectLater(
        allocation.allocate(requestedQuantity: 5, overrideShipmentId: a),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('zero quantity throws', () async {
      await expectLater(
        allocation.allocate(requestedQuantity: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ShipmentPricingService', () {
    test('per_unit cost', () {
      final shipment = _baseRow(costPricePerBarnika: 5);
      expect(ShipmentPricingService.calculateCost(shipment, 10), 50);
    });

    test('lump_sum cost averages across total count', () {
      final shipment = _baseRow(lumpSumCost: 100, total: 10);
      expect(ShipmentPricingService.calculateCost(shipment, 5), 50);
    });

    test('commission mode cost is 0 (shop does not own goods)', () {
      final shipment = _baseRow(commissionPercentage: 10);
      expect(ShipmentPricingService.calculateCost(shipment, 100), 0);
    });

    test('commission + supplier due', () {
      expect(ShipmentPricingService.calculateCommission(1000, 10), 100);
      expect(ShipmentPricingService.calculateSupplierDue(1000, 10), 900);
    });
  });

  group('EmptyBarnikaTrackingDao returns', () {
    test('status transitions outstanding -> partial -> returned', () async {
      final id = await emptyDao.insertRecord(
        EmptyBarnikaTrackingCompanion.insert(
          customerId: 'C-1',
          dateOut: DateTime(2026, 1, 3),
          quantityOut: 10,
        ),
      );

      var rec = await emptyDao.getById(id);
      expect(rec!.status, EmptyBarnikaStatus.outstanding);

      await emptyDao.recordReturn(id: id, quantityReturned: 4);
      rec = await emptyDao.getById(id);
      expect(rec!.status, EmptyBarnikaStatus.partial);
      expect(rec.quantityReturned, 4);

      await emptyDao.recordReturn(id: id, quantityReturned: 6);
      rec = await emptyDao.getById(id);
      expect(rec!.status, EmptyBarnikaStatus.returned);
      expect(rec.quantityReturned, 10);
    });

    test('over-return throws', () async {
      final id = await emptyDao.insertRecord(
        EmptyBarnikaTrackingCompanion.insert(
          customerId: 'C-1',
          dateOut: DateTime(2026, 1, 3),
          quantityOut: 5,
        ),
      );

      await expectLater(
        emptyDao.recordReturn(id: id, quantityReturned: 6),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('recordBarnikaOut', () {
    test('records an outstanding empty-barnika entry for the customer', () async {
      final id = await allocation.recordBarnikaOut(
        customerId: 'C-1',
        quantity: 7,
        dateOut: DateTime(2026, 1, 4),
      );

      final rec = await emptyDao.getById(id);
      expect(rec!.customerId, 'C-1');
      expect(rec.quantityOut, 7);
      expect(rec.status, EmptyBarnikaStatus.outstanding);
    });

    test('non-positive quantity throws', () async {
      await expectLater(
        allocation.recordBarnikaOut(customerId: 'C-1', quantity: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

VegetableShipment _baseRow({
  double? costPricePerBarnika,
  double? lumpSumCost,
  double? commissionPercentage,
  int total = 10,
}) =>
    VegetableShipment(
      id: 1,
      supplierId: supplierId,
      shipmentNumber: 'S-1',
      date: DateTime(2026, 1, 1),
      pricingMode: costPricePerBarnika != null
          ? ShipmentPricingMode.perUnit
          : lumpSumCost != null
              ? ShipmentPricingMode.lumpSum
              : ShipmentPricingMode.commission,
      totalBarnikaCount: total,
      costPricePerBarnika: costPricePerBarnika,
      lumpSumCost: lumpSumCost,
      commissionPercentage: commissionPercentage,
      containerPrice: null,
      totalCost: costPricePerBarnika ?? lumpSumCost ?? 0,
      barnikaSoldCount: 0,
      barnikaRemainingCount: total,
      notes: null,
    );
