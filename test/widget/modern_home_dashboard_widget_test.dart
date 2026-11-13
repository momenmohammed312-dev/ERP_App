import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/home/modern_home.dart';
import 'package:drift/native.dart';

AppDatabase _createTestDb() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  group('ModernHomeScreen Dashboard Widget Tests', () {
    testWidgets('Unified Header and Quick Action Strip render with 3 core buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = _createTestDb();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ar'),
            home: ModernHomeScreen(db: db),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Brand in Unified Header
      expect(find.text('مدار ERP'), findsOneWidget);
      expect(find.text('Developed by MO2'), findsOneWidget);

      // Quick Action Strip
      expect(find.text('الإجراءات السريعة'), findsOneWidget);
      expect(find.text('فاتورة جديدة'), findsOneWidget);
      expect(find.text('العملاء'), findsWidgets); // In tabbar and quick action
      expect(find.text('المنتجات'), findsWidgets); // In tabbar and quick action

      // Redundant title 'لوحة التحكم' as a standalone heading must be removed
      // (it may exist only as tab label text in AppLocalizations)
      final headings = tester.widgetList<Text>(find.byType(Text)).where(
        (t) => t.data == 'لوحة التحكم' && (t.style?.fontSize ?? 0) >= 24,
      );
      expect(headings.isEmpty, isTrue);
    });
  });
}
