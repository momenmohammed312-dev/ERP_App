// ignore: depend_on_referenced_packages
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:desktop_window/desktop_window.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/config/theme.dart';
import 'package:pos_offline_desktop/core/router/go_router.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/anti_tamper_service.dart';
import 'package:pos_offline_desktop/services/integrity_checker.dart';
import 'package:pos_offline_desktop/services/user_session_service.dart';
import 'package:pos_offline_desktop/services/user_backup_service.dart';
import 'package:pos_offline_desktop/screens/license/activation_screen.dart';
import 'package:pos_offline_desktop/screens/license/activation_success_screen.dart';
import 'package:pos_offline_desktop/screens/license/license_info_screen.dart';
import 'package:pos_offline_desktop/screens/license/tamper_detected_screen.dart';

// import 'package:firebase_core/firebase_core.dart';
// import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // // Initialize Firebase
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Check for clock tampering FIRST
  final isTampered = await AntiTamperService.detectClockTampering();
  if (isTampered) {
    // Show tamper detected screen
    runApp(const TamperDetectedApp());
    return;
  }

  // Check license validity
  final licenseManager = LicenseManager();
  final isLicenseValid = await licenseManager.isLicenseValid();

  // Start background services
  UserSessionService.startSessionCleanup();
  IntegrityChecker.startPeriodicCheck();
  AutoBackupService.start();

  if (!kIsWeb) {
    try {
      await DesktopWindow.setMinWindowSize(const Size(800, 800));
    } catch (e) {
      // Desktop window not supported on this platform
    }
  }

  // Show splash screen first, then navigate based on license status
  runApp(ProviderScope(child: MyApp(isLicenseValid: isLicenseValid)));
}

class MyApp extends ConsumerWidget {
  final bool isLicenseValid;

  const MyApp({super.key, required this.isLicenseValid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          ? ref.read(routerProvider)
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
