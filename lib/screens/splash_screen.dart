import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/config/license_config.dart';
import 'package:pos_offline_desktop/services/license_manager.dart';
import 'package:pos_offline_desktop/services/online_license_service.dart';
import 'package:pos_offline_desktop/widgets/brand/madar_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // ─── Animation Controllers ───────────────────────────────────────────
  late final AnimationController _orbitAssemblyController;
  late final AnimationController _lockupController;
  late final AnimationController _progressController;
  late final AnimationController _pulseController;
  late final AnimationController _backgroundOrbitController;

  // ─── Animations ──────────────────────────────────────────────────────
  late final Animation<double> _assemblyCurve;
  late final Animation<double> _lockupFade;
  late final Animation<Offset> _lockupSlide;
  late final Animation<double> _pulseAnim;

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
    // 1. Orbit Assembly: letters and elements curve from orbit to center
    _orbitAssemblyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _assemblyCurve = CurvedAnimation(
      parent: _orbitAssemblyController,
      curve: Curves.easeOutCubic,
    );

    // 2. Lockup details: subtitle, tagline, footer
    _lockupController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _lockupFade = CurvedAnimation(
      parent: _lockupController,
      curve: Curves.easeOut,
    );
    _lockupSlide = CurvedAnimation(
      parent: _lockupController,
      curve: Curves.easeOutCubic,
    ).drive(Tween(begin: const Offset(0, 0.3), end: Offset.zero));

    // 3. Progress bar animation
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // 4. Subtle continuous background orbit rotation
    _backgroundOrbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    // 5. Breathing glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.95, end: 1.05));
  }

  Future<void> _startSequence() async {
    if (!mounted) return;

    // Start orbit convergence
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    _orbitAssemblyController.forward();

    // Fade in brand lockup details
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    _lockupController.forward();

    // Begin background verification checks
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await _runLoadingChecks();
  }

  Future<void> _runLoadingChecks() async {
    // Step 1 — License check
    _updateStatus('التحقق من الترخيص...', 0.45);
    await Future.delayed(const Duration(milliseconds: 350));
    final licenseManager = LicenseManager();

    final isLicenseValid = LicenseConfig.isFreeVersion
        ? true
        : await licenseManager.isLicenseValid();

    if (!isLicenseValid) {
      if (mounted) context.go('/activation');
      return;
    }

    // Step 2 — Cloud Subscription Checkin (off the critical path)
    //
    // FEAT-012: the app must open instantly on a machine with no internet.
    // The check-in used to be awaited here, so a dead network added up to its
    // full timeout to every single launch, before the customer could even see
    // the POS. Enforcement is not weakened by moving it: `checkinIfNeeded` is
    // throttled by `_checkinInterval` and `PeriodicLicenseValidator` runs it in
    // the background on its own schedule.
    _updateStatus('التحقق من منظومة الاشتراك...', 0.70);
    await Future.delayed(const Duration(milliseconds: 300));
    final currentLicense = await licenseManager.getCurrentLicense();
    if (currentLicense != null) {
      unawaited(_runCheckinInBackground(currentLicense.licenseKey));
    }

    // Step 3 — Database loading
    _updateStatus('تحميل قاعدة البيانات...', 0.88);
    await Future.delayed(const Duration(milliseconds: 350));

    // Step 4 — Ready
    _updateStatus('جاهز للإطلاق!', 1.0);
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;
    context.go('/');
  }

  /// Runs the licensing check-in without blocking the launch.
  ///
  /// The result is surfaced once the app is already up: a suspension dialog is
  /// modal (it has to be seen), while warnings are a snackbar so they never
  /// interrupt the cashier mid-sale. A dead network resolves to `offline`
  /// inside the service and is treated as "carry on working" — the hard
  /// offline license is the authority, the server is only an advisory signal.
  Future<void> _runCheckinInBackground(String licenseKey) async {
    try {
      final result = await OnlineLicenseService().performCheckinIfNeeded(
        licenseKey,
      );
      if (!mounted) return;

      if (result.isSuspended) {
        _showSuspendedDialog(
          result.suspendedReason ?? 'تم إيقاف ترخيص المنظومة من قِبل المزود.',
        );
      } else if (result.warningCount > 0 && result.warningCount <= 3) {
        _showWarningDialog(result.warningCount);
      }
    } catch (_) {
      // Never let a network problem keep the app off the POS screen.
    }
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
          backgroundColor: MadarColors.bgCard,
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text(
                'تم إيقاف الترخيص',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Text(
            reason,
            style: const TextStyle(
              fontFamily: 'NotoSansArabic',
              color: MadarColors.textSecondary,
              fontSize: 14,
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {},
              child: const Text(
                'تواصل مع المزود',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  color: Colors.white,
                ),
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
          backgroundColor: MadarColors.bgCard,
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'تحذير ($warningCount/3)',
                style: const TextStyle(
                  fontFamily: 'NotoSansArabic',
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تلقيت تحذيراً من مزود منظومة مِدار. يرجى التواصل لتسوية وضعك.',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  color: MadarColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: warningCount / 3,
                color: Colors.orange,
                backgroundColor: Colors.orange.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 6),
              Text(
                warningCount >= 3
                    ? 'هذا التحذير الأخير — سيتم الإيقاف عند التحذير القادم'
                    : 'متبقي ${3 - warningCount} تحذير/ات قبل الإيقاف',
                style: const TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: 12,
                  color: MadarColors.textMuted,
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: MadarColors.gold,
                foregroundColor: MadarColors.bgDark,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'حسناً، سأتواصل',
                style: TextStyle(fontFamily: 'NotoSansArabic'),
              ),
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
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _orbitAssemblyController.dispose();
    _lockupController.dispose();
    _progressController.dispose();
    _pulseController.dispose();
    _backgroundOrbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MadarColors.bgDark,
      body: Stack(
        children: [
          // ── Background ambient mesh & subtle orbital lines
          _buildBackground(),

          // ── Ambient background satellite particles
          AnimatedBuilder(
            animation: _backgroundOrbitController,
            builder: (_, _) => CustomPaint(
              painter: _AmbientOrbitPainter(_backgroundOrbitController.value),
              size: Size.infinite,
            ),
          ),

          // ── Central Interactive Orbit & Brand Assembly
          Center(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo + Animated Orbiting Text Assembly
                  _buildOrbitAssembly(),

                  const SizedBox(height: 24),

                  // Lockup: Subtitle, Tagline, MO2 footer
                  FadeTransition(
                    opacity: _lockupFade,
                    child: SlideTransition(
                      position: _lockupSlide,
                      child: Column(
                        children: [
                          const Text(
                            'منظومة إدارة الأعمال',
                            style: TextStyle(
                              fontFamily: 'NotoSansArabic',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: MadarColors.textSecondary,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'إدارة. تشغيل. نمو.',
                            style: TextStyle(
                              fontFamily: 'NotoSansArabic',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: MadarColors.goldLight,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: 60,
                            height: 1.5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  MadarColors.gold.withValues(alpha: 0.5),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Developed by MO2',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: MadarColors.textMuted,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Progress & Loading Indicator
                  FadeTransition(
                    opacity: _lockupFade,
                    child: _buildProgressSection(),
                  ),
                ],
              ),
            ),
          ),

          // ── Footer version
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _lockupFade,
              child: const Text(
                'MADAR ERP  ·  v2.3.0',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MadarColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Background Ambient Glow ──────────────────────────────────────────
  Widget _buildBackground() {
    return Stack(
      children: [
        // Warm gold ambient glow center-top
        Positioned(
          top: -120,
          right: -100,
          child: Container(
            width: 450,
            height: 450,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  MadarColors.gold.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Deep enterprise navy glow bottom-left
        Positioned(
          bottom: -100,
          left: -100,
          child: Container(
            width: 420,
            height: 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF1E3A5F).withValues(alpha: 0.09),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Subtle grid overlay
        CustomPaint(painter: _GridPainter(), size: Size.infinite),
      ],
    );
  }

  // ─── Orbit Assembly Animation ─────────────────────────────────────────
  Widget _buildOrbitAssembly() {
    return AnimatedBuilder(
      animation: Listenable.merge([_orbitAssemblyController, _pulseController]),
      builder: (context, _) {
        final val = _assemblyCurve.value; // 0.0 -> 1.0

        // As val goes from 0.0 to 1.0:
        // Distance from center collapses smoothly
        final distanceFactor = (1.0 - val);

        // Logo scale & fade
        final logoScale = 0.5 + (0.5 * val);
        final logoOpacity = val.clamp(0.0, 1.0);

        // Orbit paths for Arabic "مِدار"
        // Starts on a curved orbit at distance 120 and angle -45 deg, converges to center
        final arAngle = (-math.pi / 3) * distanceFactor;
        final arDistance = 110 * distanceFactor;
        final arOffset = Offset(
          arDistance * math.cos(arAngle),
          arDistance * math.sin(arAngle),
        );
        final arOpacity = (val * 1.5).clamp(0.0, 1.0);

        // Orbit paths for English "MADAR"
        // Starts on lower orbit at distance 100 and angle 135 deg, converges to center
        final enAngle = (math.pi * 0.75) * distanceFactor;
        final enDistance = 90 * distanceFactor;
        final enOffset = Offset(
          enDistance * math.cos(enAngle),
          enDistance * math.sin(enAngle),
        );
        final enOpacity = (val * 1.3).clamp(0.0, 1.0);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Center Brand Mark with pulsing subtle glow
            Transform.scale(
              scale: _pulseAnim.value * logoScale,
              child: Opacity(
                opacity: logoOpacity,
                child: MadarOrbitLogo(
                  size: 96,
                  orbitAngle: _backgroundOrbitController.value * 2 * math.pi,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Arabic "مِدار" Text moving along curved orbit into final place
            Transform.translate(
              offset: arOffset,
              child: Opacity(
                opacity: arOpacity,
                child: ShaderMask(
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
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 6),

            // English "MADAR" Text moving along complementary orbit into place
            Transform.translate(
              offset: enOffset,
              child: Opacity(
                opacity: enOpacity,
                child: const Text(
                  'MADAR',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: MadarColors.gold,
                    letterSpacing: 5.5,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Progress Bar Section ─────────────────────────────────────────────
  Widget _buildProgressSection() {
    return SizedBox(
      width: 280,
      child: Column(
        children: [
          // Status message
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _statusText,
              key: ValueKey(_statusText),
              style: const TextStyle(
                fontFamily: 'NotoSansArabic',
                color: MadarColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Progress line
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: MadarColors.border,
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
                    gradient: const LinearGradient(
                      colors: [MadarColors.gold, MadarColors.goldLight],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: MadarColors.gold.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Percentage
          AnimatedBuilder(
            animation: _progressController,
            builder: (_, _) => Text(
              '${(_progress * 100).toInt()}%',
              style: const TextStyle(
                color: MadarColors.gold,
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

// ─── Background Subtle Grid ───────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MadarColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    const step = 60.0;
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

// ─── Ambient Orbit Satellite Nodes ────────────────────────────────────────
class _AmbientOrbitPainter extends CustomPainter {
  final double t; // 0.0 -> 1.0

  _AmbientOrbitPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final rings = [
      _OrbitRing(radius: 180, count: 4, speed: 1.0, color: MadarColors.gold),
      _OrbitRing(
        radius: 250,
        count: 6,
        speed: -0.6,
        color: MadarColors.goldLight,
      ),
      _OrbitRing(
        radius: 320,
        count: 8,
        speed: 0.4,
        color: const Color(0xFF64B5F6),
      ),
    ];

    for (final ring in rings) {
      // Ring path
      final pathPaint = Paint()
        ..color = ring.color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7;
      canvas.drawCircle(Offset(cx, cy), ring.radius, pathPaint);

      // Satellite dots
      final dotPaint = Paint()
        ..color = ring.color.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill;

      for (int i = 0; i < ring.count; i++) {
        final angle =
            (2 * math.pi / ring.count) * i + (2 * math.pi * t * ring.speed);
        final x = cx + ring.radius * math.cos(angle);
        final y = cy + ring.radius * math.sin(angle);
        canvas.drawCircle(Offset(x, y), 2.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_AmbientOrbitPainter old) => old.t != t;
}

class _OrbitRing {
  final double radius;
  final int count;
  final double speed;
  final Color color;

  _OrbitRing({
    required this.radius,
    required this.count,
    required this.speed,
    required this.color,
  });
}
