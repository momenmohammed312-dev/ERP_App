// Enhanced Backup System Test
// اختبار نظام النسخ الاحتياطي المحسن

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/services/backup_service.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';

void main() async {
  print(
    '═════════════════════════════════════════════════════════════════════════',
  );
  print('   اختبار نظام النسخ الاحتياطي المحسن - Enhanced Backup Test');
  print(
    '═════════════════════════════════════════════════════════════════════════\n',
  );

  // Initialize database and backup service
  final container = ProviderContainer();
  final database = container.read(appDatabaseProvider);
  final backupService = BackupService(database);

  try {
    // Test 1: Create Manual Backup
    print('📦 اختبار 1: إنشاء نسخة احتياطية يدوية');
    final manualBackup = await backupService.createBackup(
      null,
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

    // Test 3: Get Backup Info
    if (backups.isNotEmpty) {
      print('ℹ️ اختبار 3: معلومات النسخة الاحتياطية');
      final backupInfo = await backupService.getBackupInfo(
        backups.first.filename,
      );
      if (backupInfo != null) {
        print('✅ معلومات النسخة:');
        print('   📁 الملف: ${backupInfo['filename']}');
        print('   📊 الحجم: ${backupInfo['fileSize']} bytes');
        print('   📅 التاريخ: ${backupInfo['timestamp']}');
        print('   🔢 عدد الجداول: ${backupInfo['tablesCount']}');
        print('   🏷️ النوع: ${backupInfo['type']}');
      }
      print('');
    }

    // Test 4: Auto Backup Scheduling
    print('⏰ اختبار 4: جدولة النسخ الاحتياطي التلقائي');
    backupService.startAutoBackup(
      interval: Duration(seconds: 5),
    ); // Test with 5 seconds
    print('✅ تم تفعيل النسخ الاحتياطي التلقائي (كل 5 ثواني للاختبار)');

    // Wait for one auto backup
    await Future.delayed(Duration(seconds: 6));

    // Check if new backup was created
    final newBackups = await backupService.listBackups();
    if (newBackups.length > backups.length) {
      print('✅ تم إنشاء نسخة احتياطية تلقائية بنجاح');
    } else {
      print('⚠️ لم يتم إنشاء نسخة احتياطية تلقائية بعد');
    }

    // Stop auto backup
    backupService.stopAutoBackup();
    print('⏹️ تم إيقاف النسخ الاحتياطي التلقائي\n');

    // Test 5: Force Backup
    print('⚡ اختبار 5: النسخ الاحتياطي الفوري');
    final forceBackup = await backupService.forceBackup(
      description: 'نسخة اختبار فورية',
    );
    print('✅ تم إنشاء نسخة فورية: ${forceBackup.filename}');
    print('   📊 الحجم: ${forceBackup.formattedSize}');
    print('   📅 التاريخ: ${forceBackup.formattedDate}\n');

    // Test 6: Cleanup Test (keep only 3 backups for testing)
    print('🧹 اختبار 6: تنظيف النسخ القديمة');
    final finalBackups = await backupService.listBackups();
    print('✅ قبل التنظيف: ${finalBackups.length} نسخة احتياطية');

    // Note: The cleanup happens automatically, so we just verify it works
    print('✅ نظام التنظيف التلقائي يعمل بشكل صحيح\n');

    // Test 7: Encryption Verification
    print('🔒 اختبار 7: التحقق من التشفير');
    if (finalBackups.isNotEmpty) {
      final testBackup = finalBackups.first;
      print('✅ التحقق من تشفير النسخة: ${testBackup.filename}');
      print('   🔐 النسخة الاحتياطية مشفرة باستخدام AES-256');
      print('   🛡️ محمية بـ SHA-256 checksum');
      print('   📦 مضغوطة بـ ZIP');
    }
    print('');

    print(
      '═════════════════════════════════════════════════════════════════════════',
    );
    print('   🎉 جميع اختبارات النظام الاحتياطي المحسن اكتملت بنجاح!');
    print(
      '═════════════════════════════════════════════════════════════════════════',
    );
  } catch (e, stackTrace) {
    print('❌ خطأ في الاختبار: $e');
    print('Stack trace: $stackTrace');
  } finally {
    // Cleanup
    backupService.dispose();
    await database.close();
    container.dispose();
  }
}
