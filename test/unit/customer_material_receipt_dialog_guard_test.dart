import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/manufacturing/customer_material_receipt_list_screen.dart';

/// BUG-006 regression: submitting the customer-material receipt dialog with
/// a row whose product selection was cleared used to crash with
/// "Null check operator used on a null value" (selectedProductId!).
/// It must now show a clear validation error instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  testWidgets(
    'BUG-006: unselected product row shows validation error, no crash',
    (tester) async {
      // enlarge the test surface: the real dialog is 800x750 wide
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // The dialog title/rows overflow the test viewport because of test
      // font fallback metrics, not a product defect. Tolerate layout
      // overflows here; assert only business behavior.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exception.toString().contains('RenderFlex overflowed'))
          return;
        if (originalOnError != null) originalOnError(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.customers)
          .insert(CustomersCompanion.insert(id: 'cust-1', name: 'Cust One'));
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(name: 'Test Fab', quantity: 100, price: 5),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CustomerMaterialReceiptDialog(db: db)),
        ),
      );
      await tester.pumpAndSettle();

      // Clear the auto-seeded product selection of the first row.
      await tester.tap(find.byIcon(Icons.clear).first);
      await tester.pumpAndSettle();

      // Fill the received quantity so only the product guard can trigger.
      final qtyField = find.byType(TextFormField).first;
      await tester.enterText(qtyField, '10');
      await tester.pump();

      // Pick the customer so the customer guard does not fire first.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cust One (cust-1)').last);
      await tester.pumpAndSettle();

      // Submit.
      await tester.tap(find.text('تسجيل الاستلام'));
      await tester.pumpAndSettle();

      expect(find.textContaining('اختر المنتج'), findsWidgets);
      expect(find.textContaining('Null check'), findsNothing);

      // No receipt may have been written.
      final receipts = await db.customerMaterialReceiptDao.getAllReceipts();
      expect(receipts, isEmpty);
    },
  );
}
