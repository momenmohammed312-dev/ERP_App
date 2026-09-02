import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/utils/pdf_bidi_helper.dart';

class StaffPayrollStatementGenerator {
  static Future<Map<String, pw.Font?>> _loadFonts() async {
    pw.Font? arabicFont;
    pw.Font? arabicBoldFont;
    final latinFont = pw.Font.helvetica();

    try {
      final regularFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (regularFontData.lengthInBytes > 100) {
        arabicFont = pw.Font.ttf(regularFontData);
      }
    } catch (_) {}

    try {
      final boldFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (boldFontData.lengthInBytes > 100) {
        arabicBoldFont = pw.Font.ttf(boldFontData);
      }
    } catch (_) {}

    arabicFont ??= latinFont;
    arabicBoldFont ??= latinFont;

    return {
      'arabic': arabicFont,
      'arabicBold': arabicBoldFont,
      'latin': latinFont,
    };
  }

  static String _b(String text) => PdfBidiHelper.reorder(text);

  static Future<void> generateAndPrint({
    required BuildContext context,
    required AppDatabase db,
    required Staff staff,
    required List<Payroll> payrollRecords,
  }) async {
    final fonts = await _loadFonts();
    final arabicFont = fonts['arabic'];
    final arabicBoldFont = fonts['arabicBold'];

    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');

    final tableHeaders = [
      _b('الشهر'),
      _b('صافي المرتب'),
      _b('السلف المخصومة'),
      _b('الجزاءات'),
      _b('تاريخ الصرف'),
      _b('الحالة'),
    ];

    final tableData = payrollRecords.map((p) {
      final paymentDateStr = p.paymentDate != null
          ? dateFormat.format(p.paymentDate!)
          : dateFormat.format(p.periodEnd);
      String statusStr = p.status;
      switch (p.status) {
        case 'paid':
          statusStr = 'مدفوع';
          break;
        case 'approved':
          statusStr = 'معتمد';
          break;
        case 'calculated':
          statusStr = 'محسوب';
          break;
        case 'draft':
          statusStr = 'مسودة';
          break;
        case 'cancelled':
          statusStr = 'ملغي';
          break;
      }

      return [
        _b(p.payrollPeriod),
        _b(p.netSalary.toStringAsFixed(2)),
        _b(p.advances.toStringAsFixed(2)),
        _b(p.penaltiesTotal.toStringAsFixed(2)),
        _b(paymentDateStr),
        _b(statusStr),
      ];
    }).toList();

    // حساب ساعات التأخير/الانصراف المبكر الحقيقية لكل فترة من سجلات الحضور
    final Map<int, Map<String, dynamic>> payrollDetails = {};
    for (final p in payrollRecords) {
      final atts = await db.staffManagementDao.getAttendanceByStaff(staff.staffId, startDate: p.periodStart, endDate: p.periodEnd.add(const Duration(days: 1)));
      // نحتاج إعدادات grace و workStart/End لحساب الدقائق
      String workStart = '08:00';
      String workEnd = '17:00';
      int grace = 15;
      double lateMult = 0;
      double earlyMult = 0;
      double absencePerDay = 0;
      double absenceMult = 1.0;
      try {
        final settings = await db.select(db.attendanceSettings).get();
        for (final s in settings) {
          if (s.settingKey == 'default_work_start') workStart = s.settingValue;
          if (s.settingKey == 'default_work_end') workEnd = s.settingValue;
          if (s.settingKey == 'grace_period_minutes') grace = int.tryParse(s.settingValue) ?? 15;
          if (s.settingKey == 'late_penalty_per_hour') lateMult = double.tryParse(s.settingValue) ?? 0;
          if (s.settingKey == 'early_leave_penalty_per_hour') earlyMult = double.tryParse(s.settingValue) ?? 0;
          if (s.settingKey == 'absence_penalty_amount') absencePerDay = double.tryParse(s.settingValue) ?? 0;
          if (s.settingKey == 'absence_penalty_days_multiplier') absenceMult = double.tryParse(s.settingValue) ?? 1.0;
        }
      } catch (_) {}
    if (!staff.useDefaultSchedule) {
      if (staff.workScheduleStart != null && staff.workScheduleStart!.isNotEmpty) workStart = staff.workScheduleStart!;
      if (staff.workScheduleEnd != null && staff.workScheduleEnd!.isNotEmpty) workEnd = staff.workScheduleEnd!;
    }
          int sMin = 9*60; int eMin = 17*60;
      try { final pa = workStart.split(':'); sMin = (int.tryParse(pa[0])??9)*60 + (int.tryParse(pa[1])??0); } catch(_){}
      try { final pa = workEnd.split(':'); eMin = (int.tryParse(pa[0])??17)*60 + (int.tryParse(pa[1])??0); } catch(_){}
      final gEnd = sMin + grace;
      int lateMin = 0; int earlyMin = 0;
      bool isLateAtt(Attendance a) {
        if (a.excused && a.excusedHours <= 0) return false; // بإذن كامل — لا يُحسب تأخير
        if (a.status == 'late') return true;
        if (a.status == 'present' && a.checkInTime != null) {
          final ci = a.checkInTime!.hour*60 + a.checkInTime!.minute;
          return ci > gEnd;
        }
        return false;
      }
      // الخصم التناسبي بالساعة: يخصم ساعات الإذن المسموح من دقائق المخالفة
      int deductAllowed(int actualMinutes, Attendance a) {
        if (!a.excused) return actualMinutes; // بدون إذن — يخصم كله
        final allowed = (a.excusedHours * 60).round();
        if (allowed <= 0) return 0; // بإذن بلا ساعات — لا خصم
        final r = actualMinutes - allowed;
        return r < 0 ? 0 : r;
      }
      for (final a in atts) {
        if (isLateAtt(a) && a.checkInTime != null) {
          final ci = a.checkInTime!.hour*60 + a.checkInTime!.minute;
          if (ci > gEnd) lateMin += deductAllowed(ci - gEnd, a);
        }
        if (a.checkOutTime != null && (!a.excused || a.excusedHours > 0)) {
          final co = a.checkOutTime!.hour*60 + a.checkOutTime!.minute;
          if (co < eMin) earlyMin += deductAllowed(eMin - co, a);
        }
      }
      // الحساب الحقيقي للخصم = ساعات × سعر الساعة × المضاعف
      final hourly = staff.hourlyRate ?? (staff.basicSalary / 30 / 8);
      final daily = staff.basicSalary / 30;
      final lateDed = lateMult > 0 ? (lateMin / 60.0) * hourly * lateMult : 0;
      final earlyDed = earlyMult > 0 ? (earlyMin / 60.0) * hourly * earlyMult : 0;
      final absentDed = absencePerDay > 0 ? p.absentDays * absencePerDay : p.absentDays * daily * absenceMult;
      payrollDetails[p.id] = {'lateMin': lateMin, 'earlyMin': earlyMin, 'lateDed': lateDed, 'earlyDed': earlyDed, 'absentDed': absentDed};
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBoldFont,
        ),
        build: (pw.Context context) {
          return [
            // العنوان الرئيسي
            pw.Center(
              child: pw.Text(
                _b('كشف حساب مرتب'),
                style: pw.TextStyle(
                  font: arabicBoldFont,
                  fontSize: 20,
                ),
              ),
            ),
            pw.SizedBox(height: 16),

            // بيانات الموظف
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _b('الاسم: ${staff.name}'),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _b('الكود: ${staff.staffId}'),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _b('الوظيفة: ${staff.position}'),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _b('المرتب الأساسي: ${staff.basicSalary.toStringAsFixed(2)} جنيه'),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // جدول السجلات
            pw.TableHelper.fromTextArray(
              headers: tableHeaders,
              data: tableData,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerStyle: pw.TextStyle(
                font: arabicBoldFont,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: pw.TextStyle(
                font: arabicFont,
                fontSize: 9,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
            ),
            pw.SizedBox(height: 12),
            // ملخص الإيرادات (وقت إضافي + بدلات)
            pw.Text(_b('الإيرادات'), style: pw.TextStyle(font: arabicBoldFont, fontSize: 12)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: [_b('البند'), _b('الكمية'), _b('المبلغ')],
              data: payrollRecords.expand((p) {
                final rows = <List<String>>[];
                if (p.overtimeHours > 0) {
                  rows.add([_b('وقت إضافي'), _b('${p.overtimeHours.toStringAsFixed(1)} س'), _b(p.overtimePay.toStringAsFixed(2))]);
                }
                if (p.allowances > 0) rows.add([_b('بدلات'), _b('-'), _b(p.allowances.toStringAsFixed(2))]);
                return rows;
              }).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerStyle: pw.TextStyle(font: arabicBoldFont, fontSize: 9),
              cellStyle: pw.TextStyle(font: arabicFont, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.center,
            ),
            pw.SizedBox(height: 12),
            // جدول تفصيلي للخصومات
            pw.Text(_b('تفاصيل الخصومات'), style: pw.TextStyle(font: arabicBoldFont, fontSize: 12)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: [_b('البند'), _b('الأيام/الساعات'), _b('المبلغ'), _b('السبب')],
              data: payrollRecords.expand((p) {
                final rows = <List<String>>[];
                final d = payrollDetails[p.id] ?? {'lateMin':0,'earlyMin':0,'lateDed':0.0,'earlyDed':0.0,'absentDed':0.0};
                final lateMin = d['lateMin'] as int;
                final earlyMin = d['earlyMin'] as int;
                final lateDed = (d['lateDed'] as double?) ?? p.penaltiesTotal;
                final earlyDed = (d['earlyDed'] as double?) ?? 0;
                final absentDed = (d['absentDed'] as double?) ?? p.absentDays * (p.basicSalary/30);
                if (p.absentDays > 0) rows.add([_b('غياب'), _b('${p.absentDays} يوم'), _b(absentDed.toStringAsFixed(2)), _b('غياب بدون إذن')]);
                if (lateMin > 0) {
                  final h = (lateMin/60).toStringAsFixed(1);
                  rows.add([_b('تأخير'), _b('${h} س'), _b(lateDed.toStringAsFixed(2)), _b('تأخير بعد السماح')]);
                }
                if (earlyMin > 0) {
                  final h = (earlyMin/60).toStringAsFixed(1);
                  rows.add([_b('انصراف مبكر'), _b('${h} س'), _b(earlyDed.toStringAsFixed(2)), _b('خروج قبل نهاية الدوام')]);
                }
                // أي جزاءات يدوية (مكافآت/جزاءات مسجلة من rewards_penalties) مش متغطاة بالتفاصيل أعلاه
                final covered = absentDed + lateDed + earlyDed;
                final remainder = (p.penaltiesTotal - covered);
                if ((p.penaltiesTotal > 0 || covered > 0) && remainder.abs() > 0.01) {
                  rows.add([_b('جزاءات / فرق'), _b('-'), _b(remainder.toStringAsFixed(2)), _b('جزاءات أخرى / تلقائية')]);
                }
                if (p.advances > 0) rows.add([_b('سلف'), _b('-'), _b(p.advances.toStringAsFixed(2)), _b('سلفة')]);
                if (rows.isEmpty) rows.add([_b('-'), _b('-'), _b('0.00'), _b('لا يوجد خصومات')]);
                return rows;
              }).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerStyle: pw.TextStyle(font: arabicBoldFont, fontSize: 9),
              cellStyle: pw.TextStyle(font: arabicFont, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.center,
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
}
