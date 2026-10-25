import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/screens/auth/login_screen.dart';
import 'package:drift/native.dart';

AppDatabase _createTestDb() {
  return AppDatabase(NativeDatabase.memory());
}

void main() {
  group('LoginScreen Widget Tests', () {
    testWidgets('Desktop layout (1024x768): Split layout with form on right and brand on left',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
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
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Form on right pane starts directly with welcome
      expect(find.text('مرحبًا بعودتك'), findsOneWidget);
      expect(find.text('سجّل الدخول للمتابعة إلى منظومة إدارة الأعمال'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
      expect(find.text('إدارة المستخدمين'), findsOneWidget);

      // Brand panel on left pane
      expect(find.text('MADAR'), findsOneWidget);
      expect(find.text('نظام سطح المكتب غير المتصل'), findsOneWidget);
      expect(find.text('قاعدة بيانات محلية مشفرة'), findsOneWidget);
      expect(find.text('Developed by MO2'), findsOneWidget);
    });

    testWidgets('Mobile layout (400x800): Responsive single-card layout',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
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
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('مِدار MADAR'), findsOneWidget);
      expect(find.text('مرحبًا بعودتك'), findsOneWidget);
      expect(find.text('سجّل الدخول للمتابعة'), findsOneWidget);
      expect(find.text('تسجيل الدخول'), findsOneWidget);
    });

    testWidgets('Pre-auth user management dialog opens on button tap',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
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
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final manageBtn = find.text('إدارة المستخدمين');
      expect(manageBtn, findsOneWidget);
      await tester.tap(manageBtn);
      await tester.pumpAndSettle();

      expect(find.text('صلاحية المدير مطلوبة'), findsOneWidget);
      expect(find.text('أدخل كلمة مرور المدير لإدارة المستخدمين:'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
      expect(find.text('تأكيد'), findsOneWidget);
    });
  });
}
