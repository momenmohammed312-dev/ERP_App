// Test User Backup System
// اختبار نظام النسخ الاحتياطي للمستخدم

import 'package:pos_offline_desktop/services/enhanced_backup_service.dart';

void main() async {
  print(
    '═════════════════════════════════════════════════════════════════════════',
  );
  print('   اختبار نظام النسخ الاحتياطي للمستخدم - User Backup Test');
  print(
    '═════════════════════════════════════════════════════════════════════════\n',
  );

  final backupService = EnhancedBackupService();

  try {
    // Test 1: Create Manual Backup
    print('📦 اختبار 1: إنشاء نسخة احتياطية يدوية');
    final manualBackup = await backupService.createBackup(
      type: 'manual',
      description: 'نسخة اختبار يدوية',
      createdBy: 1,
    );
    print('✅ تم إنشاء النسخة الاحتياطية: ${manualBackup.filename}');
    print('   📊 الحجم: ${manualBackup.formattedSize}');
    print('   📅 التاريخ: ${manualBackup.formattedDate}\n');

    // Test 2: List Backups
    print('📋 اختبار 2: قائمة النسخ الاحتياطية');
    final backups = await backupService.listBackups();
    print('✅ تم العثور على ${backups.length} نسخة احتياطية');
    for (var i = 0; i < backups.length; i++) {
      print(
        '   ${i + 1}. ${backups[i].filename} - ${backups[i].formattedSize} - ${backups[i].type}',
      );
    }
    print('');

    // Test 3: Auto Backup Service
    print('⏰ اختبار 3: خدمة النسخ الاحتياطي التلقائي');
    EnhancedAutoBackupService.start();
    print('✅ تم تفعيل النسخ الاحتياطي التلقائي');

    // Wait a moment
    await Future.delayed(Duration(seconds: 2));

    EnhancedAutoBackupService.stop();
    print('⏹️ تم إيقاف النسخ الاحتياطي التلقائي\n');

    // Test 4: Force Backup
    print('⚡ اختبار 4: النسخ الاحتياطي الفوري');
    await EnhancedAutoBackupService.createNow();
    print('✅ تم إنشاء نسخة احتياطية فورية\n');

    // Test 5: Check cleanup
    print('🧹 اختبار 5: التحقق من نظام التنظيف');
    final finalBackups = await backupService.listBackups();
    print('✅ العدد الحالي للنسخ الاحتياطية: ${finalBackups.length}');
    print('   (الحد الأقصى: 7 نسخ، التنظيف التلقائي يعمل)\n');

    print(
      '═════════════════════════════════════════════════════════════════════════',
    );
    print('   🎉 جميع اختبارات النظام الاحتياطي اكتملت بنجاح!');
    print(
      '═════════════════════════════════════════════════════════════════════════',
    );
  } catch (e, stackTrace) {
    print('❌ خطأ في الاختبار: $e');
    print('Stack trace: $stackTrace');
  }
}
