import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Displayed in release builds if the binary was compiled without injecting
/// the required LICENSE_SECRET_KEY via --dart-define.
class LicenseMisconfigurationApp extends StatelessWidget {
  const LicenseMisconfigurationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1E1E2C),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              color: const Color(0xFF2D2D3F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amberAccent,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'خطأ في إعدادات الترخيص',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'تم إنشاء هذه النسخة دون تزويد مفتاح التشفير المطلوب (LICENSE_SECRET_KEY).\n'
                      'لحماية أمان النظام والبيانات، تم إيقاف تشغيل التطبيق بالمفتاح الافتراضي.\n'
                      'يرجى إعادة البناء وتمرير المفاتيح عبر --dart-define.',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => SystemNavigator.pop(),
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('إغلاق التطبيق'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
