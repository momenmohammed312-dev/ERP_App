import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/license_provider.dart';
import 'package:pos_offline_desktop/ui/home/modern_home.dart';
import 'package:pos_offline_desktop/screens/license/activation_screen.dart';
import 'package:pos_offline_desktop/ui/purchase/widgets/enhanced_purchase_invoice_page.dart';
import 'package:pos_offline_desktop/ui/backup/enhanced_backup_screen.dart';
import 'package:pos_offline_desktop/ui/admin/admin_dashboard_page.dart';
import 'package:pos_offline_desktop/ui/setup/first_run_setup_screen.dart';
import 'package:pos_offline_desktop/ui/auth/login_screen.dart';
import 'package:pos_offline_desktop/core/services/auth_service.dart';

// Simple splash screen widget
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  void _navigateToNextScreen() {
    // Wait 3 seconds then navigate
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        // For development: go directly to home
        // In production: check license status first
        context.go('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final licenseState = ref.watch(licenseStateProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF2C3E50), // Dark blue background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo/Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.store, size: 80, color: Colors.white),
            ),
            const SizedBox(height: 30),

            // App Title
            const Text(
              'نظام نقاط البيع',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'POS System',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w300,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 40),

            // Loading Status
            Text(
              licenseState.isLoading
                  ? 'جاري التحقق من الرخصة...'
                  : 'جاري التحميل...',
              style: const TextStyle(fontSize: 18, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Error or License Status
            if (licenseState.hasError)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'خطأ: ${licenseState.error}',
                  style: const TextStyle(fontSize: 14, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            if (!licenseState.isLoading && !licenseState.hasError)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'الرخصة صالحة: ${licenseState.value}',
                  style: const TextStyle(fontSize: 14, color: Colors.green),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 30),

            // Loading Indicator
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 3,
            ),

            const SizedBox(height: 20),

            // Developer Info
            const Text(
              'Developed by MO2',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final authService = ref.watch(authServiceProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) async {
      final loggedIn = authService.isLoggedIn();
      final isAuthPath =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/splash' ||
          state.matchedLocation == '/activation' ||
          state.matchedLocation == '/setup';

      // 1. Initial splash/activation screen logic (omitted for brevity, keeping simple)

      // 2. Logic for first-run setup
      if (state.matchedLocation != '/setup') {
        final hasDefault = await db.userDao.hasDefaultAdminPassword();
        if (hasDefault) {
          return '/setup';
        }
      }

      // 3. Auth redirect
      if (!loggedIn && !isAuthPath) {
        return '/login';
      }

      // 4. Already logged in, trying to access login
      if (loggedIn && state.matchedLocation == '/login') {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const FirstRunSetupScreen(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/activation',
        builder: (context, state) => const ActivationScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => ModernHomeScreen(db: db),
      ),
      GoRoute(
        path: '/new-supply-invoice',
        builder: (context, state) => EnhancedPurchaseInvoicePage(db: db),
      ),
      GoRoute(
        path: '/backup',
        builder: (context, state) => EnhancedBackupScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardPage(),
      ),
    ],
  );
});

class SplashLoadingScreen extends StatelessWidget {
  const SplashLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking license...'),
          ],
        ),
      ),
    );
  }
}
