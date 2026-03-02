import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/anti_tamper_service.dart';
import 'package:pos_offline_desktop/services/firebase_license_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // ─── Animation Controllers ───────────────────────────────────────────
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final AnimationController _progressController;
  late final AnimationController _particleController;
  late final AnimationController _pulseController;

  // ─── Animations ──────────────────────────────────────────────────────
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoRotate;
  late final Animation<double> _textFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<Offset> _subtitleSlide;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _glowAnim;

  // ─── State ───────────────────────────────────────────────────────────
  String _statusText = 'جاري التحميل...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startSequence();
  }

  void _setupAnimations() {
    // Logo: scale + fade + slight rotation
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    ).drive(Tween(begin: 0.0, end: 1.0));
    _logoFade = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ).drive(Tween(begin: 0.0, end: 1.0));
    _logoRotate = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    ).drive(Tween(begin: -0.08, end: 0.0));

    // Text: fade + slide
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textFade = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.0, end: 1.0));
    _titleSlide = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOutCubic,
    ).drive(Tween(begin: const Offset(0, 0.5), end: Offset.zero));
    _subtitleSlide = CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    ).drive(Tween(begin: const Offset(0, 0.8), end: Offset.zero));

    // Progress bar
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Particle rotation
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // Pulse glow on logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.85, end: 1.05));
    _glowAnim = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.3, end: 0.7));
  }

  Future<void> _startSequence() async {
    // Phase 1: Logo appears (600ms)
    await Future.delayed(const Duration(milliseconds: 200));
    _logoController.forward();

    // Phase 2: Text slides in (400ms after logo)
    await Future.delayed(const Duration(milliseconds: 600));
    _textController.forward();

    // Phase 3: Start loading checks
    await Future.delayed(const Duration(milliseconds: 400));
    await _runLoadingChecks();
  }

  Future<void> _runLoadingChecks() async {
    // Step 1 — Anti-tamper
    _updateStatus('فحص أمان النظام...', 0.25);
    await Future.delayed(const Duration(milliseconds: 500));
    final isTampered = await AntiTamperService.detectClockTampering();
    if (isTampered) {
      if (mounted) context.go('/tamper-detected');
      return;
    }

    // Step 2 — License (local check)
    _updateStatus('التحقق من الترخيص...', 0.50);
    await Future.delayed(const Duration(milliseconds: 400));
    final licenseManager = LicenseManager();
    final isLicenseValid = await licenseManager.isLicenseValid();

    if (!isLicenseValid) {
      if (mounted) context.go('/activation');
      return;
    }

    // Step 3 — Firebase 7-day checkin
    _updateStatus('التحقق من الاشتراك...', 0.72);
    await Future.delayed(const Duration(milliseconds: 300));
    final currentLicense = await licenseManager.getCurrentLicense();
    if (currentLicense != null) {
      final fbService = FirebaseLicenseService();
      final fbResult = await fbService.performCheckinIfNeeded(
        currentLicense.licenseKey,
      );

      if (fbResult.isSuspended) {
        // الترخيص موقوف → أوقف البرنامج
        if (mounted) {
          _showSuspendedDialog(
            fbResult.suspendedReason ?? 'تم إيقاف ترخيصك من قِبل المزود.',
          );
          return;
        }
      } else if (fbResult.warningCount > 0 && fbResult.warningCount <= 3) {
        // في حالة تحذير → نُكمل لكن نعرض رسالة
        if (mounted) {
          _showWarningDialog(fbResult.warningCount);
        }
      }
    }

    // Step 4 — Database
    _updateStatus('تحميل قاعدة البيانات...', 0.88);
    await Future.delayed(const Duration(milliseconds: 400));

    // Step 5 — Done
    _updateStatus('جاهز!', 1.0);
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;
    context.go('/');
  }

  void _showSuspendedDialog(String reason) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: const Color(0xFF0F172A),
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text(
                'تم إيقاف الترخيص',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Text(
            reason,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {},
              child: const Text(
                'تواصل مع المزود',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWarningDialog(int warningCount) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              Text(
                'تحذير ($warningCount/3)',
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تلقيت تحذيراً من المزود. يرجى التواصل لتسوية وضعك.'),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: warningCount / 3,
                color: Colors.orange,
                backgroundColor: Colors.orange.shade100,
              ),
              const SizedBox(height: 6),
              Text(
                warningCount >= 3
                    ? 'هذا التحذير الأخير — سيتم الإيقاف عند التحذير القادم'
                    : 'متبقي ${3 - warningCount} تحذير/ات قبل الإيقاف',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('حسناً، سأتواصل'),
            ),
          ],
        ),
      ),
    );
  }

  void _updateStatus(String text, double progress) {
    if (!mounted) return;
    setState(() {
      _statusText = text;
      _progress = progress;
    });
    _progressController.animateTo(
      progress,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _progressController.dispose();
    _particleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Colors ──────────────────────────────────────────────────────────
  static const Color _bg = Color(0xFF0D1117);
  static const Color _gold = Color(0xFFC9A84C);
  static const Color _goldLight = Color(0xFFE8C97A);
  static const Color _border = Color(0xFF30363D);
  static const Color _textMuted = Color(0xFF7D8590);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── Background gradient mesh
          _buildBackground(),

          // ── Rotating orbit particles
          AnimatedBuilder(
            animation: _particleController,
            builder: (_, _) => _buildParticles(),
          ),

          // ── Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo area
                AnimatedBuilder(
                  animation: Listenable.merge([
                    _logoController,
                    _pulseController,
                  ]),
                  builder: (_, _) => _buildLogoSection(),
                ),

                const SizedBox(height: 40),

                // ── Title & subtitle
                FadeTransition(
                  opacity: _textFade,
                  child: Column(
                    children: [
                      SlideTransition(
                        position: _titleSlide,
                        child: const Text(
                          'نظام نقاط البيع',
                          style: TextStyle(
                            fontFamily: 'NotoSansArabic',
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SlideTransition(
                        position: _subtitleSlide,
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [_gold, _goldLight, _gold],
                          ).createShader(bounds),
                          child: const Text(
                            'POS System — Developed by MO2',
                            style: TextStyle(
                              fontFamily: 'NotoSansArabic',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 60),

                // ── Progress section
                FadeTransition(
                  opacity: _textFade,
                  child: _buildProgressSection(),
                ),
              ],
            ),
          ),

          // ── Footer version
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _textFade,
              child: const Text(
                'v1.0.0  ·  2026',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Background ───────────────────────────────────────────────────────
  Widget _buildBackground() {
    return Stack(
      children: [
        // Radial gold glow top-right
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_gold.withValues(alpha: 0.07), Colors.transparent],
              ),
            ),
          ),
        ),
        // Radial blue glow bottom-left
        Positioned(
          bottom: -80,
          left: -80,
          child: Container(
            width: 350,
            height: 350,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF1ABCFE).withValues(alpha: 0.05),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Subtle grid
        CustomPaint(painter: _GridPainter(), size: Size.infinite),
      ],
    );
  }

  // ─── Orbit Particles ──────────────────────────────────────────────────
  Widget _buildParticles() {
    final t = _particleController.value;
    return CustomPaint(painter: _OrbitPainter(t), size: Size.infinite);
  }

  // ─── Logo Section ─────────────────────────────────────────────────────
  Widget _buildLogoSection() {
    return Transform.rotate(
      angle: _logoRotate.value,
      child: Transform.scale(
        scale: _logoScale.value,
        child: Opacity(
          opacity: _logoFade.value.clamp(0.0, 1.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              AnimatedBuilder(
                animation: _glowAnim,
                builder: (_, _) => Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withValues(alpha: _glowAnim.value * 0.5),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),

              // Pulse scale ring
              Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _gold.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              // Main logo container
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E2A3A), Color(0xFF0D1117)],
                  ),
                  border: Border.all(
                    color: _gold.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Image.asset(
                      'assets/logo/app_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.storefront_rounded,
                        color: _gold,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Progress Section ─────────────────────────────────────────────────
  Widget _buildProgressSection() {
    return SizedBox(
      width: 260,
      child: Column(
        children: [
          // Status text
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _statusText,
              key: ValueKey(_statusText),
              style: const TextStyle(
                fontFamily: 'NotoSansArabic',
                color: _textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Progress bar
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: _border,
              borderRadius: BorderRadius.circular(2),
            ),
            child: AnimatedBuilder(
              animation: _progressController,
              builder: (_, _) => FractionallySizedBox(
                alignment: Alignment.centerRight,
                widthFactor: _progress,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(colors: [_gold, _goldLight]),
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withValues(alpha: 0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Percentage
          AnimatedBuilder(
            animation: _progressController,
            builder: (_, _) => Text(
              '${(_progress * 100).toInt()}%',
              style: const TextStyle(
                color: _gold,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grid Background Painter ──────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF30363D).withValues(alpha: 0.35)
      ..strokeWidth = 0.5;

    const step = 55.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

// ─── Orbit Particles Painter ──────────────────────────────────────────────
class _OrbitPainter extends CustomPainter {
  final double t;
  _OrbitPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 3 orbit rings with dots
    final orbits = [
      _OrbitConfig(
        radius: 160,
        dotCount: 5,
        dotSize: 2.5,
        color: const Color(0xFFC9A84C),
        speed: 1.0,
        opacity: 0.35,
      ),
      _OrbitConfig(
        radius: 210,
        dotCount: 8,
        dotSize: 1.8,
        color: const Color(0xFF1ABCFE),
        speed: -0.6,
        opacity: 0.25,
      ),
      _OrbitConfig(
        radius: 260,
        dotCount: 12,
        dotSize: 1.2,
        color: const Color(0xFF3FB950),
        speed: 0.4,
        opacity: 0.2,
      ),
    ];

    for (final orbit in orbits) {
      final paint = Paint()
        ..color = orbit.color.withValues(alpha: orbit.opacity);
      final ringPaint = Paint()
        ..color = orbit.color.withValues(alpha: orbit.opacity * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

      canvas.drawCircle(Offset(cx, cy), orbit.radius, ringPaint);

      for (int i = 0; i < orbit.dotCount; i++) {
        final angle =
            (2 * math.pi / orbit.dotCount) * i + 2 * math.pi * t * orbit.speed;
        final x = cx + orbit.radius * math.cos(angle);
        final y = cy + orbit.radius * math.sin(angle);
        canvas.drawCircle(Offset(x, y), orbit.dotSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.t != t;
}

class _OrbitConfig {
  final double radius, dotSize, speed, opacity;
  final int dotCount;
  final Color color;
  const _OrbitConfig({
    required this.radius,
    required this.dotCount,
    required this.dotSize,
    required this.color,
    required this.speed,
    required this.opacity,
  });
}
