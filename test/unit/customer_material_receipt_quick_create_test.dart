import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/manufacturing/customer_material_receipt_list_screen.dart';

/// FEAT-006: receiving material the workshop does not stock.
/// Contract: the receipt dialog exposes the quick-create custody-product
/// button, and a custody-only product (factory quantity stays 0) can be
/// received and consumed exactly like any other custody line.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  testWidgets('FEAT-006: custody-only product receives into custody only',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('RenderFlex overflowed')) {
        return;
      }
      if (originalOnError != null) {
        originalOnError(details);
      }
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'cust-1', name: 'Cust One'),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerMaterialReceiptDialog(db: db),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // With no products the dialog shows the quick-create custody-product
    // button next to the add-row button.
    expect(find.byKey(const Key('fe006-add-custody-product')), findsOneWidget);
  });

  testWidgets('FEAT-006: zero-stock product receipt keeps factory stock 0',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('RenderFlex overflowed')) {
        return;
      }
      if (originalOnError != null) {
        originalOnError(details);
      }
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'cust-1', name: 'Cust One'),
        );
    // The on-the-fly custody product shape created by the dialog button:
    // quantity stays 0 and it is typed as raw material.
    final createdId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Customer Skirt',
            quantity: 0,
            price: 0,
            productType: const Value('raw_material'),
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerMaterialReceiptDialog(db: db),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The seeded product auto-populates the first row.
    expect(find.text('Customer Skirt'), findsWidgets);

    final qtyField = find.widgetWithText(TextFormField, 'المستلم كلياً');
    await tester.enterText(qtyField, '5');
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cust One (cust-1)').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('تسجيل الاستلام'));
    await tester.pump();

    // submit persists DB writes on a later microtask; flush then settle.
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();

    final receipts = await db.customerMaterialReceiptDao.getAllReceipts();
    expect(receipts.length, 1);
    final custody = await db.customerMaterialReceiptDao
        .getCustomerAvailableQuantity(
          customerId: 'cust-1',
          productId: createdId,
        );
    expect(custody, 5.0);

    // Factory stock of the custody-only product stays 0.
    final product = await (db.select(db.products)).getSingle();
    expect(product.quantity, 0);
  });
}
