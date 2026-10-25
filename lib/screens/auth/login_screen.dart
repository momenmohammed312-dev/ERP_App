import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/auth_service.dart';
import 'package:pos_offline_desktop/ui/user/user_management_page.dart';
import 'package:pos_offline_desktop/widgets/brand/madar_logo.dart';

const Color _bgDark = Color(0xFF0D1117);
const Color _bgCard = Color(0xFF161B22);
const Color _gold = Color(0xFFC9A84C);
const Color _border = Color(0xFF30363D);
const Color _textMuted = Color(0xFF8B949E);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  late final AnimationController _animCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _formSlide;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _logoScale = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
    );
    _logoFade = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
    );
    _formSlide = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = ref.read(appDatabaseProvider);
      final username = _usernameCtrl.text.trim();
      final password = _passwordCtrl.text;

      final appUser = await db.userDao.getUserByUsername(username);
      if (appUser == null) {
        setState(() {
          _errorMessage = 'اسم المستخدم غير موجود';
          _isLoading = false;
        });
        return;
      }

      final isValid = await db.userDao.authenticate(username, password);
      if (isValid == null) {
        setState(() {
          _errorMessage = 'كلمة المرور غير صحيحة';
          _isLoading = false;
        });
        return;
      }

      if (!appUser.isActive) {
        setState(() {
          _errorMessage = 'هذا الحساب معطّل. تواصل مع المسؤول.';
          _isLoading = false;
        });
        return;
      }

      await db.userDao.updateLastLogin(appUser.id);
      final user = _mapToUser(appUser);
      await ref.read(authProvider.notifier).login(user);

      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'حدث خطأ أثناء تسجيل الدخول: $e';
          _isLoading = false;
        });
      }
    }
  }

  User _mapToUser(AppUser appUser) {
    UserRole role;
    switch (appUser.role.toLowerCase()) {
      case 'admin':
        role = UserRole.admin;
        break;
      case 'manager':
        role = UserRole.manager;
        break;
      case 'cashier':
        role = UserRole.cashier;
        break;
      case 'accountant':
        role = UserRole.accountant;
        break;
      default:
        role = UserRole.viewer;
    }
    return User(
      id: appUser.id,
      username: appUser.username,
      passwordHash: appUser.password,
      fullName: appUser.fullName,
      role: role,
      isActive: appUser.isActive,
      lastLogin: appUser.lastLogin,
      createdAt: appUser.createdAt,
      email: null,
      phone: null,
      customPermissions: const [],
      failedAttempts: 0,
      lockedUntil: null,
      updatedAt: null,
      createdBy: null,
      updatedBy: null,
    );
  }

  Future<void> _openPreAuthUserManagement() async {
    final passwordCtrl = TextEditingController();
    final isAuthorized = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _bgCard,
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                'صلاحية المدير مطلوبة',
                style: TextStyle(color: Colors.white, fontFamily: 'NotoSansArabic'),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'أدخل كلمة مرور المدير لإدارة المستخدمين:',
                style: TextStyle(color: _textMuted, fontFamily: 'NotoSansArabic'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'كلمة مرور المدير',
                  labelStyle: TextStyle(color: _textMuted),
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock, color: _textMuted),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(color: _textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _bgDark,
              ),
              onPressed: () async {
                final db = ref.read(appDatabaseProvider);
                final nav = Navigator.of(ctx);
                final ok = await db.userDao.authenticate(
                  'admin',
                  passwordCtrl.text,
                );
                nav.pop(ok != null);
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );

    if (isAuthorized == true && mounted) {
      final db = ref.read(appDatabaseProvider);
      final authService = ref.read(authServiceProvider);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              UserManagementPage(database: db, authService: authService),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D1117), Color(0xFF161B22), Color(0xFF0D1117)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 840;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: isDesktop ? _buildDesktopSplitLayout() : _buildMobileLayout(),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Desktop Fiori Split Layout (Wide Screen):
  /// Right pane (in RTL): Login form starts immediately with "مرحبًا بعودتك"
  /// Left pane (in RTL): Authentic Madar orbital brand identity & status telemetry
  Widget _buildDesktopSplitLayout() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960),
      child: Container(
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: _gold.withValues(alpha: 0.05),
              blurRadius: 10,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Right Pane (Form): No logo/title above it, starts directly with welcome
              Expanded(
                flex: 11,
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: FadeTransition(
                    opacity: _formSlide,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(_formSlide),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'مرحبًا بعودتك',
                            style: TextStyle(
                              fontFamily: 'NotoSansArabic',
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.start,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'سجّل الدخول للمتابعة إلى منظومة إدارة الأعمال',
                            style: TextStyle(
                              fontFamily: 'NotoSansArabic',
                              fontSize: 13.5,
                              color: _textMuted,
                            ),
                            textAlign: TextAlign.start,
                          ),
                          const SizedBox(height: 28),
                          _buildFormContent(),
                          const SizedBox(height: 24),
                          _buildFooterRow(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Left Pane: Brand Identity & Telemetry
              Expanded(
                flex: 9,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const RadialGradient(
                      center: Alignment(0, -0.2),
                      radius: 1.1,
                      colors: [Color(0xFF1E2A3A), Color(0xFF0D1117)],
                    ),
                    border: Border(
                      right: BorderSide(color: _border.withValues(alpha: 0.8)),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: const MadarOrbitLogo(size: 88),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Colors.white,
                            MadarColors.goldLight,
                            MadarColors.gold,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(bounds),
                        child: const Text(
                          'مِدار',
                          style: TextStyle(
                            fontFamily: 'NotoSansArabic',
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'MADAR',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _gold,
                          letterSpacing: 4.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'منظومة إدارة الأعمال',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'إدارة. تشغيل. نمو.',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: _textMuted,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Telemetry Pills
                      _buildTelemetryPill(
                        Icons.cloud_off_rounded,
                        'نظام سطح المكتب غير المتصل',
                        Colors.blueGrey.shade300,
                      ),
                      const SizedBox(height: 8),
                      _buildTelemetryPill(
                        Icons.security_rounded,
                        'قاعدة بيانات محلية مشفرة',
                        _gold,
                      ),
                      const SizedBox(height: 8),
                      _buildTelemetryPill(
                        Icons.code_rounded,
                        'Developed by MO2',
                        Colors.white60,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mobile Compact Layout (< 840px)
  Widget _buildMobileLayout() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: const MadarOrbitLogo(size: 64),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'مِدار MADAR',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _gold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'مرحبًا بعودتك',
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 4),
            const Text(
              'سجّل الدخول للمتابعة',
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 12.5,
                color: _textMuted,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 20),
            _buildFormContent(),
            const SizedBox(height: 20),
            _buildFooterRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryPill(IconData icon, String text, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormContent() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _usernameCtrl,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم',
              labelStyle: TextStyle(fontFamily: 'NotoSansArabic', color: _textMuted),
              prefixIcon: Icon(Icons.person_outline, color: _textMuted),
              border: OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _gold),
              ),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'أدخل اسم المستخدم' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'كلمة المرور',
              labelStyle: const TextStyle(fontFamily: 'NotoSansArabic', color: _textMuted),
              prefixIcon: const Icon(Icons.lock_outline, color: _textMuted),
              border: const OutlineInputBorder(),
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: _border),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: _gold),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: _textMuted,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            onFieldSubmitted: (_) => _login(),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontFamily: 'NotoSansArabic',
                        color: Colors.red,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _bgDark,
                disabledBackgroundColor: _gold.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _bgDark,
                      ),
                    )
                  : const Text(
                      'تسجيل الدخول',
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            'لإعادة تعيين كلمة المرور تواصل مع المسؤول',
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 11.5,
              color: _textMuted.withValues(alpha: 0.8),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => _openPreAuthUserManagement(),
          icon: const Icon(Icons.admin_panel_settings, size: 16),
          label: const Text(
            'إدارة المستخدمين',
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: TextButton.styleFrom(foregroundColor: _gold),
        ),
      ],
    );
  }
}
