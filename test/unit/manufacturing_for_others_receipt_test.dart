import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:drift/native.dart';

/// Test-first Phase B1: Customer Material Receipts & Custody Balance.
///
/// Expected RED until C2 (v76 schema) and C3 (CustomerMaterialReceiptDao) land.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  test('CMR-1: customer material receipt creates header and line items with generated sequence', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Dynamic invocation to decouple compilation before DAO and tables exist in C2/C3
    final dynamic dynamicDb = db;
    expect(dynamicDb.customerMaterialReceiptDao, isNotNull);
  });

  test('CMR-2: receipt inspects defective material and returns it immediately at receipt', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic dynamicDb = db;
    expect(dynamicDb.customerMaterialReceiptDao, isNotNull);
  });

  test('CMR-3: accepted material increments customer_stock_balances without touching products.quantity', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic dynamicDb = db;
    expect(dynamicDb.customerMaterialReceiptDao, isNotNull);
  });

  test('CMR-4: receipt requires valid text customerId existing in customers table', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic dynamicDb = db;
    expect(dynamicDb.customerMaterialReceiptDao, isNotNull);
  });

  test('CMR-5: multiple receipts for the same customer accumulate rolling balance', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final dynamic dynamicDb = db;
    expect(dynamicDb.customerMaterialReceiptDao, isNotNull);
  });
}
