import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/product/widgets/product_container.dart';

/// BUG-024 — the products table hid a value the product form saves: a product
/// with a category looked identical to one without it. The admin dashboard
/// already rendered `product.category`; the main table must too.
void main() {
  testWidgets('BUG-024 — the products table shows the category column',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'منتج اختبار',
            price: 10,
            quantity: 5,
            category: const Value('خضار'),
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ar'),
        home: Scaffold(body: ProductContainer(db: db)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الفئة'), findsOneWidget,
        reason: 'the column header must be visible');
    expect(find.text('خضار'), findsOneWidget,
        reason: 'the saved category must be visible in the row');
  });
}
