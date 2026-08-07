import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';

/// These tests prove that every local write the outbox can push to the "other"
/// device (the server) produces an EXACT, self-describing `sync_queue` row:
/// correct table ref, operation, and a snake_case payload that references only
/// Supabase (UUID) ids — never the local integer primary keys. This is the
/// contract that must hold for two (and later three) devices to converge.

AppDatabase openDb() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

Future<List<Map<String, dynamic>>> payloadsFor(
  AppDatabase db, {
  required String tableRef,
}) async {
  final rows = (await db.syncQueueDao.getPending())
      .where((r) => r.tableRef == tableRef)
      .toList();
  return rows
      .map((r) => jsonDecode(r.payloadJson) as Map<String, dynamic>)
      .toList();
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncQueueDao mechanics', () {
    test('enqueue → getPending returns oldest-first, then markSynced removes it',
        () async {
      final db = openDb();
      await db.syncQueueDao.enqueue(
        tableName: 'products',
        recordSyncId: 'a',
        operation: 'insert',
        payload: {'sync_id': 'a'},
      );
      await db.syncQueueDao.enqueue(
        tableName: 'products',
        recordSyncId: 'b',
        operation: 'insert',
        payload: {'sync_id': 'b'},
      );

      final pending = await db.syncQueueDao.getPending();
      expect(pending.map((r) => r.recordSyncId).toList(), ['a', 'b'],
          reason: 'oldest first');

      expect(await db.syncQueueDao.getPendingCount(), 2);

      await db.syncQueueDao.markSynced(pending.first.id);
      final after = await db.syncQueueDao.getPending();
      expect(after.map((r) => r.recordSyncId).toList(), ['b'],
          reason: 'synced row leaves the pending set');
      expect(await db.syncQueueDao.getPendingCount(), 1);
    });

    test('markFailed bumps retryCount; over-budget rows stop being returned',
        () async {
      final db = openDb();
      await db.syncQueueDao.enqueue(
        tableName: 'products',
        recordSyncId: 'x',
        operation: 'insert',
        payload: {'sync_id': 'x'},
      );
      final row = (await db.syncQueueDao.getPending()).single;

      for (var i = 0; i < 8; i++) {
        await db.syncQueueDao.markFailed(row.id, 'err $i');
      }

      final after = await db.syncQueueDao.getPending();
      expect(after, isEmpty,
          reason: 'row exhausted its retry budget and must not be sent');
      expect(await db.syncQueueDao.getPendingCount(), 0);

      final still = await db.syncQueueDao.getPending(
        // no limit argument override of the retry filter is intended here
      );
      expect(still, isEmpty);
    });
  });

  group('Outbox payload contract (local DAO writes → sync_queue)', () {
    test('new product → products/insert, UUID identity, no local id leak',
        () async {
      final db = openDb();
      await db.productDao.insertProduct(ProductsCompanion.insert(
        name: 'طماطم',
        quantity: 100,
        price: 5.5,
      ));

      final product = await db.productDao.getProductById(1);
      expect(product, isNotNull);
      expect(product!.syncId, isNotNull, reason: 'insert stamps a syncId');

      final pending = await db.syncQueueDao.getPending();
      expect(pending.single.tableRef, 'products');
      expect(pending.single.operation, 'insert');
      expect(pending.single.recordSyncId, product.syncId,
          reason: 'outbox identity == local product syncId');

      final payload = jsonDecode(pending.single.payloadJson) as Map<String, dynamic>;
      expect(payload['sync_id'], product.syncId);
      expect(payload['name'], 'طماطم');
      expect(payload['quantity'], 100);
      expect(payload['price'], 5.5);
      expect(payload['status'], 'Active');
      expect(payload['updated_at'], isNotNull);
      expect(payload.containsKey('id'), isFalse,
          reason: 'must never leak the local int id');
      expect(payload['product_id'], isNull,
          reason: 'must never leak the local int product id');
    });

    test('Product update → products/update with bumped updated_at', () async {
      final db = openDb();
      await db.productDao.insertProduct(ProductsCompanion.insert(
        name: 'منتج',
        quantity: 10,
        price: 2.0,
      ));
      await db.productDao.updateProduct(ProductsCompanion(
        id: const Value(1),
        name: const Value('منتج'),
        quantity: const Value(7),
        price: const Value(2.0),
      ));

      final payloads = await payloadsFor(db, tableRef: 'products');
      final updates = payloads.where((p) => p['sync_id'] != null).toList();
      final ops = (await db.syncQueueDao.getPending())
          .where((r) => r.tableRef == 'products')
          .map((r) => r.operation)
          .toList();
      expect(ops, contains('insert'));
      expect(ops, contains('update'), reason: 'update must enqueue a row');

      final product = await db.productDao.getProductById(1);
      expect(product!.quantity, 7, reason: 'local update applied');
      final up = updates.last;
      expect(up['quantity'], 7);
      expect(up['updated_at'], isNotNull);
    });

    test('Customer → customers/insert + update, id IS the UUID', () async {
      final db = openDb();
      await db.customerDao.insertCustomer(CustomersCompanion.insert(
        id: 'cust-uuid-123',
        name: 'عميل تجريبي',
      ));

      final pending = await db.syncQueueDao.getPending();
      expect(pending.single.tableRef, 'customers');
      expect(pending.single.operation, 'insert');
      expect(pending.single.recordSyncId, 'cust-uuid-123',
          reason: 'recordSyncId must be the customer UUID');

      final ins = jsonDecode(pending.single.payloadJson) as Map<String, dynamic>;
      expect(ins['sync_id'], 'cust-uuid-123');
      expect(ins['name'], 'عميل تجريبي');
      expect(ins.containsKey('id'), isFalse, reason: 'no local id concept');
      expect(ins['updated_at'], isNotNull);

      await db.customerDao.updateCustomer(CustomersCompanion(
        id: const Value('cust-uuid-123'),
        name: const Value('عميل تجريبي'),
        phone: const Value('0100000000'),
      ));
      final ops = (await db.syncQueueDao.getPending())
          .where((r) => r.tableRef == 'customers')
          .map((r) => r.operation)
          .toList();
      expect(ops, containsAll(['insert', 'update']));
    });

    test('Invoice + item → invoices/insert + invoice_items/insert (UUID refs)',
        () async {
      final db = openDb();
      await db.customerDao.insertCustomer(CustomersCompanion.insert(
        id: 'cust-uuid-1',
        name: 'عميل آجل',
      ));
      await db.productDao.insertProduct(ProductsCompanion.insert(
        name: 'سلعة',
        quantity: 50,
        price: 10.0,
      ));
      final product = await db.productDao.getProductById(1);

      final invoiceId = await db.invoiceDao.insertInvoice(InvoicesCompanion(
        customerId: const Value('cust-uuid-1'),
        customerName: const Value('عميل آجل'),
        totalAmount: const Value(30.0),
        paidAmount: const Value(0),
        status: const Value('unpaid'),
      ));
      await db.invoiceDao.insertInvoiceItem(InvoiceItemsCompanion(
        invoiceId: Value(invoiceId),
        productId: const Value(1),
        quantity: const Value(3),
        price: const Value(10.0),
      ));

      final invoicePayloads = await payloadsFor(db, tableRef: 'invoices');
      final itemPayloads = await payloadsFor(db, tableRef: 'invoice_items');

      expect(invoicePayloads, hasLength(1));
      final inv = invoicePayloads.single;
      expect(inv['customer_sync_id'], 'cust-uuid-1',
          reason: 'must reference the customer by UUID, not a local id');
      expect(inv['total_amount'], 30.0);
      expect(inv['status'], 'unpaid');
      expect(inv.containsKey('id'), isFalse);
      expect(inv.containsKey('customer_id'), isFalse);

      expect(itemPayloads, hasLength(1));
      final item = itemPayloads.single;
      expect(item['invoice_sync_id'], inv['sync_id'],
          reason: 'item references its parent invoice by UUID');
      expect(item['product_sync_id'], product!.syncId,
          reason: 'item references the product by UUID');
      expect(item['quantity'], 3);
      expect(item.containsKey('invoice_id'), isFalse);
      expect(item.containsKey('product_id'), isFalse);
    });

    test('Stock movement → stock_movements/stock_delta (signed delta only)',
        () async {
      final db = openDb();
      await db.productDao.insertProduct(ProductsCompanion.insert(
        name: 'منتج مخزون',
        quantity: 10,
        price: 1.0,
      ));
      final product = await db.productDao.getProductById(1);

await db.inventoryMovementDao.createMovement(
        InventoryMovementsCompanion.insert(
          productId: 1,
          movementType: 'sale',
          quantity: -3,
          unitCost: 1.0,
          totalValue: -3.0,
          movementDate: DateTime(2026, 8, 6),
          reference: 'INV-900',
          referenceType: 'sale_invoice',
          previousQuantity: 10,
          newQuantity: 7,
          createdAt: DateTime(2026, 8, 6, 10, 0),
          updatedAt: DateTime(2026, 8, 6, 10, 0),
        ),
      );

      final pending = (await db.syncQueueDao.getPending())
          .where((r) => r.tableRef == 'stock_movements')
          .toList();
      expect(pending, hasLength(1));
      expect(pending.single.operation, 'stock_delta');

      final payload =
          jsonDecode(pending.single.payloadJson) as Map<String, dynamic>;
      expect(payload['product_sync_id'], product!.syncId,
          reason: 'must use the product UUID');
      expect(payload['quantity_delta'], -3);
      expect(payload['movement_type'], 'sale');
      expect(payload['reference'], 'INV-900');
      expect(payload['movement_date'], isNotNull);
      // The RPC contract explicitly forbids local snapshots.
      expect(payload.containsKey('previous_quantity'), isFalse);
      expect(payload.containsKey('new_quantity'), isFalse);
      expect(payload.containsKey('product_id'), isFalse);
    });
  });
}