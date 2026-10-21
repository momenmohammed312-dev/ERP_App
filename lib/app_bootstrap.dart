// ignore: depend_on_referenced_packages
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/license_provider.dart';
import 'package:pos_offline_desktop/core/router/go_router.dart';
import 'package:pos_offline_desktop/core/config/theme.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';

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

/// Shared startup for all flavors. [flavor] wins over `--dart-define=FLAVOR=…`.
Future<void> bootstrapApp({Flavor? flavor}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // A throw during startup happens before runApp, so without these handlers
  // the app dies on a blank screen with nothing in the log the user can see.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.e('FlutterError', details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.e('Uncaught platform error', error, stack);
    return true;
  };

  AppFlavor.initialize(flavor ?? AppFlavor.fromEnvironment());

  // A2: Ensure production release builds warn if running with default secret keys.
  if (kReleaseMode) {
    try {
      LicenseConfig.assertSecretKeyConfigured();
    } catch (e) {
      AppLogger.w('Running in release mode without custom LICENSE_SECRET_KEY: $e');
    }
  }

  // Each startup service is isolated: one failure must not stop the app from
  // reaching runApp, and must leave a trace instead of failing silently.
  Future<void> guard(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      AppLogger.e('Startup step failed: $label', error, stack);
    }
  }

  await guard('SecurityService.initialize', SecurityService.initialize);
  await guard('SecureLicenseStorage.init', SecureLicenseStorage.init);

  // FEAT-016 — a release build compiled without --dart-define=LICENSE_PUBLIC_KEY
  // carries an EMPTY verification key, so LicenseManager._parseLease() rejects
  // every signed license and the customer sees "no license" with no cause. That
  // failure mode is invisible, so surface it once, loudly, at startup.
  if (LicenseConfig.publicKey.isEmpty && !LicenseConfig.isFreeVersion) {
    debugPrint(
      '╔══════════════════════════════════════════════════════════════╗\n'
      '║ MADAR: LICENSE_PUBLIC_KEY is missing from this build.        ║\n'
      '║ Every signed license will be REJECTED and the customer will  ║\n'
      '║ see "no license". Rebuild with:                             ║\n'
      '║   --dart-define=LICENSE_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----\\n'
      '║   MIIB...\\n-----END PUBLIC KEY-----"                      ║\n'
      '╚══════════════════════════════════════════════════════════════╝',
    );
  }

  final container = ProviderContainer();
  final db = container.read(appDatabaseProvider);

  await guard('createDefaultAdmin', () async {
    UserSessionService.init(db);
    await db.userDao.createDefaultAdmin();
  });

  await guard(
    'PeriodicLicenseValidator',
    PeriodicLicenseValidator.validateWithPeriodicCheck,
  );

  await guard('sessionCleanup', () async {
    UserSessionService.startSessionCleanup();
  });
  await guard('IntegrityChecker', () async {
    IntegrityChecker.startPeriodicCheck(db);
  });
  await guard('EnhancedBackupService', () async {
    EnhancedBackupService().init(db);
  });
  await guard('EnhancedAutoBackupService', () async {
    EnhancedAutoBackupService.start();
  });

  // Multi-device sync (local-first → Supabase): initialize the client once and
  // start the background outbox flush. Guarded so a missing/placeholder
  // SUPABASE_URL never blocks app startup.
  try {
    final syncService = container.read(syncServiceProvider);
    await syncService.initialize();
    syncService.startPeriodicSync();
  } catch (e) {
    debugPrint('Sync service init error (continuing offline): $e');
  }

  await guard(
    'NotificationService',
    () => NotificationService().initialize(db),
  );

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
        await windowManager.setTitle(AppFlavor.appTitle);
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('Window manager initialization error: $e');
    }
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const PosApp()),
  );
}

class PosApp extends ConsumerWidget {
  const PosApp({super.key});

  /// Build light theme with compact density and scaled text on mobile platforms.
  static ThemeData getLightTheme() {
    final base = AppTheme.getLightTheme();
    final textTheme = PlatformUtils.isMobile
        ? Typography.material2021().englishLike.merge(base.textTheme)
        : base.textTheme;

    return base.copyWith(
      visualDensity: PlatformUtils.isMobile
          ? VisualDensity.compact
          : VisualDensity.standard,
      textTheme: textTheme.apply(
        fontSizeFactor: PlatformUtils.isMobile ? 0.85 : 1.0,
        fontFamily: 'NotoSansArabic',
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

  /// Build dark theme with compact density and scaled text on mobile platforms.
  static ThemeData getDarkTheme() {
    final base = AppTheme.getDarkTheme();
    final textTheme = PlatformUtils.isMobile
        ? Typography.material2021().englishLike.merge(base.textTheme)
        : base.textTheme;

    return base.copyWith(
      visualDensity: PlatformUtils.isMobile
          ? VisualDensity.compact
          : VisualDensity.standard,
      textTheme: textTheme.apply(
        fontSizeFactor: PlatformUtils.isMobile ? 0.85 : 1.0,
        fontFamily: 'NotoSansArabic',
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

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
      theme: getLightTheme(),
      darkTheme: getDarkTheme(),
      themeMode: ThemeMode.dark,
      supportedLocales: const [Locale('ar'), Locale('en')],
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
      ],
    );
  }
}
