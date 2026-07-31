// ignore: depend_on_referenced_packages
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/license_provider.dart';
import 'package:pos_offline_desktop/core/router/go_router.dart';
import 'package:pos_offline_desktop/core/config/theme.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';

import 'package:pos_offline_desktop/services/anti_tamper_service.dart';
import 'package:pos_offline_desktop/services/notification_service.dart';
import 'package:pos_offline_desktop/services/security_service.dart';
import 'package:pos_offline_desktop/services/user_session_service.dart';
import 'package:pos_offline_desktop/services/integrity_checker.dart';
import 'package:pos_offline_desktop/services/enhanced_backup_service.dart';
import 'package:pos_offline_desktop/services/secure_license_storage.dart';
import 'package:pos_offline_desktop/core/services/periodic_license_validator.dart';

import 'package:pos_offline_desktop/screens/license/activation_screen.dart';
import 'package:pos_offline_desktop/screens/license/activation_success_screen.dart';
import 'package:pos_offline_desktop/screens/license/license_info_screen.dart';
import 'package:pos_offline_desktop/screens/license/tamper_detected_screen.dart';

/// Shared startup for all flavors. [flavor] wins over `--dart-define=FLAVOR=…`.
Future<void> bootstrapApp({Flavor? flavor}) async {
  WidgetsFlutterBinding.ensureInitialized();

  AppFlavor.initialize(flavor ?? AppFlavor.fromEnvironment());

  await SecurityService.initialize();
  await SecureLicenseStorage.init();

  final container = ProviderContainer();
  final db = container.read(appDatabaseProvider);

  AntiTamperService.init(db);
  UserSessionService.init(db);
  await db.userDao.createDefaultAdmin();

  final isTampered = await AntiTamperService.detectClockTampering();
  if (isTampered) {
    runApp(const ProviderScope(child: TamperDetectedApp()));
    return;
  }

  await PeriodicLicenseValidator.validateWithPeriodicCheck();

  UserSessionService.startSessionCleanup();
  IntegrityChecker.startPeriodicCheck(db);
  EnhancedBackupService().init(db);
  EnhancedAutoBackupService.start();

  await NotificationService().initialize(db);

  if (!kIsWeb && io.Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1280, 800),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('Window manager initialization error: $e');
    }
  }

  runApp(UncontrolledProviderScope(container: container, child: const PosApp()));
}

class PosApp extends ConsumerWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenseState = ref.watch(licenseStateProvider);

    final isLicenseValid = licenseState.when(
      data: (valid) => valid,
      loading: () => false,
      error: (_, _) => false,
    );

    return MaterialApp.router(
      title: AppFlavor.appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.getLightTheme().copyWith(
        textTheme: AppTheme.getLightTheme().textTheme.apply(
          fontFamily: 'NotoSansArabic',
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      darkTheme: AppTheme.getDarkTheme().copyWith(
        textTheme: AppTheme.getDarkTheme().textTheme.apply(
          fontFamily: 'NotoSansArabic',
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      themeMode: ThemeMode.dark,
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      locale: const Locale('ar'),
      routerConfig: isLicenseValid
          ? ref.watch(routerProvider)
          : _createActivationRouter(),
    );
  }

  GoRouter _createActivationRouter() {
    return GoRouter(
      initialLocation: '/activation',
      routes: [
        GoRoute(
          path: '/activation',
          builder: (context, state) => const ActivationScreen(),
        ),
        GoRoute(
          path: '/activation-success',
          builder: (context, state) => const ActivationSuccessScreen(),
        ),
        GoRoute(
          path: '/license-info',
          builder: (context, state) => const LicenseInfoScreen(),
        ),
        GoRoute(
          path: '/tamper-detected',
          builder: (context, state) => const TamperDetectedScreen(),
        ),
      ],
    );
  }
}

class TamperDetectedApp extends StatelessWidget {
  const TamperDetectedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POS System - Security Alert',
      home: const TamperDetectedScreen(),
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
    );
  }
}
