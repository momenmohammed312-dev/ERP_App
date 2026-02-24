import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/main.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/license_provider.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> setupMockData(AppDatabase db) async {
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Test Product',
            price: 10.0,
            quantity: 100,
            category: const Value('General'),
          ),
        );
    await db.dayDao.openDay(openingBalance: 100.0);
  }

  group('Payment Type Selection Tests', () {
    testWidgets('Cash selection auto-sets paid amount', (
      WidgetTester tester,
    ) async {
      await setupMockData(db);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            licenseStateProvider.overrideWith((ref) => true),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Open New Invoice
      await tester.tap(find.byIcon(Icons.receipt_long));
      // Use pump instead of pumpAndSettle to avoid hang on animations if any
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Select Cash in Modal
      expect(find.text('نقدي'), findsOneWidget);
      await tester.tap(find.text('نقدي'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Wait for loading to finish (wait for product to appear)
      // We expect "Test Product" to be visible eventually
      int retry = 0;
      while (find.text('Test Product').evaluate().isEmpty && retry < 10) {
        await tester.pump(const Duration(milliseconds: 200));
        retry++;
      }

      expect(find.text('Test Product'), findsAtLeastNWidgets(1));

      // Tap on the product list item (InkWell or similar)
      await tester.tap(find.text('Test Product'));
      await tester.pumpAndSettle();

      // Verify cash is selected by default
      expect(find.text('نقدي'), findsAtLeastNWidgets(1));
    });

    testWidgets('Credit selection resets paid amount', (
      WidgetTester tester,
    ) async {
      await setupMockData(db);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            licenseStateProvider.overrideWith((ref) => true),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.receipt_long));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('آجل'), findsOneWidget);
      await tester.tap(find.text('آجل'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      int retry = 0;
      while (find.text('Test Product').evaluate().isEmpty && retry < 10) {
        await tester.pump(const Duration(milliseconds: 200));
        retry++;
      }

      await tester.tap(find.text('Test Product'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.payment), findsOneWidget);
    });
  });
}
