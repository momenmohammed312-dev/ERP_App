import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/widgets/brand/madar_contact_dialog.dart';
import 'package:pos_offline_desktop/widgets/brand/madar_logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0D1117) : MadarColors.lightBgApp;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final borderColor = isDark ? const Color(0xFF30363D) : MadarColors.lightBorder;
    final accent = isDark ? MadarColors.gold : MadarColors.lightPrimary;
    final muted = isDark ? Colors.white60 : MadarColors.lightTextSecondary;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          backgroundColor: cardBg,
          foregroundColor: isDark ? Colors.white : MadarColors.lightTextPrimary,
          title: Text(
            'حول مِدار — MADAR ERP',
            style: TextStyle(color: accent, fontWeight: FontWeight.bold),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),
              const MadarOrbitLogo(size: 72),
              const SizedBox(height: 14),
              Text(
                kMadarAppTitleAr,
                style: TextStyle(
                  color: accent,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$kMadarAppVersion • نظام نقاط البيع والمحاسبة المتكامل',
                style: TextStyle(color: muted, fontSize: 14),
              ),
              const SizedBox(height: 28),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    _buildCard(
                      context,
                      cardBg,
                      borderColor,
                      accent,
                      'نظرة عامة',
                      '''
نظام نقاط بيع وإدارة عمليات متكامل يعمل محلياً دون اتصال بالإنترنت.
قاعدة بيانات SQLite محلية مشفرة ومحمية مع نسخ احتياطي آمن.
دعم كامل للغة العربية (RTL) والوضعين الفاتح والداكن.
                      ''',
                    ),
                    _buildCard(
                      context,
                      cardBg,
                      borderColor,
                      accent,
                      'المميزات',
                      '''
• إدارة الفواتير: نقدي / آجل / موردين ومرتجعات
• إدارة المخزون والمنتجات والتالف والجرد
• محاسبة العملاء والموردين (دفتر أستاذ)
• تقارير شاملة: PDF / Excel
• إدارة الموظفين: رواتب / حضور / إجازات
• نظام صلاحيات متعدد المستويات
• نسخ احتياطي تلقائي مُشفَّر
• ترخيص مُرتبط بالجهاز
                      ''',
                    ),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'طرق التواصل والدعم الفني',
                            style: TextStyle(
                              color: accent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          buildMadarContactInlineBox(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '© 2026 $kMadarDeveloperName — جميع الحقوق محفوظة',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                'Developed By $kMadarDeveloperName',
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    Color cardBg,
    Color borderColor,
    Color accent,
    String title,
    String content,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content.trim(),
            style: TextStyle(
              color: isDark ? Colors.white70 : MadarColors.lightTextPrimary,
              fontSize: 13,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}
