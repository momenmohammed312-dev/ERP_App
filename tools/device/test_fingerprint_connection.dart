import 'dart:io';

import 'package:pos_offline_desktop/services/attendance/zkteco/zkteco_client.dart';

const int _defaultPort = 4370;

void main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    _printUsage();
    exit(args.isEmpty ? 64 : 0);
  }

  final host = args[0].trim();
  if (host.isEmpty) {
    stderr.writeln('الخطأ: عنوان الجهاز (IP/hostname) مطلوب.');
    _printUsage();
    exit(64);
  }

  int port = _defaultPort;
  if (args.length > 1) {
    final parsed = int.tryParse(args[1].trim());
    if (parsed == null || parsed < 1 || parsed > 65535) {
      stderr.writeln('الخطأ: البورت غير صالح: "${args[1]}"');
      _printUsage();
      exit(64);
    }
    port = parsed;
  }

  int commKey = 0;
  if (args.length > 2) {
    final parsed = int.tryParse(args[2].trim());
    if (parsed == null) {
      stderr.writeln('الخطأ: CommKey يجب أن يكون رقمًا: "${args[2]}"');
      _printUsage();
      exit(64);
    }
    commKey = parsed;
  }

  final withData = args.contains('--with-data');

  print('=================================');
  print('  اختبار اتصال جهاز البصمة');
  print('=================================');
  print('الجهاز : $host');
  print('البورت : $port');
  print('CommKey: $commKey');
  print('---------------------------------');
  print('جاري الاتصال...');

  final client = ZKTecoClient(
    host: host,
    port: port,
    commKey: commKey,
    timeout: const Duration(seconds: 8),
  );

  final connected = await client.connect();
  if (!connected) {
    print('✗ فشل الاتصال بـ $host:$port');
    print('تحقق من:');
    print('  - صحة الـ IP والبورت');
    print('  - أن الجهاز على نفس الشبكة');
    print('  - أن الجدار الناري لا يحجب البورت $port');
    print('  - CommKey الصحيح لو الجهاز محمي');
    await client.disconnect();
    exit(1);
  }

  print('✓ متصل بنجاح (sessionId=${client.sessionId})');
  print('---------------------------------');

  try {
    final info = await client.getDeviceInfo();
    print('معلومات الجهاز:');
    print('  الاسم          : ${info.deviceName ?? '-'}');
    print('  Firmware       : ${info.firmwareVersion ?? '-'}');
    print('  Serial Number  : ${info.serialNumber ?? '-'}');
    print('  Platform       : ${info.platform ?? '-'}');
    print('  وقت الجهاز    : ${info.deviceTime ?? '-'}');

    if (withData) {
      final users = await client.getUsers();
      final records = await client.getAttendanceRecords();
      print('---------------------------------');
      print('المستخدمون على الجهاز : ${users.length}');
      print('سجلات الحضور          : ${records.length}');
      if (users.isNotEmpty) {
        final sample = users.take(5).map((u) => u.userId).join(', ');
        print('  عينة userId        : $sample');
      }
    }
  } catch (e) {
    print('⚠ الاتصال نجح لكن قراءة المعلومات فشلت: $e');
  } finally {
    await client.disconnect();
  }

  print('---------------------------------');
  print('✓ تم إغلاق الاتصال.');
  print('النتيجة: SUCCESS');
  exit(0);
}

void _printUsage() {
  print('اختبار اتصال جهاز بصمة ZKTeco عبر TCP');
  print('');
  print('الاستخدام:');
  print('  dart run tools/device/test_fingerprint_connection.dart <host> [port] [commKey] [--with-data]');
  print('');
  print('المعاملات:');
  print('  host        عنوان IP أو اسم الجهاز (مطلوب)');
  print('  port        بورت الجهاز (اختياري، الافتراضي $_defaultPort)');
  print('  commKey     مفتاح CommKey إن وُجد (اختياري، الافتراضي 0)');
  print('  --with-data جرّب قراءة المستخدمين وسجلات الحضور بعد الاتصال');
  print('');
  print('أمثلة:');
  print('  dart run tools/device/test_fingerprint_connection.dart 192.168.1.100');
  print('  dart run tools/device/test_fingerprint_connection.dart 192.168.1.100 4370');
  print('  dart run tools/device/test_fingerprint_connection.dart 192.168.1.100 4370 123456 --with-data');
}
