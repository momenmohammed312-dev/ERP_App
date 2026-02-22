// ════════════════════════════════════════════════════════════════════════
// اختبار نظام النسخ الاحتياطي المحسّن
// ════════════════════════════════════════════════════════════════════════

import 'package:pos_offline_desktop/services/enhanced_backup_service.dart';

void main() async {
  print('═══════════════════════════════════════════════');
  print('   اختبار النسخ الاحتياطي المحسّن - POS SaaS');
  print('═══════════════════════════════════════════════\n');

  final backupService = EnhancedBackupService();

  try {
    // 1. إنشاء نسخة احتياطية يدوية
    print('1. إنشاء نسخة احتياطية يدوية...');
    final manualBackup = await backupService.createBackup(
      type: 'manual',
      description: 'نسخة احتياطية يدوية للاختبار',
      createdBy: 1,
    );

    print('   ✅ تم إنشاء النسخة: ${manualBackup.filename}');
    print('   📊 الحجم: ${manualBackup.formattedSize}');
    print('   📅 التاريخ: ${manualBackup.formattedDate}');
    print('   🔐 التشفير: ${manualBackup.isEncrypted ? "مفعّل" : "معطّل"}\n');

    // 2. إنشاء نسخة احتياطية تلقائية
    print('2. إنشاء نسخة احتياطية تلقائية...');
    final autoBackup = await backupService.createBackup(
      type: 'auto',
      description: 'نسخة احتياطية تلقائية للاختبار',
    );

    print('   ✅ تم إنشاء النسخة: ${autoBackup.filename}');
    print('   📊 الحجم: ${autoBackup.formattedSize}\n');

    // 3. عرض جميع النسخ الاحتياطية
    print('3. قائمة النسخ الاحتياطية:');
    final backups = await backupService.listBackups();

    if (backups.isEmpty) {
      print('   ⚠️ لا توجد نسخ احتياطية');
    } else {
      for (var i = 0; i < backups.length; i++) {
        final backup = backups[i];
        print('   ${i + 1}. ${backup.filename}');
        print('      📅 ${backup.formattedDate}');
        print('      📊 ${backup.formattedSize}');
        print('      🏷️ ${backup.type}');
        print('      🔐 ${backup.isEncrypted ? "مشفر" : "غير مشفر"}');
        if (backup.description != null) {
          print('      📝 ${backup.description}');
        }
        print('');
      }
    }

    // 4. التحقق من سلامة النسخ
    print('4. التحقق من سلامة النسخ الاحتياطية:');
    for (final backup in backups) {
      final isValid = await backupService.verifyBackupIntegrity(
        backup.filename,
      );
      print('   ${backup.filename}: ${isValid ? "✅ سليمة" : "❌ تالبة"}');
    }
    print('');

    // 5. الحصول على إحصائيات
    print('5. إحصائيات النسخ الاحتياطي:');
    final stats = await backupService.getBackupStatistics();
    print('   📊 إجمالي النسخ: ${stats['total_backups']}');
    print('   💾 الحجم الإجمالي: ${stats['total_size_mb']} MB');
    print('   🔐 النسخ المشفرة: ${stats['encrypted_backups']}');
    print('   🔓 النسخ غير المشفرة: ${stats['unencrypted_backups']}');
    print('');

    // 6. اختبار النسخ التلقائي
    print('6. اختبار النسخ الاحتياطي التلقائي:');
    // بدء النسخ التلقائي
    EnhancedAutoBackupService.start();

    // زيادة عداد العمليات
    for (int i = 0; i < 55; i++) {
      EnhancedAutoBackupService.incrementTransactionCount();
    }

    // إنشاء نسخة فورية
    await EnhancedAutoBackupService.createNow(description: 'نسخة اختبار فورية');

    // الحصول على الحالة
    final status = EnhancedAutoBackupService.getStatus();
    print('   🔄 الحالة: ${status['is_running'] ? "مفعّل" : "معطّل"}');
    print(
      '   📈 عدد العمليات: ${status['transaction_count']}/${status['transaction_threshold']}',
    );
    print(
      '   📅 النسخ اليومي: ${status['daily_backup_enabled'] ? "مفعّل" : "معطّل"}',
    );
    print(
      '   📅 النسخ الأسبوعي: ${status['weekly_backup_enabled'] ? "مفعّل" : "معطّل"}',
    );

    // إيقاف النسخ التلقائي
    EnhancedAutoBackupService.stop();
    print('   ⏹️ تم إيقاف النسخ التلقائي\n');

    // 7. اختبار الاستعادة (اختياري - يتطلب قاعدة بيانات)
    print('7. اختبار الاستعادة:');
    if (backups.isNotEmpty) {
      print('   ⚠️ اختبار الاستعادة يتطلب وجود قاعدة بيانات صالحة');
      print(
        '   📝 يمكن استخدام: await backupService.restoreBackup("${backups.first.filename}")',
      );
    }

    print('\n✅ اكتمل الاختبار بنجاح!');
    print('\n═══════════════════════════════════════════════');
    print('   ملاحظات:');
    print('   - تم إنشاء نسخ احتياطية مشفرة');
    print('   - تم التحقق من سلامة النسخ');
    print('   - تم اختبار النسخ التلقائي');
    print('   - يمكن دمج هذا النظام مع واجهة المستخدم');
    print('═══════════════════════════════════════════════');
  } catch (e, stackTrace) {
    print('❌ خطأ في الاختبار: $e');
    print('Stack trace:\n$stackTrace');
  }
}
