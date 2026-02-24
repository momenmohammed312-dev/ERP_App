// ignore: depend_on_referenced_packages
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:desktop_window/desktop_window.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/config/theme.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/router/go_router.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/core/provider/license_provider.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/anti_tamper_service.dart';
import 'package:pos_offline_desktop/services/integrity_checker.dart';
import 'package:pos_offline_desktop/services/user_session_service.dart';
import 'package:pos_offline_desktop/services/user_backup_service.dart';
import 'package:pos_offline_desktop/screens/license/activation_screen.dart';
import 'package:pos_offline_desktop/screens/license/activation_success_screen.dart';
import 'package:pos_offline_desktop/screens/license/license_info_screen.dart';
import 'package:pos_offline_desktop/screens/license/tamper_detected_screen.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Create shared container for all services
  final container = ProviderContainer();
  final db = container.read(appDatabaseProvider);

  // Initialize services with shared database
  AntiTamperService.init(db);
  UserSessionService.init(db);

  // Check for clock tampering (now that services are initialized)
  final isTampered = await AntiTamperService.detectClockTampering();
  if (isTampered) {
    runApp(const TamperDetectedApp());
    return;
  }

  // Check license validity
  final licenseManager = LicenseManager();
  final isLicenseValid = await licenseManager.isLicenseValid();

  // Start background services with shared database
  UserSessionService.startSessionCleanup();
  IntegrityChecker.startPeriodicCheck(db);
  AutoBackupService.start();

  if (!kIsWeb) {
    try {
      await DesktopWindow.setMinWindowSize(const Size(800, 800));
    } catch (e) {
      // Desktop window not supported on this platform
    }
  }

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenseState = ref.watch(licenseStateProvider);

    // Determine if license is valid from the provider state
    final isLicenseValid = licenseState.when(
      data: (valid) => valid,
      loading: () => false, // Default to false while loading
      error: (_, _) => false,
    );

    return MaterialApp.router(
      title: 'POS System - Developed by MO2',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate, // generated localizations
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
        Locale('ar'), // Arabic
        Locale('en'), // English
      ],
      locale: const Locale('ar'), // Set Arabic as default
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
          builder: (context, state) => TamperDetectedScreen(),
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
      home: TamperDetectedScreen(),
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
    );
  }
}
