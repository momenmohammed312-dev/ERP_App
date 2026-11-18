import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pos_offline_desktop/core/config/theme.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/utils/security_utils.dart';
import 'package:pos_offline_desktop/ui/widgets/daily_sales_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ar');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('FEAT-037: Backward-compatible Auth, Custom Username, MO2 & Lockout', () {
    test(
        'Legacy admin SHA-256 hash authenticates seamlessly and upgrades silently to \$v2\$',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.userDao.createDefaultAdmin();

      final admin = (await db.userDao.getUserByUsername('admin'))!;
      final legacyHash = SecurityUtils.hashPasswordLegacy('myOldPass123');
      await (db.update(db.users)..where((t) => t.id.equals(admin.id))).write(
        UsersCompanion(password: Value(legacyHash)),
      );

      expect(SecurityUtils.isLegacyHash(legacyHash), isTrue);

      final authed = await db.userDao.authenticate('admin', 'myOldPass123');
      expect(authed, isNotNull);
      expect(authed!.username, equals('admin'));

      final refreshed = (await db.userDao.getUserById(admin.id))!;
      expect(SecurityUtils.isLegacyHash(refreshed.password), isFalse);
      expect(refreshed.password.startsWith(r'$v2$'), isTrue);

      // Subsequent login with upgraded hash must succeed too
      final authedAgain = await db.userDao.authenticate('admin', 'myOldPass123');
      expect(authedAgain, isNotNull);
    });

    test(
        'Custom admin username updates cleanly and authenticateAnyAdmin accepts custom username',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.userDao.createDefaultAdmin();

      expect(await db.userDao.hasDefaultAdminPassword(), isTrue);

      await db.userDao.updateAdminAccount(
        username: 'store_owner',
        password: 'Owner#2026',
      );

      expect(await db.userDao.hasDefaultAdminPassword(), isFalse);

      // Case-insensitive login with new username succeeds
      final authed =
          await db.userDao.authenticate('STORE_OWNER', 'Owner#2026');
      expect(authed, isNotNull);
      expect(authed!.username, equals('store_owner'));

      // Pre-auth admin gate check works without hardcoded "admin"
      expect(await db.userDao.authenticateAnyAdmin('Owner#2026'), isTrue);
      expect(await db.userDao.authenticateAnyAdmin('wrongpass'), isFalse);
    });

    test(
        'Hidden MO2 Super Admin authenticates case-insensitively without DB row',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final upper = await db.userDao.authenticate('MO2', 'MO2');
      final lower = await db.userDao.authenticate('mo2', 'mo2');
      final mixed = await db.userDao.authenticate('Mo2', 'mO2');

      expect(upper, isNotNull);
      expect(lower, isNotNull);
      expect(mixed, isNotNull);
      expect(upper!.id, equals(-1));
      expect(upper.role.toLowerCase(), equals('admin'));

      expect(await db.userDao.authenticateAnyAdmin('mo2'), isTrue);
      expect(await db.userDao.authenticate('MO2', 'wrong'), isNull);

      final dbUsers = await db.userDao.getAllUsers();
      expect(
        dbUsers.any((u) => SecurityUtils.isSuperAdminUsername(u.username)),
        isFalse,
      );

      // Must be a safe no-op for virtual id <= 0
      await db.userDao.updateLastLogin(-1);
    });

    test('5 failed attempts lock account for 5 minutes and changePassword resets',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final userId = await db.userDao.createUser(
        'cashier_ali',
        'Secret@123',
        'Cashier',
        'Ali Cashier',
      );

      for (int i = 0; i < 5; i++) {
        final res = await db.userDao.authenticate('cashier_ali', 'badpass$i');
        expect(res, isNull);
      }

      final lockedUser = (await db.userDao.getUserById(userId))!;
      expect(lockedUser.failedAttempts, equals(5));
      expect(lockedUser.lockedUntil, isNotNull);
      expect(lockedUser.lockedUntil!.isAfter(DateTime.now()), isTrue);

      // Even the correct password is rejected while locked out
      expect(
        await db.userDao.authenticate('cashier_ali', 'Secret@123'),
        isNull,
      );

      // Changing password clears lockout & failed attempts
      await db.userDao.changePassword(userId, 'NewSecret@456');
      final unlockedUser = (await db.userDao.getUserById(userId))!;
      expect(unlockedUser.failedAttempts, equals(0));
      expect(unlockedUser.lockedUntil, isNull);

      final authed =
          await db.userDao.authenticate('cashier_ali', 'NewSecret@456');
      expect(authed, isNotNull);
    });

    test(
        'AuthNotifier persists Remember Me session, restores it, and logout keeps lastUsername',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.userDao.createDefaultAdmin();

      final adminAppUser = (await db.userDao.getUserByUsername('admin'))!;
      final adminUser = User(
        id: adminAppUser.id,
        username: adminAppUser.username,
        passwordHash: '',
        fullName: adminAppUser.fullName,
        role: UserRole.admin,
        isActive: adminAppUser.isActive,
        createdAt: adminAppUser.createdAt,
      );

      const storage = FlutterSecureStorage();
      final notifier = AuthNotifier(storage, db);
      await notifier.ensureInitialized();
      expect(notifier.state, isNull);

      await notifier.login(adminUser, rememberMe: true);
      expect(notifier.state?.username, equals('admin'));
      expect(await SettingsService.getRememberMe(), isTrue);
      expect(await SettingsService.getLastUsername(), equals('admin'));

      // Simulate app restart with a fresh AuthNotifier instance
      final restartedNotifier = AuthNotifier(storage, db);
      await restartedNotifier.ensureInitialized();
      expect(restartedNotifier.state, isNotNull);
      expect(restartedNotifier.state!.id, equals(adminAppUser.id));
      expect(restartedNotifier.state!.username, equals('admin'));

      // Logout clears active session & rememberMe, preserves lastUsername
      await restartedNotifier.logout();
      expect(restartedNotifier.state, isNull);
      expect(await SettingsService.getRememberMe(), isFalse);
      expect(await SettingsService.getLastUsername(), equals('admin'));

      // Next startup should NOT auto-login
      final afterLogoutNotifier = AuthNotifier(storage, db);
      await afterLogoutNotifier.ensureInitialized();
      expect(afterLogoutNotifier.state, isNull);
    });
  });

  group('BUG-036: Dark & Light Theme Calendar / DatePicker Compatibility', () {
    test('AppTheme datePickerTheme defines dark and light palette contrast',
        () {
      final darkDateTheme = AppTheme.getDarkTheme().datePickerTheme;
      expect(darkDateTheme.backgroundColor, equals(const Color(0xFF161B22)));
      expect(darkDateTheme.rangePickerBackgroundColor,
          equals(const Color(0xFF161B22)));
      expect(darkDateTheme.dayForegroundColor, isNotNull);
      expect(darkDateTheme.todayForegroundColor, isNotNull);
      expect(darkDateTheme.rangeSelectionBackgroundColor, isNotNull);

      final lightDateTheme = AppTheme.getLightTheme().datePickerTheme;
      expect(lightDateTheme.backgroundColor, equals(Colors.white));
      expect(lightDateTheme.dayForegroundColor, isNotNull);
      expect(lightDateTheme.todayForegroundColor, isNotNull);
      expect(lightDateTheme.rangeSelectionBackgroundColor, isNotNull);
    });

    testWidgets('DailySalesCalendar renders cleanly in Dark Theme',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.getDarkTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailySalesCalendar(db: db),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DailySalesCalendar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
