import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/empty_barnika_tracking_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/vegetable_shipment_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/empty_barnika_tracking_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/shipment_allocation_service.dart';

const _supplierId = 'SUP-TEST';
const _customerId = 'CUST-TEST';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  late AppDatabase db;
  late VegetableShipmentDao shipmentDao;
  late EmptyBarnikaTrackingDao emptyBarnikaDao;
  late ShipmentAllocationService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    shipmentDao = db.vegetableShipmentDao;
    emptyBarnikaDao = db.emptyBarnikaTrackingDao;
    service = ShipmentAllocationService(shipmentDao, emptyBarnikaDao);

    await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(id: _supplierId, name: 'مورّد اختبار'),
        );
    await db.customerDao.insertCustomer(
      CustomersCompanion.insert(id: _customerId, name: 'عميل اختبار'),
    );
  });

  tearDown(() => db.close());

  Future<int> insertShipment({
    required String number,
    required int total,
    required DateTime date,
    int? remaining,
  }) {
    return shipmentDao.insertShipment(
      VegetableShipmentsCompanion.insert(
        supplierId: _supplierId,
        shipmentNumber: number,
        date: Value(date),
        pricingMode: ShipmentPricingMode.perUnit,
        totalBarnikaCount: total,
        costPricePerBarnika: const Value(5),
        totalCost: 5.0 * total,
        barnikaRemainingCount: remaining ?? total,
      ),
    );
  }

  group('ShipmentAllocationService.allocate - FIFO', () {
    test('deducts from oldest open shipment when quantity fits in it', () async {
      final oldest = await insertShipment(
        number: 'S-OLD',
        total: 10,
        date: DateTime(2026, 1, 1),
      );
      await insertShipment(
        number: 'S-NEW',
        total: 20,
        date: DateTime(2026, 1, 2),
      );

      final result = await service.allocate(requestedQuantity: 6);

      expect(result, hasLength(1));
      expect(result.single.shipmentId, oldest);
      expect(result.single.quantity, 6);
    });

    test('deducts across multiple open shipments when quantity exceeds the first', () async {
      final first = await insertShipment(
        number: 'S-1',
        total: 10,
        date: DateTime(2026, 1, 1),
      );
      final second = await insertShipment(
        number: 'S-2',
        total: 20,
        date: DateTime(2026, 1, 2),
      );

      final result = await service.allocate(requestedQuantity: 15);

      expect(result, hasLength(2));
      expect(result[0].shipmentId, first);
      expect(result[0].quantity, 10);
      expect(result[1].shipmentId, second);
      expect(result[1].quantity, 5);
    });

    test('skips shipments whose remaining count is zero', () async {
      await insertShipment(
        number: 'S-EMPTY',
        total: 10,
        date: DateTime(2026, 1, 1),
        remaining: 0,
      );
      final open = await insertShipment(
        number: 'S-OPEN',
        total: 10,
        date: DateTime(2026, 1, 2),
      );

      final result = await service.allocate(requestedQuantity: 3);

      expect(result.single.shipmentId, open);
      expect(result.single.quantity, 3);
    });

    test('throws ArgumentError when requestedQuantity is zero', () async {
      await expectLater(
        service.allocate(requestedQuantity: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when requestedQuantity is negative', () async {
      await expectLater(
        service.allocate(requestedQuantity: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when requestedQuantity exceeds total available remaining', () async {
      await insertShipment(
        number: 'S-1',
        total: 3,
        date: DateTime(2026, 1, 1),
      );
      await insertShipment(
        number: 'S-2',
        total: 4,
        date: DateTime(2026, 1, 2),
      );

      await expectLater(
        service.allocate(requestedQuantity: 8),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when no shipments exist', () async {
      await expectLater(
        service.allocate(requestedQuantity: 1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ShipmentAllocationService.allocate - manual override', () {
    test('draws only from the specified shipment', () async {
      await insertShipment(
        number: 'S-1',
        total: 10,
        date: DateTime(2026, 1, 1),
      );
      final target = await insertShipment(
        number: 'S-2',
        total: 20,
        date: DateTime(2026, 1, 2),
      );

      final result = await service.allocate(
        requestedQuantity: 7,
        overrideShipmentId: target,
      );

      expect(result, hasLength(1));
      expect(result.single.shipmentId, target);
      expect(result.single.quantity, 7);
    });

    test('throws ArgumentError when override shipment does not exist', () async {
      await insertShipment(
        number: 'S-1',
        total: 10,
        date: DateTime(2026, 1, 1),
      );

      await expectLater(
        service.allocate(requestedQuantity: 1, overrideShipmentId: 999999),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when override shipment has insufficient remaining', () async {
      final target = await insertShipment(
        number: 'S-1',
        total: 10,
        date: DateTime(2026, 1, 1),
        remaining: 2,
      );

      await expectLater(
        service.allocate(requestedQuantity: 5, overrideShipmentId: target),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ShipmentAllocationService.totalRemaining', () {
    test('returns 0 when no shipments exist', () async {
      expect(await service.totalRemaining(), 0);
    });

    test('returns the sum of remaining counts across open shipments', () async {
      await insertShipment(
        number: 'S-1',
        total: 10,
        date: DateTime(2026, 1, 1),
      );
      await insertShipment(
        number: 'S-2',
        total: 20,
        date: DateTime(2026, 1, 2),
        remaining: 7,
      );
      await insertShipment(
        number: 'S-EMPTY',
        total: 5,
        date: DateTime(2026, 1, 3),
        remaining: 0,
      );

      expect(await service.totalRemaining(), 17);
    });
  });

  group('ShipmentAllocationService.recordBarnikaOut', () {
    test('inserts an outstanding record with zero returned quantity', () async {
      final dateOut = DateTime(2026, 2, 1);
      final id = await service.recordBarnikaOut(
        customerId: _customerId,
        quantity: 4,
        dateOut: dateOut,
      );

      final record = await emptyBarnikaDao.getById(id);
      expect(record, isNotNull);
      expect(record!.customerId, _customerId);
      expect(record.quantityOut, 4);
      expect(record.quantityReturned, 0);
      expect(record.status, EmptyBarnikaStatus.outstanding);
      expect(record.dateOut, dateOut);
    });

    test('throws ArgumentError when quantity is zero', () async {
      await expectLater(
        service.recordBarnikaOut(customerId: _customerId, quantity: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when quantity is negative', () async {
      await expectLater(
        service.recordBarnikaOut(customerId: _customerId, quantity: -3),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when customerId is empty', () async {
      await expectLater(
        service.recordBarnikaOut(customerId: '', quantity: 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('links invoiceId when provided and supports FIFO customer return', () async {
      final invId = await db.invoiceDao.insertInvoice(
        InvoicesCompanion.insert(
          customerId: const Value(_customerId),
          customerName: const Value('عميل اختبار'),
          totalAmount: const Value(500),
        ),
      );
      final id1 = await service.recordBarnikaOut(
        customerId: _customerId,
        quantity: 6,
        dateOut: DateTime(2026, 2, 1),
        invoiceId: invId,
      );
      final id2 = await service.recordBarnikaOut(
        customerId: _customerId,
        quantity: 4,
        dateOut: DateTime(2026, 2, 2),
      );

      final rec1 = await emptyBarnikaDao.getById(id1);
      expect(rec1!.invoiceId, invId);
      expect(
        await emptyBarnikaDao.getCustomerOutstandingBalance(_customerId),
        10,
      );

      await service.recordCustomerBarnikaReturn(
        customerId: _customerId,
        quantityReturned: 8,
        dateReturned: DateTime(2026, 2, 3),
      );

      final after1 = await emptyBarnikaDao.getById(id1);
      final after2 = await emptyBarnikaDao.getById(id2);
      expect(after1!.status, EmptyBarnikaStatus.returned);
      expect(after1.quantityReturned, 6);
      expect(after2!.status, EmptyBarnikaStatus.partial);
      expect(after2.quantityReturned, 2);
      expect(
        await emptyBarnikaDao.getCustomerOutstandingBalance(_customerId),
        2,
      );

      await expectLater(
        service.recordCustomerBarnikaReturn(
          customerId: _customerId,
          quantityReturned: 3,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('ShipmentAllocationService topping & closed guards', () {
    test('recordTopping reduces effective remaining and prevents overselling', () async {
      final id = await insertShipment(
        number: 'S-TOP-1',
        total: 20,
        date: DateTime(2026, 2, 1),
      );

      final updated = await service.recordTopping(
        shipmentId: id,
        additionalToppingCount: 3,
        reason: 'تكميل وزن الصناديق الناقصة',
      );

      expect(updated.toppingCount, 3);
      expect(updated.toppingReason, 'تكميل وزن الصناديق الناقصة');
      expect(updated.barnikaRemainingCount, 17);
      expect(await service.totalRemaining(), 17);

      // Overselling above 17 must be rejected.
      await expectLater(
        service.allocate(requestedQuantity: 18, overrideShipmentId: id),
        throwsA(isA<ArgumentError>()),
      );

      // Selling exact remaining 17 succeeds.
      final allocated = await service.allocate(
        requestedQuantity: 17,
        overrideShipmentId: id,
      );
      expect(allocated.single.quantity, 17);
    });

    test('recordTopping throws when exceeding available remaining', () async {
      final id = await insertShipment(
        number: 'S-TOP-OVER',
        total: 5,
        date: DateTime(2026, 2, 1),
      );

      await expectLater(
        service.recordTopping(shipmentId: id, additionalToppingCount: 6),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('closed shipments are excluded from FIFO, manual allocation, and topping', () async {
      final id = await insertShipment(
        number: 'S-CLOSED',
        total: 10,
        date: DateTime(2026, 2, 1),
      );
      await (db.update(db.vegetableShipments)..where((t) => t.id.equals(id)))
          .write(
        const VegetableShipmentsCompanion(
          status: Value(VegetableShipmentStatus.closed),
        ),
      );

      expect(await service.totalRemaining(), 0);
      await expectLater(
        service.allocate(requestedQuantity: 1, overrideShipmentId: id),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        service.recordTopping(shipmentId: id, additionalToppingCount: 1),
        throwsA(isA<StateError>()),
      );
    });
  });
}
