import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/enhanced_new_invoice_page.dart';

AppDatabase _createTestDb() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  group('EnhancedNewInvoicePage Responsive Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'business_name': 'مؤسسة تجريبية',
      });
    });

    testWidgets('Mobile (360x780): Selection modal -> 2-tab layout without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = _createTestDb();
      await db.dayDao.openDay(openingBalance: 500.0, openedBy: 'admin');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            home: EnhancedNewInvoicePage(db: db),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Type selection modal is shown first
      expect(find.text('اختر نوع الفاتورة'), findsOneWidget);
      expect(find.text('نقدي (كاش)'), findsOneWidget);

      // Tap Cash
      await tester.tap(find.text('نقدي (كاش)'));
      await tester.pumpAndSettle();

      // Step 2: Main invoice interface on mobile shows tab bar
      expect(find.text('المنتجات'), findsOneWidget);
      expect(find.text('الفاتورة (0)'), findsOneWidget);

      // Verify Products tab is active
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);

      // Switch to Invoice Details / Cart Tab
      await tester.tap(find.text('الفاتورة (0)'));
      await tester.pumpAndSettle();

      // In Invoice Details Tab: Empty state with back to products button
      expect(find.text('لا توجد منتجات مضافة'), findsOneWidget);
      expect(find.text('إضافة منتجات من القائمة'), findsOneWidget);

      // Switch back to Products
      await tester.tap(find.text('المنتجات'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    });

    testWidgets('Desktop (1280x800): Side-by-side layout without mobile tabs',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = _createTestDb();
      await db.dayDao.openDay(openingBalance: 500.0, openedBy: 'admin');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            home: EnhancedNewInvoicePage(db: db),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Desktop type selection modal is shown
      expect(find.text('اختر نوع الفاتورة'), findsOneWidget);
      expect(find.text('نقدي'), findsOneWidget);

      // Tap Cash
      await tester.tap(find.text('نقدي'));
      await tester.pumpAndSettle();

      // Step 2: Side-by-side layout renders both Products & Details at the same time
      expect(find.text('فاتورة جديدة'), findsWidgets);
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
      expect(find.text('لا توجد منتجات مضافة'), findsOneWidget);
      // No mobile tab toggle in AppBar
      expect(find.text('الفاتورة (0)'), findsNothing);
    });
  });
}
