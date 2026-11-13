import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/reports/reports_page.dart';
import 'package:drift/native.dart';

AppDatabase _createTestDb() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  group('ReportsPage Widget Tests', () {
    testWidgets('Renders Material 3 KPI cards, dual charts, and 9 sub-report tiles',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = _createTestDb();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            home: Scaffold(body: ReportsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify 4 Material 3 KPI cards
      expect(find.text('إجمالي المبيعات'), findsOneWidget);
      expect(find.text('التدفق النقدي والآجل'), findsOneWidget);
      expect(find.text('إجمالي المشتريات'), findsOneWidget);
      expect(find.text('صافي الهامش التقديري'), findsOneWidget);

      // Verify dual charts
      expect(find.text('منحنى التدفقات المالية (المبيعات vs المشتريات vs الأرباح)'), findsOneWidget);
      expect(find.text('توزيع المبيعات حسب الأصناف'), findsOneWidget);

      // Verify the 9 official sub-report tiles
      expect(find.text('تقرير اليوم'), findsOneWidget);
      expect(find.text('تقارير المبيعات'), findsOneWidget);
      expect(find.text('فواتير المشتريات'), findsOneWidget);
      expect(find.text('تقرير العملاء والذمم'), findsOneWidget);
      expect(find.text('تقرير المصروفات'), findsOneWidget);
      expect(find.text('مصروفات الموظفين'), findsOneWidget);
      expect(find.text('المشتريات حسب المورد'), findsOneWidget);
      expect(find.text('المشتريات حسب المنتج'), findsOneWidget);
      expect(find.text('الأرصدة الموحدة'), findsOneWidget);

      // Verify old static sections and comparison card are removed
      expect(find.text('ملخص المبيعات'), findsNothing);
      expect(find.text('إحصائيات الفواتير'), findsNothing);
      expect(find.text('مقارنة المشتريات بالمبيعات'), findsNothing);
    });
  });
}
