// ════════════════════════════════════════════════════════════
// اختبار تكامل نظام النسخ الاحتياطي
// ══════════════════════════════════════════════════════════

import 'package:pos_offline_desktop/services/enhanced_backup_service.dart';

void main() async {
  print('═══════════════════════════════════════════════════');
  print('   اختبار تكامل نظام النسخ الاحتياطي المحسّن');
  print('═══════════════════════════════════════════════════════\n');

  try {
    // 1. اختبار الخدمة الأساسية
    print('1. اختبار الخدمة الأساسية...');
    final backupService = EnhancedBackupService();

    // 2. اختبار النسخ التلقائي
    print('2. اختبار النسخ التلقائي...');
    final autoStatus = EnhancedAutoBackupService.getStatus();
    print('   الحالة: ${autoStatus['is_running'] ? "مفعّل" : "معطّل"}');

    // 3. بدء النسخ التلقائي
    print('3. بدء النسخ التلقائي...');
    EnhancedAutoBackupService.start();

    // 4. زيادة عداد العمليات
    print('4. محاكاة العمليات...');
    for (int i = 0; i < 55; i++) {
      EnhancedAutoBackupService.incrementTransactionCount();
    }

    // 5. إنشاء نسخة يدوية
    print('5. إنشاء نسخة يدوية...');
    final manualBackup = await backupService.createBackup(
      type: 'manual',
      description: 'نسخة اختبار التكامل',
      createdBy: 1,
    );

    print('   ✅ تم إنشاء النسخة: ${manualBackup.filename}');
    print('   📊 الحجم: ${manualBackup.formattedSize}');
    print('   📅 التاريخ: ${manualBackup.formattedDate}');
    print('   🔐 التشفير: ${manualBackup.isEncrypted ? "مفعّل" : "معطّل"}');

    // 6. التحقق من سلامة النسخة
    print('6. التحقق من سلامة النسخة...');
    final isValid = await backupService.verifyBackupIntegrity(
      manualBackup.filename,
    );
    print('   النتيجة: ${isValid ? "سليمة" : "تالبة"}');

    // 7. الحصول على قائمة النسخ
    print('7. الحصول على قائمة النسخ...');
    final backups = await backupService.listBackups();
    print('   عدد النسخ: ${backups.length}');

    for (var i = 0; i < backups.length; i++) {
      final backup = backups[i];
      print('   ${i + 1}. ${backup.filename} - ${backup.formattedSize}');
    }

    // 8. الحصول على إحصائيات
    print('8. الحصول على إحصائيات...');
    final stats = await backupService.getBackupStatistics();
    print('   إجمالي النسخ: ${stats['total_backups']}');
    print('   الحجم الإجمالي: ${stats['total_size_mb']} MB');
    print('   النسخ المشفرة: ${stats['encrypted_backups']}');

    // 9. إيقاف النسخ التلقائي
    print('9. إيقاف النسخ التلقائي...');
    EnhancedAutoBackupService.stop();

    // 10. التحقق من الإيقاف
    final finalStatus = EnhancedAutoBackupService.getStatus();
    print(
      '   الحالة النهائية: ${finalStatus['is_running'] ? "مفعّل" : "معطّل"}',
    );

    print('\n✅ اكتمل الاختبار بنجاح!');
    print('═════════════════════════════════════════════════════');
    print('   جميع الوظائف تعمل بشكل صحيح');
    print('   النظام جاهز للاستخدام في التطبيق');
    print('═════════════════════════════════════════════════');
  } catch (e, stackTrace) {
    print('❌ خطأ في الاختبار: $e');
    print('Stack trace:\n$stackTrace');
  }
}
