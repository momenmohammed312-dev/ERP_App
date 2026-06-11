import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/ui/home/modern_home.dart';
import 'package:pos_offline_desktop/screens/auth/login_screen.dart';
import 'package:pos_offline_desktop/screens/license/activation_screen.dart';
import 'package:pos_offline_desktop/ui/purchase/widgets/enhanced_purchase_invoice_page.dart';
import 'package:pos_offline_desktop/ui/backup/enhanced_backup_screen.dart';
import 'package:pos_offline_desktop/ui/admin/admin_dashboard_page.dart';
import 'package:pos_offline_desktop/ui/setup/first_run_setup_screen.dart';
import 'package:pos_offline_desktop/screens/splash_screen.dart';
import 'package:pos_offline_desktop/ui/product/damaged_items_screen.dart';
import 'package:pos_offline_desktop/screens/reports/returns_report_screen.dart';

final firstRunCompleteProvider = FutureProvider<bool>((ref) async {
  return SettingsService.isFirstRunComplete();
});

final routerProvider = Provider<GoRouter>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final user = ref.watch(authProvider);
  final firstRunAsync = ref.watch(firstRunCompleteProvider);
  final isFirstRunComplete = firstRunAsync.valueOrNull ?? true;

  // Paths that never need authentication
  const publicPaths = ['/login', '/setup', '/activation', '/splash'];

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isPublic = publicPaths.any((p) => location.startsWith(p));
      final isLoggedIn = user != null;

      // First-run check: redirect to /setup if not completed
      if (!isFirstRunComplete && !isPublic && location != '/setup') return '/setup';

      // Not logged in and trying to access a protected page → /login
      if (!isLoggedIn && !isPublic) return '/login';
      // Already logged in and navigating to /login → home
      if (isLoggedIn && location == '/login') return '/';

      // Permission guard: /admin requires manageUsers permission
      if (isLoggedIn && location == '/admin' && !user.hasPermission(Permission.manageUsers)) return '/';


      return null;
    },
    routes: [
      // Splash
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      // Auth
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      // License & Setup
      GoRoute(
        path: '/setup',
        builder: (context, state) => const FirstRunSetupScreen(),
      ),
      GoRoute(
        path: '/activation',
        builder: (context, state) => const ActivationScreen(),
      ),
      // Main Application
      GoRoute(
        path: '/',
        builder: (context, state) => ModernHomeScreen(db: db),
      ),
      // Feature Routes
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
      GoRoute(
        path: '/damaged-items',
        builder: (context, state) => DamagedItemsScreen(db: db),
      ),
      GoRoute(
        path: '/returns-report',
        builder: (context, state) => ReturnsReportScreen(database: db),
      ),
    ],
  );
});


