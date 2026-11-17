import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/import/excel_import_screen.dart';

Widget _wrap(Widget child, {ThemeMode themeMode = ThemeMode.light}) {
  return MaterialApp(
    themeMode: themeMode,
    theme: ThemeData.light(useMaterial3: true),
    darkTheme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('ar'),
    home: child,
  );
}

void main() {
  tearDown(() {
    AppFlavor.initialize(Flavor.base);
  });

  testWidgets('ExcelImportScreen renders cleanly on 390x844 mobile viewport in Flavor.vegetable', (
    tester,
  ) async {
    AppFlavor.initialize(Flavor.vegetable);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));

    await tester.pumpWidget(_wrap(ExcelImportScreen(db: db)));
    await tester.pumpAndSettle();

    expect(find.text('استيراد الأرصدة الافتتاحية (.xlsx)'), findsOneWidget);
    expect(find.text('تحميل قالب الأرصدة الافتتاحية (.xlsx)'), findsOneWidget);
    expect(find.text('اختيار ملف .xlsx'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ExcelImportScreen shows vegetable-only guard under Flavor.base', (tester) async {
    AppFlavor.initialize(Flavor.base);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));

    await tester.pumpWidget(_wrap(ExcelImportScreen(db: db)));
    await tester.pumpAndSettle();

    expect(find.text('ميزة الاستيراد متاحة في فليفر سوق الخضار فقط'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ExcelImportScreen renders cleanly on 360x780 small phone in Dark Mode', (tester) async {
    AppFlavor.initialize(Flavor.vegetable);
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));

    await tester.pumpWidget(_wrap(ExcelImportScreen(db: db), themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    expect(find.text('تحميل قالب الأرصدة الافتتاحية (.xlsx)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
