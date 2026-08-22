import 'dart:io';

import 'package:drift/drift.dart' show isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

/// اختبار حارس لملف الـ backup:
/// 1) يتأكد من أسماء الجداول الفعلية في SQLite (staff_table وليس staff مثلاً).
/// 2) يقرأ قائمتي الجداول من backup_service.dart ويتأكد أن كل اسم فيها
///    جدول موجود فعلاً في قاعدة البيانات — أي اسم غلط يعني بيانات مش بتتحفظ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUpAll(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDownAll(() async {
    await database.close();
  });

  /// يقرأ أسماء الجداول من كتلة معينة داخل backup_service.dart
  Set<String> extractList(String source, String listStartMarker) {
    final start = source.indexOf(listStartMarker);
    expect(start, greaterThanOrEqualTo(0),
        reason: 'لم يتم العثور على $listStartMarker');
    final openBracket = source.indexOf('[', start);
    final closeBracket = source.indexOf('];', openBracket);
    expect(closeBracket, greaterThan(openBracket));
    final body = source.substring(openBracket, closeBracket);
    return RegExp(r"'([a-z_]+)'")
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();
  }

  test('actual SQLite table names match names used in backup_service', () async {
    // فتح أول استعلام يشغّل الـ migrations وينشئ كل الجداول
    await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '\\_migration%' ESCAPE '\\' "
      'AND name NOT LIKE \'database\\_%\' ESCAPE \'\\\'',
    ).get();

    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final sqliteTables = rows.map((r) => r.data['name'] as String).toSet();

    // الأسماء الفعلية المؤكدة (مش المفترضة)
    expect(sqliteTables, contains('staff_table'),
        reason: 'جدول الموظفين اسمه الفعلي staff_table');
    expect(sqliteTables, contains('attendance_table'),
        reason: 'جدول الحضور اسمه الفعلي attendance_table');
    expect(sqliteTables, contains('employees'));
    expect(sqliteTables, contains('biometric_devices'));

    // الأسماء الخاطئة التي كانت مستخدمة سابقاً في الـ backup ولا يجب أن تعود
    expect(sqliteTables, isNot(contains('staff')));
    expect(sqliteTables, isNot(contains('attendance')));

    // قراءة قائمتي الجداول من ملف الـ backup ومطابقتهما مع الواقع
    final source =
        File('lib/core/services/backup_service.dart').readAsStringSync();
    final backupList = extractList(source, 'final tables = [');
    final restoreOrder = extractList(source, 'final tableOrder = [');

    expect(restoreOrder, backupList,
        reason: 'قائمة الاستعادة لازم تحتوي نفس جداول النسخ');

    for (final tableName in backupList) {
      expect(sqliteTables, contains(tableName),
          reason: "جدول '$tableName' موجود في backup_service لكن غير موجود في SQLite");
    }

    for (final tableName in sqliteTables) {
      if (tableName.startsWith('database_') || tableName.startsWith('_')) {
        continue;
      }
      expect(backupList, contains(tableName),
          reason: "جدول '$tableName' موجود في SQLite لكن ناقص من الـ backup");
    }
  });

  test('restore order respects foreign keys', () async {
    final source =
        File('lib/core/services/backup_service.dart').readAsStringSync();
    final order = extractList(source, 'final tableOrder = [').toList();

    int indexOf(String t) {
      final i = order.indexOf(t);
      expect(i, greaterThanOrEqualTo(0), reason: '$t مفقود من ترتيب الاستعادة');
      return i;
    }

    final staffIdx = indexOf('staff_table');
    // كل ما يعتمد على الموظفين ييجي بعدهم
    for (final child in [
      'attendance_table',
      'vacations',
      'staff_advances',
      'payroll_table',
      'rewards_penalties',
      'performance_reviews',
      'staff_documents',
    ]) {
      expect(indexOf(child), greaterThan(staffIdx),
          reason: '$child لازم يكون بعد staff_table');
    }

    final devicesIdx = indexOf('biometric_devices');
    for (final child in [
      'staff_biometric_mappings',
      'attendance_raw_events',
      'attendance_sync_logs',
    ]) {
      expect(indexOf(child), greaterThan(devicesIdx),
          reason: '$child لازم يكون بعد biometric_devices');
    }
  });
}
