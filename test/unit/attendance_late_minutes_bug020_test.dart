import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/product/widgets/product_form.dart';
import '../helpers/license_grant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  group('BUG-020: Attendance late_minutes repair & Barcode Quantity Guard', () {
    setUp(() {
      grantLicensedModules();
    });

    tearDown(() {
      revokeLicensedModules();
    });

    test('Case 1: Unit test for _repairCorruptedAttendanceLateMinutes() local time calculation & idempotency', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // 1. إعداد جدول الإعدادات: الدوام يبدأ 08:00 وينتهي 16:00، فترة السماح 10 دقائق
      await db.into(db.attendanceSettings).insert(
        AttendanceSettingsCompanion.insert(
          settingKey: 'default_work_start',
          settingValue: '08:00',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await db.into(db.attendanceSettings).insert(
        AttendanceSettingsCompanion.insert(
          settingKey: 'default_work_end',
          settingValue: '16:00',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await db.into(db.attendanceSettings).insert(
        AttendanceSettingsCompanion.insert(
          settingKey: 'grace_period_minutes',
          settingValue: '10',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // 2. إدخال موظفين
      await db.into(db.staffTable).insert(
        StaffTableCompanion.insert(
          staffId: 'EMP-01',
          name: 'موظف 1',
          position: 'كاشير',
          employmentType: 'full_time',
          basicSalary: 6000.0,
          hireDate: DateTime(2026, 1, 1),
          status: 'active',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );

      // موظف 2 بجدول عمل مخصص يبدأ 09:00
      await db.into(db.staffTable).insert(
        StaffTableCompanion.insert(
          staffId: 'EMP-02',
          name: 'موظف 2',
          position: 'مبيعات',
          employmentType: 'full_time',
          basicSalary: 6000.0,
          hireDate: DateTime(2026, 1, 1),
          status: 'active',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          useDefaultSchedule: const Value(false),
          workScheduleStart: const Value('09:00'),
          workScheduleEnd: const Value('17:00'),
        ),
      );

      // 3. إدخال سجلات حضور مشوهة بالمعادلة القديمة
      // موظف 1 حضر 08:05 (داخل فترة السماح 10 دقائق): كان مسجلاً late_minutes = 485 بالخطأ
      final t1 = DateTime(2026, 9, 1, 8, 5);
      final id1 = await db.into(db.attendanceTable).insert(
        AttendanceTableCompanion.insert(
          staffId: 'EMP-01',
          date: DateTime(2026, 9, 1),
          status: 'late',
          lateMinutes: const Value(485), // قيمة مشوهة
          checkInTime: Value(t1),
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );

      // موظف 1 حضر 08:30 (متأخر 30 دقيقة عن 08:00): كان مسجلاً late_minutes = 850 بالخطأ
      final t2 = DateTime(2026, 9, 2, 8, 30);
      final id2 = await db.into(db.attendanceTable).insert(
        AttendanceTableCompanion.insert(
          staffId: 'EMP-01',
          date: DateTime(2026, 9, 2),
          status: 'late',
          lateMinutes: const Value(850), // قيمة مشوهة
          checkInTime: Value(t2),
          createdAt: DateTime(2026, 9, 2),
          updatedAt: DateTime(2026, 9, 2),
        ),
      );

      // موظف 2 حضر 09:25 (متأخر 25 دقيقة عن جدوله 09:00): كان مسجلاً 600 بالخطأ
      final t3 = DateTime(2026, 9, 3, 9, 25);
      final id3 = await db.into(db.attendanceTable).insert(
        AttendanceTableCompanion.insert(
          staffId: 'EMP-02',
          date: DateTime(2026, 9, 3),
          status: 'late',
          lateMinutes: const Value(600), // قيمة مشوهة
          checkInTime: Value(t3),
          createdAt: DateTime(2026, 9, 3),
          updatedAt: DateTime(2026, 9, 3),
        ),
      );

      // 4. حذف قيد _migration_log إن وجد لضمان تشغيل دالة التصحيح
      await db.customStatement(
        "DELETE FROM _migration_log WHERE step = 'v80_repair_attendance_late_minutes'",
      );

      // 5. استدعاء دالة الإصلاح
      await db.repairCorruptedAttendanceLateMinutes();

      // 6. التحقق من القيم المصححة
      final row1 = await (db.select(db.attendanceTable)..where((t) => t.id.equals(id1))).getSingle();
      final row2 = await (db.select(db.attendanceTable)..where((t) => t.id.equals(id2))).getSingle();
      final row3 = await (db.select(db.attendanceTable)..where((t) => t.id.equals(id3))).getSingle();

      // الموظف 1 حضر 08:05 (داخل سماح 10 دقائق من 08:00) => تأخير 0 وحالة present
      expect(row1.lateMinutes, equals(0));
      expect(row1.status, equals('present'));

      // الموظف 1 حضر 08:30 (تجاوز السماح) => تأخير 30 دقيقة بالضبط
      expect(row2.lateMinutes, equals(30));
      expect(row2.status, equals('late'));

      // الموظف 2 بجدول خاص 09:00 وحضر 09:25 (تجاوز السماح) => تأخير 25 دقيقة بالضبط
      expect(row3.lateMinutes, equals(25));
      expect(row3.status, equals('late'));

      // 7. التحقق من الـ Idempotency: تشغيلها مرة ثانية لا يغير شيئاً
      await db.repairCorruptedAttendanceLateMinutes();
      final row2Again = await (db.select(db.attendanceTable)..where((t) => t.id.equals(id2))).getSingle();
      expect(row2Again.lateMinutes, equals(30));
    });

    test('Case 2: Live verification on temporary copy of client database (scratch/client_copy.sqlite)', () async {
      final clientCopy = File('scratch/client_copy.sqlite');
      if (!clientCopy.existsSync()) {
        // Skip if client copy is not found
        return;
      }

      final tempFile = File('scratch/temp_bug020_client.sqlite');
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      clientCopy.copySync(tempFile.path);

      AppDatabase? clientDb;
      try {
        // فتح قاعدة بيانات العميل المؤقتة عبر AppDatabase (ستقوم بتشغيل onUpgrade إلى v80 و beforeOpen وإصلاح الدقائق)
        clientDb = AppDatabase(NativeDatabase(tempFile));

        // قراءة مجاميع دقائق التأخير بعد تشغيل beforeOpen وإصلاح v80
        final summary = await clientDb.customSelect(
          'SELECT SUM(late_minutes) as total_late, COUNT(*) as cnt FROM attendance_table WHERE check_in_time IS NOT NULL',
        ).getSingle();

        final totalLate = summary.read<int?>('total_late') ?? 0;
        final totalCount = summary.read<int>('cnt');

        // تحقق من انخفاض مجموع الدقائق من 1,318,336 إلى النطاق الواقعي (< 150,000 دقيقة)
        expect(totalLate, lessThan(150000),
            reason: 'Total late minutes should drop from 1.3M to normal range');

        // تحقق من أن الصفوف الشاذة (> 600 دقيقة أي أكثر من 10 ساعات تأخير في اليوم) اختفت تماماً أو أصبحت 0
        final excessiveLate = await clientDb.customSelect(
          'SELECT COUNT(*) as cnt FROM attendance_table WHERE late_minutes > 600',
        ).getSingle();

        final excessiveCount = excessiveLate.read<int>('cnt');
        expect(excessiveCount, equals(0),
            reason: 'Zero rows should have late_minutes > 600 after repair');

        // تحقق من تسجيل نجاح الخطوة في _migration_log
        final logRows = await clientDb.customSelect(
          "SELECT status FROM _migration_log WHERE step = 'v80_repair_attendance_late_minutes'",
        ).get();
        expect(logRows, isNotEmpty);
        expect(logRows.first.read<String>('status'), equals('completed'));
      } finally {
        await clientDb?.close();
        if (tempFile.existsSync()) {
          try {
            tempFile.deleteSync();
          } catch (_) {}
        }
      }
    });

    testWidgets('Case 3: Product Form Quantity Barcode Guard validator rejects > 999999', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ar'),
          home: Scaffold(
            body: ProductForm(db: db),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // البحث عن حقل الكمية وإدخال باركود مكون من 13 رقماً
      final qtyFinder = find.widgetWithText(TextFormField, 'الكمية');
      expect(qtyFinder, findsOneWidget);

      // إدخال باركود 13 رقماً في خانة الكمية
      await tester.enterText(qtyFinder, '6223001234567');
      await tester.pumpAndSettle();

      // محاولة الحفظ عبر زر الحفظ
      final saveBtnFinder = find.text('حفظ المنتج');
      expect(saveBtnFinder, findsOneWidget);
      await tester.ensureVisible(saveBtnFinder);
      await tester.tap(saveBtnFinder);
      await tester.pumpAndSettle();

      // يجب أن يظهر تنبيه منع مسح الباركود في حقل الكمية
      expect(find.text('الكمية كبيرة جداً — تأكد من عدم مسح الباركود في حقل الكمية'), findsOneWidget);

      // إدخال كمية طبيعية (مثلاً 50 قطعة)
      await tester.enterText(qtyFinder, '50');
      await tester.pumpAndSettle();
      await tester.ensureVisible(saveBtnFinder);
      await tester.tap(saveBtnFinder);
      await tester.pumpAndSettle();

      // يجب ألا تظهر رسالة الخطأ الخاصة بالباركود
      expect(find.text('الكمية كبيرة جداً — تأكد من عدم مسح الباركود في حقل الكمية'), findsNothing);
    });
  });
}

