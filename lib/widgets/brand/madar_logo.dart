import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Gold and brand color constants for MADAR brand identity.
class MadarColors {
  static const Color bgDark = Color(0xFF0D1117);
  static const Color bgCard = Color(0xFF161B22);
  static const Color bgSurface = Color(0xFF1E2A3A);
  static const Color gold = Color(0xFFC9A84C);
  static const Color goldLight = Color(0xFFE8C97A);
  static const Color goldDark = Color(0xFF9B7B2B);
  static const Color border = Color(0xFF30363D);
  static const Color textMuted = Color(0xFF7D8590);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textLight = Color(0xFFF0F6FC);
}

/// The official geometric orbit brand mark for MADAR (مِدار).
/// Communicates interconnected ERP modules revolving around one central core system.
class MadarOrbitLogo extends StatelessWidget {
  final double size;
  final bool animateGlow;
  final double orbitAngle;

  const MadarOrbitLogo({
    super.key,
    this.size = 80,
    this.animateGlow = false,
    this.orbitAngle = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient gold glow behind the badge
          Container(
            width: size * 0.88,
            height: size * 0.88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.22),
              boxShadow: [
                BoxShadow(
                  color: MadarColors.gold.withValues(alpha: 0.28),
                  blurRadius: size * 0.32,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          // Official brand icon image with painter fallback
          Image.asset(
            'assets/logo/app_logo.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => CustomPaint(
              size: Size(size, size),
              painter: _MadarLogoPainter(orbitAngle: orbitAngle),
            ),
          ),
        ],
      ),
    );
  }
}

class _MadarLogoPainter extends CustomPainter {
  final double orbitAngle;

  _MadarLogoPainter({this.orbitAngle = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background subtle glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          MadarColors.gold.withValues(alpha: 0.18),
          MadarColors.gold.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.1));
    canvas.drawCircle(center, radius * 1.1, glowPaint);

    // Outer subtle boundary ring
    final outerRingPaint = Paint()
      ..color = MadarColors.gold.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.016;
    canvas.drawCircle(center, radius * 0.94, outerRingPaint);

    // Save canvas state for rotated ellipses (orbital paths)
    // Orbital path 1 (tilted 35 degrees + dynamic orbit angle)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((35 * math.pi / 180) + orbitAngle * 0.5);

    final orbitRect1 = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 1.75,
      height: radius * 0.72,
    );

    final orbit1Paint = Paint()
      ..shader = const LinearGradient(
        colors: [
          MadarColors.goldLight,
          MadarColors.gold,
          Colors.transparent,
          MadarColors.gold,
        ],
        stops: [0.0, 0.45, 0.75, 1.0],
      ).createShader(orbitRect1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.022;

    canvas.drawOval(orbitRect1, orbit1Paint);

    // Satellite node on Orbit 1
    final sat1X = (radius * 1.75 / 2) * math.cos(orbitAngle * 1.2);
    final sat1Y = (radius * 0.72 / 2) * math.sin(orbitAngle * 1.2);
    final sat1Paint = Paint()
      ..color = MadarColors.goldLight
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(sat1X, sat1Y), size.width * 0.042, sat1Paint);

    // Halo around satellite 1
    final sat1Halo = Paint()
      ..color = MadarColors.gold.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(sat1X, sat1Y), size.width * 0.075, sat1Halo);

    canvas.restore();

    // Orbital path 2 (tilted -35 degrees)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate((-35 * math.pi / 180) - orbitAngle * 0.35);

    final orbitRect2 = Rect.fromCenter(
      center: Offset.zero,
      width: radius * 1.70,
      height: radius * 0.65,
    );

    final orbit2Paint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.transparent,
          MadarColors.gold,
          MadarColors.goldLight,
          Colors.transparent,
        ],
        stops: [0.0, 0.3, 0.7, 1.0],
      ).createShader(orbitRect2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.02;

    canvas.drawOval(orbitRect2, orbit2Paint);

    // Satellite node on Orbit 2
    final sat2X = (radius * 1.70 / 2) * math.cos(math.pi + orbitAngle * 0.9);
    final sat2Y = (radius * 0.65 / 2) * math.sin(math.pi + orbitAngle * 0.9);
    final sat2Paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(sat2X, sat2Y), size.width * 0.035, sat2Paint);

    canvas.restore();

    // Central Core Container (Dark disk with gold border)
    final coreRadius = radius * 0.44;
    final coreBgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.2, -0.2),
        colors: [Color(0xFF263345), Color(0xFF131A24), Color(0xFF090D12)],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, coreBgPaint);

    final coreBorderPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [MadarColors.goldLight, MadarColors.goldDark],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.028;
    canvas.drawCircle(center, coreRadius, coreBorderPaint);

    // Central Nucleus Symbol: Abstract interconnected Madar geometric center
    final nucleusPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [MadarColors.goldLight, MadarColors.gold],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 0.5))
      ..style = PaintingStyle.fill;

    // Center focal point
    canvas.drawCircle(center, coreRadius * 0.30, nucleusPaint);

    // Center white spark / reflection
    final centerCoreLight = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(center.dx - coreRadius * 0.08, center.dy - coreRadius * 0.08),
      coreRadius * 0.10,
      centerCoreLight,
    );

    // Connected geometric nodal rays to outer orbit
    final rayPaint = Paint()
      ..color = MadarColors.gold.withValues(alpha: 0.4)
      ..strokeWidth = size.width * 0.015
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 4; i++) {
      final angle = (i * 90) * math.pi / 180 + (orbitAngle * 0.1);
      final p1 = Offset(
        center.dx + (coreRadius * 0.45) * math.cos(angle),
        center.dy + (coreRadius * 0.45) * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + (coreRadius * 0.85) * math.cos(angle),
        center.dy + (coreRadius * 0.85) * math.sin(angle),
      );
      canvas.drawLine(p1, p2, rayPaint);
      canvas.drawCircle(p2, size.width * 0.02, nucleusPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MadarLogoPainter oldDelegate) {
    return oldDelegate.orbitAngle != orbitAngle;
  }
}

/// A complete, reusable brand lockup for MADAR (Logo + Arabic + English + Descriptor).
class MadarBrandLockup extends StatelessWidget {
  final double logoSize;
  final bool showTagline;
  final bool showDescriptor;

  const MadarBrandLockup({
    super.key,
    this.logoSize = 72,
    this.showTagline = false,
    this.showDescriptor = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MadarOrbitLogo(size: logoSize),
        const SizedBox(height: 18),
        // Arabic Brand Name
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, MadarColors.goldLight, MadarColors.gold],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
          child: const Text(
            'مِدار',
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.5,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        // English Brand Name
        const Text(
          'MADAR',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: MadarColors.gold,
            letterSpacing: 4.5,
          ),
          textAlign: TextAlign.center,
        ),
        if (showDescriptor) ...[
          const SizedBox(height: 8),
          const Text(
            'منظومة إدارة الأعمال',
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: MadarColors.textSecondary,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (showTagline) ...[
          const SizedBox(height: 10),
          const Text(
            'إدارة. تشغيل. نمو.',
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: MadarColors.goldLight,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
