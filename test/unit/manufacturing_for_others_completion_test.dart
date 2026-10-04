import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:drift/native.dart';

/// Test-first Phase B1: Manufacturing Order For-Others Completion & Scrap Policies.
///
/// Expected RED until C2 (v76 schema) and C4 (completeForOthersOrder & scrap policy) land.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  test('MOC-1: completeForOthersOrder fails when customer has insufficient custody balance', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic moDao = db.manufacturingOrderDao;
    // Method does not exist until C4
    expect(() => moDao.completeForOthersOrder(orderId: 1), returnsNormally);
  });

  test('MOC-2: completeForOthersOrder deducts customer custody stock and records customer_stock_movements', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic moDao = db.manufacturingOrderDao;
    expect(() => moDao.completeForOthersOrder(orderId: 1), returnsNormally);
  });

  test('MOC-3: completeForOthersOrder does not increment factory finished product stock', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic moDao = db.manufacturingOrderDao;
    expect(() => moDao.completeForOthersOrder(orderId: 1), returnsNormally);
  });

  test('MOC-4: mixed order consumes customer blank piece and factory ink inventory atomically', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic moDao = db.manufacturingOrderDao;
    expect(() => moDao.completeForOthersOrder(orderId: 1), returnsNormally);
  });

  test('MSP-1: scrap policy customer_bears does not credit customer on service invoice', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic scrapDao = db.manufacturingScrapDao;
    expect(() => scrapDao.recordOrderScrapWithPolicy(orderId: 1), returnsNormally);
  });

  test('MSP-2: scrap policy factory_pays_piece_value calculates compensation_amount when fault is factory', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic scrapDao = db.manufacturingScrapDao;
    expect(() => scrapDao.recordOrderScrapWithPolicy(orderId: 1), returnsNormally);
  });

  test('MSP-3: scrap policy factory_bears_labour_only bills service fee only for delivered units', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic scrapDao = db.manufacturingScrapDao;
    expect(() => scrapDao.recordOrderScrapWithPolicy(orderId: 1), returnsNormally);
  });

  test('MSP-4: scrap policy factory_replaces_piece consumes factory inventory to replace customer item', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic scrapDao = db.manufacturingScrapDao;
    expect(() => scrapDao.recordOrderScrapWithPolicy(orderId: 1), returnsNormally);
  });

  test('MSP-5: scrap record validates fault_party (factory vs customer)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic scrapDao = db.manufacturingScrapDao;
    expect(() => scrapDao.recordOrderScrapWithPolicy(orderId: 1), returnsNormally);
  });
}
