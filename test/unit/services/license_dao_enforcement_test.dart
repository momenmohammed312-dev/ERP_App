import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/custody_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/damaged_items_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/cash_custody_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/damaged_items_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';
import 'package:pos_offline_desktop/services/license_entitlement.dart';

import '../../helpers/license_grant.dart';

/// BUG-017 — the DAOs themselves must refuse an unlicensed write.
///
/// Hiding a launcher button is not enforcement. These tests call the DAOs
/// directly — exactly the way a route, a background task or a future refactor
/// can reach them without going near the UI — and assert that the write is
/// refused, and that a refusal leaves the database untouched.
void main() {
  late AppDatabase db;
  late DamagedItemsDao damagedDao;
  late CustodyDao custodyDao;
  late ManufacturingOrderDao moDao;
  late int productId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    damagedDao = DamagedItemsDao(db);
    custodyDao = CustodyDao(db);
    moDao = ManufacturingOrderDao(db);
    // damaged_items.product_id is a foreign key, so a real row is needed.
    productId = await db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: 'صنف',
        quantity: 100,
        price: 50,
      ),
    );
    revokeLicensedModules();
  });

  tearDown(revokeLicensedModules);

  DamagedItemsCompanion newItem() =>
      DamagedItemsCompanion.insert(productId: productId, quantity: 5, unitCost: 10, totalLoss: 50, reason: 'damaged', damageDate: DateTime(2026, 1, 1));

  group('AC4 — an unlicensed write is refused', () {
    test('damaged goods: insert', () {
      expect(
        () => damagedDao.insertDamagedItem(newItem()),
        throwsA(isA<FeatureNotLicensedException>()),
      );
    });

    test('damaged goods: delete', () {
      expect(
        () => damagedDao.deleteDamagedItem(1),
        throwsA(isA<FeatureNotLicensedException>()),
      );
    });

    test('custody: insert', () {
      expect(
        () => custodyDao.insertCustody(
          CashCustodiesCompanion.insert(custodyNumber: 'C-1', staffId: '1', staffName: 'كاشير', date: DateTime(2026, 1, 1), amount: 1000, remainingAmount: 1000),
        ),
        throwsA(isA<FeatureNotLicensedException>()),
      );
    });

    test('manufacturing: create order', () {
      expect(
        () => moDao.createOrder(
          ManufacturingOrdersCompanion.insert(orderNumber: 'MO-1', bomId: 1, finishedProductId: 1, plannedQuantity: 10),
        ),
        throwsA(isA<FeatureNotLicensedException>()),
      );
    });

    test('manufacturing: status transitions are guarded too', () {
      // A licensed customer could otherwise reach these through any call site
      // that skipped creation.
      expect(
        () => moDao.startOrder(1),
        throwsA(isA<FeatureNotLicensedException>()),
      );
      expect(
        () => moDao.cancelOrder(1),
        throwsA(isA<FeatureNotLicensedException>()),
      );
      expect(
        () => moDao.deleteOrder(1),
        throwsA(isA<FeatureNotLicensedException>()),
      );
    });
  });

  group('AC5 — a licensed write behaves exactly as before', () {
    test('damaged goods: insert works when the feature is granted', () async {
      grantLicensedModules();
      final id = await damagedDao.insertDamagedItem(newItem());
      expect(id, greaterThan(0));
      final rows = await db.select(db.damagedItems).get();
      expect(rows, hasLength(1));
    });

    test('custody: insert works when the feature is granted', () async {
      grantLicensedModules();
      await custodyDao.insertCustody(
        CashCustodiesCompanion.insert(custodyNumber: 'C-1', staffId: '1', staffName: 'كاشير', date: DateTime(2026, 1, 1), amount: 1000, remainingAmount: 1000),
      );
      final rows = await db.select(db.cashCustodies).get();
      expect(rows, hasLength(1));
    });

    test('granting one module does not grant another', () {
      grantLicensedModules(['manufacturing']);
      expect(
        () => damagedDao.insertDamagedItem(newItem()),
        throwsA(isA<FeatureNotLicensedException>()),
        reason: 'paying for manufacturing must not buy damaged-goods',
      );
    });
  });

  group('AC8 — a refusal never leaves a partial write', () {
    test('no row is created when the write is refused', () async {
      expect(
        () => damagedDao.insertDamagedItem(newItem()),
        throwsA(isA<FeatureNotLicensedException>()),
      );
      expect(await db.select(db.damagedItems).get(), isEmpty,
          reason: 'the guard must refuse BEFORE the statement, not roll back');
    });

    test('no custody row is created when the write is refused', () async {
      expect(
        () => custodyDao.insertCustody(
          CashCustodiesCompanion.insert(custodyNumber: 'C-1', staffId: '1', staffName: 'كاشير', date: DateTime(2026, 1, 1), amount: 1000, remainingAmount: 1000),
        ),
        throwsA(isA<FeatureNotLicensedException>()),
      );
      expect(await db.select(db.cashCustodies).get(), isEmpty);
    });

    test('an existing row survives a refused update', () async {
      grantLicensedModules();
      final id = await damagedDao.insertDamagedItem(newItem());

      revokeLicensedModules();
      expect(
        () => damagedDao.updateDamagedItem(
          DamagedItemsCompanion(
            id: Value(id),
            quantity: const Value(999),
          ),
        ),
        throwsA(isA<FeatureNotLicensedException>()),
      );

      final rows = await db.select(db.damagedItems).get();
      expect(rows.single.quantity, 5,
          reason: 'the refused update must not have touched the row');
    });
  });

  group('the refusal explains itself', () {
    test('the message names the module in Arabic, not the internal key', () {
      grantLicensedModules(['pos']);
      try {
        damagedDao.insertDamagedItem(newItem());
        fail('should have thrown');
      } on FeatureNotLicensedException catch (e) {
        expect(e.feature, 'damaged_goods');
        expect(e.toString(), contains('التالف'));
        expect(e.toString(), isNot(contains('damaged_goods')),
            reason: 'an Arabic-speaking operator should never be shown a key');
      }
    });
  });
}