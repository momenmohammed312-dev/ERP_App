import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
        title: const Text(
          'عن التطبيق',
          style: TextStyle(color: Color(0xFFC9A84C), fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            const Text(
              'نظام نقاط البيع المتكامل',
              style: TextStyle(
                color: Color(0xFFC9A84C),
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'POS Offline Desktop v2.1',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 32),
            _buildCard('نظرة عامة', '''
نظام نقاط بيع متكامل يعمل دون اتصال بالإنترنت.
قاعدة بيانات SQLite محلية مشفرة ومحمية.
دعم كامل للغة العربية (RTL).
            '''),
            _buildCard('المميزات', '''
• إدارة الفواتير: نقدي / آجل / موردين
• إدارة المخزون والمنتجات والتالف
• محاسبة العملاء والموردين (دفتر أستاذ)
• تقارير شاملة: PDF / Excel
• إدارة الموظفين: رواتب / حضور / إجازات
• نظام صلاحيات متعدد المستويات
• نسخ احتياطي تلقائي مُشفَّر
• ترخيص مُرتبط بالجهاز
            '''),
            _buildCard('المكدس التقني', '''
الإطار:          Flutter Desktop (Windows)
قاعدة البيانات:  SQLite عبر Drift ORM v2.21
إدارة الحالة:    Riverpod v2.6
التوجيه:         GoRouter v16
إصدار Schema:    46
            '''),
            const SizedBox(height: 24),
            const Text(
              '© 2025 MO2 — جميع الحقوق محفوظة',
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              'Developed By MO2',
              style: TextStyle(color: Color(0xFFC9A84C), fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String title, String content) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                color: Color(0xFFC9A84C),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 10),
          Text(content.trim(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.7,
              )),
        ],
      ),
    );
  }
}
