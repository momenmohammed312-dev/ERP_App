import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v76 -> v77 migration preserves existing orders and adds input columns/BOM type', () async {
    final tempDir = Directory.systemTemp.createTempSync('drift_v77_migration_real_');
    final dbFile = File('${tempDir.path}/test_v76_to_v77_real.db');
    
    // 1. Create a fully populated DB using the CURRENT schema (v77).
    final setupDb = AppDatabase(NativeDatabase(dbFile));
    
    final customerId = 'cust123';
    await setupDb.customerDao.insertCustomer(
        CustomersCompanion.insert(id: customerId, name: 'Test Customer', phone: const Value('1234567')));
        
    final productId = await setupDb.productDao.insertProduct(
        ProductsCompanion.insert(name: 'Test Product', price: 0, quantity: 10));
        
    final bomId = await setupDb.bomDao.insertBom(
        BillOfMaterialsCompanion.insert(name: 'Test BOM', finishedProductId: productId));
        
    final orderId = await setupDb.into(setupDb.manufacturingOrders).insert(
        ManufacturingOrdersCompanion.insert(
          orderNumber: 'MO-76-TEST',
          bomId: bomId,
          finishedProductId: productId,
          plannedQuantity: 10.0,
          status: const Value(ManufacturingOrderStatus.completed),
          orderType: const Value('internal'),
          inputProductId: Value(productId),
          inputColor: const Value('Red'),
          inputSize: const Value('XL'),
          inputQuantity: const Value(5.0),
        )
    );
    
    // We insert rows in other Phase A/B1 tables just to ensure they survive.
    await setupDb.into(setupDb.customerStockBalances).insert(
        CustomerStockBalancesCompanion.insert(
            customerId: customerId,
            productId: productId,
            quantityOnHand: const Value(10.0),
        )
    );
    
    // Close the setup DB.
    await setupDb.close();

    // 2. Open via raw sqlite, drop the v77 columns, and set version to 76.
    final raw = sqlite3.open(dbFile.path);
    try {
      raw.execute('ALTER TABLE manufacturing_orders DROP COLUMN input_product_id;');
      raw.execute('ALTER TABLE manufacturing_orders DROP COLUMN input_color;');
      raw.execute('ALTER TABLE manufacturing_orders DROP COLUMN input_size;');
      raw.execute('ALTER TABLE manufacturing_orders DROP COLUMN input_quantity;');
      raw.execute('ALTER TABLE bill_of_materials DROP COLUMN type;');
      raw.execute('PRAGMA user_version = 76;');
    } finally {
      raw.dispose();
    }

    // 3. Open via AppDatabase -> triggers onUpgrade from 76 to 77
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    final version = versionRow.read<int>('user_version');
    expect(version, 77, reason: 'Database upgraded from 76 to 77');

    // 4. Assert pre-existing rows survived and new columns are null
    final moRow = await db.customSelect('SELECT * FROM manufacturing_orders WHERE id = $orderId').getSingle();
    expect(moRow.read<String>('order_number'), 'MO-76-TEST');
    expect(moRow.read<int?>('input_product_id'), isNull);
    expect(moRow.read<String?>('input_color'), isNull);
    expect(moRow.read<String?>('input_size'), isNull);
    expect(moRow.read<double?>('input_quantity'), isNull);

    final bomRow = await db.customSelect('SELECT * FROM bill_of_materials WHERE id = $bomId').getSingle();
    expect(bomRow.read<String>('name'), 'Test BOM');
    expect(bomRow.read<String?>('type'), isNull);

    // 5. Test idempotency
    await db.close();

    final rawReopen = sqlite3.open(dbFile.path);
    rawReopen.execute('PRAGMA user_version = 76;');
    rawReopen.dispose();

    final dbSecond = AppDatabase(NativeDatabase(dbFile));
    addTearDown(dbSecond.close);

    final secondVersionRow = await dbSecond.customSelect('PRAGMA user_version').getSingle();
    expect(secondVersionRow.read<int>('user_version'), 77);
  });
}
