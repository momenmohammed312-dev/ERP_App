import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/utils/pdf_bidi_helper.dart';

class StaffAttendanceReportGenerator {
  static Future<Map<String, pw.Font?>> _loadFonts() async {
    pw.Font? arabicFont;
    pw.Font? arabicBoldFont;
    final latinFont = pw.Font.helvetica();
    try {
      final regularFontData = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      if (regularFontData.lengthInBytes > 100) arabicFont = pw.Font.ttf(regularFontData);
    } catch (_) {}
    try {
      final boldFontData = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      if (boldFontData.lengthInBytes > 100) arabicBoldFont = pw.Font.ttf(boldFontData);
    } catch (_) {}
    arabicFont ??= latinFont;
    arabicBoldFont ??= latinFont;
    return {'arabic': arabicFont, 'arabicBold': arabicBoldFont, 'latin': latinFont};
  }

  static String _b(String text) => PdfBidiHelper.reorder(text);

  static String _fmtTime(DateTime? dt) => dt == null ? '-' : DateFormat('HH:mm').format(dt);
  static String _fmtDate(DateTime dt) => DateFormat('yyyy/MM/dd').format(dt);

  static Future<void> generateAndPrint({
    required AppDatabase db,
    required Staff staff,
    required List<Attendance> records,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final fonts = await _loadFonts();
    final arabicFont = fonts['arabic'];
    final arabicBoldFont = fonts['arabicBold'];

    // قراءة الإعدادات للحساب التقديري للخصم (مضاعفات أجر الساعة)
    double lateMult = 0;
    double earlyMult = 0;
    double absencePerDay = 0;
    double absenceMultiplier = 1.0;
    int grace = 15;
    String workStartStr = '08:00';
    String workEndStr = '17:00';
    try {
      final rows = await db.select(db.attendanceSettings).get();
      for (final r in rows) {
        if (r.settingKey == 'late_penalty_per_hour') lateMult = double.tryParse(r.settingValue) ?? 0;
        if (r.settingKey == 'early_leave_penalty_per_hour') earlyMult = double.tryParse(r.settingValue) ?? 0;
        if (r.settingKey == 'absence_penalty_amount') absencePerDay = double.tryParse(r.settingValue) ?? 0;
        if (r.settingKey == 'absence_penalty_days_multiplier') absenceMultiplier = double.tryParse(r.settingValue) ?? 1.0;
        if (r.settingKey == 'grace_period_minutes') grace = int.tryParse(r.settingValue) ?? 15;
        if (r.settingKey == 'default_work_start') workStartStr = r.settingValue;
        if (r.settingKey == 'default_work_end') workEndStr = r.settingValue;
      }
    } catch (_) {}
if (!staff.useDefaultSchedule) {
      if (staff.workScheduleStart != null && staff.workScheduleStart!.isNotEmpty) workStartStr = staff.workScheduleStart!;
      if (staff.workScheduleEnd != null && staff.workScheduleEnd!.isNotEmpty) workEndStr = staff.workScheduleEnd!;
    }
        final hourly = staff.hourlyRate ?? (staff.basicSalary / 30 / 8);

    // احتساب دقائق التأخير لكل سجل للتقرير
    int parseStartMin(String s) {
      final p = s.split(':');
      return (int.tryParse(p[0]) ?? 9) * 60 + (int.tryParse(p[1]) ?? 0);
    }
    final startMin = parseStartMin(workStartStr);
    final endMin = parseStartMin(workEndStr);
    final graceEnd = startMin + grace;

    final pdf = pw.Document();
    final title = _b('كشف الحضور والغياب والخصومات');
    final staffInfo = [
      _b('الاسم: ${staff.name}'),
      _b('الكود: ${staff.staffId}'),
      _b('الوظيفة: ${staff.position}'),
      _b('الفترة: ${startDate != null ? _fmtDate(startDate) : '-'} - ${endDate != null ? _fmtDate(endDate) : _fmtDate(DateTime.now())}'),
    ];

    // إحصائيات — مع حساب دفاعي: present بعد السماح يُعتبر late
    // السجلات بإذن (excused) لا تحتسب في التأخير/الخصم — مع خصم تناسبي بالساعة (excusedHours)
    bool isLateEff(Attendance r) {
      if (r.excused && r.excusedHours <= 0) return false;
      if (r.status == 'late') return true;
      if (r.status == 'present' && r.checkInTime != null) {
        final ci = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
        return ci > graceEnd;
      }
      return false;
    }
    // يخصم ساعات الإذن المسموح من دقائق المخالفة (الفرق فوق المسموح فقط يُخصم)
    int deductAllowed(int actualMinutes, Attendance r) {
      if (!r.excused) return actualMinutes; // بدون إذن — يخصم كله
      final allowed = (r.excusedHours * 60).round();
      if (allowed <= 0) return 0; // بإذن بلا ساعات — لا خصم
      final res = actualMinutes - allowed;
      return res < 0 ? 0 : res;
    }
    int absent = records.where((r) => r.status == 'absent').length;
    int lateCount = records.where(isLateEff).length;
    int totalLateMin = 0;
    int totalEarlyMin = 0;
    for (final r in records) {
      if (isLateEff(r) && r.checkInTime != null) {
        final ci = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
        if (ci > graceEnd) totalLateMin += deductAllowed(ci - graceEnd, r);
      }
      if (r.checkOutTime != null && (!r.excused || r.excusedHours > 0)) {
        final co = r.checkOutTime!.hour * 60 + r.checkOutTime!.minute;
        if (co < endMin) totalEarlyMin += deductAllowed(endMin - co, r);
      }
    }
    double totalLateHours = totalLateMin / 60.0;
    double totalEarlyHours = totalEarlyMin / 60.0;
    double lateDeduction = 0;
    if (lateMult > 0) {
      lateDeduction = totalLateHours * hourly * lateMult;
    } else {
      try {
        final r = await (db.select(db.attendanceSettings)..where((t) => t.settingKey.equals('late_penalty_amount'))).getSingleOrNull();
        final amt = double.tryParse(r?.settingValue ?? '0') ?? 0;
        if (amt > 0) lateDeduction = lateCount * amt;
      } catch (_) {}
    }
    double earlyDeduction = earlyMult > 0 ? totalEarlyHours * hourly * earlyMult : 0;
    double absenceDeduction = absencePerDay > 0 ? absent * absencePerDay * absenceMultiplier : absent * (staff.basicSalary / 30) * absenceMultiplier;
    double totalDeduction = lateDeduction + earlyDeduction + absenceDeduction;
    double totalHours = records.fold(0.0, (s, r) => s + (r.workingHours ?? 0));

    final headers = [
      _b('التاريخ'),
      _b('حضور / انصراف'),
      _b('الحالة'),
      _b('التأخير'),
      _b('الخصم'),
      _b('ملاحظات'),
    ];

    final data = records.map((r) {
      final effLate = isLateEff(r);
      String statusA = r.status;
      if (effLate && r.status == 'present') statusA = 'late';
      if (r.excused) statusA = r.status == 'early_leave' ? 'excused_early' : 'excused_late';
      switch (statusA) {
        case 'present': statusA = 'حاضر'; break;
        case 'absent': statusA = 'غائب'; break;
        case 'late': statusA = 'متأخر'; break;
        case 'leave': statusA = 'إجازة'; break;
        case 'excused_late': statusA = 'متأخر بإذن'; break;
        case 'excused_early': statusA = 'انصراف بإذن'; break;
      }
      int lateMin = 0;
      if (effLate && r.checkInTime != null) {
        final ci = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
        if (ci > graceEnd) lateMin = ci - graceEnd;
      }
      final lateStr = lateMin > 0 ? '${lateMin ~/ 60}س ${lateMin % 60}د' : '-';
      double rowDeduction = 0;
      if (effLate && lateMin > 0 && lateMult > 0) rowDeduction = (lateMin / 60.0) * hourly * lateMult;
      if (r.status == 'absent' && absencePerDay > 0) rowDeduction = absencePerDay;
      // انصراف مبكر
      if (r.checkOutTime != null && !r.excused) {
        final co = r.checkOutTime!.hour * 60 + r.checkOutTime!.minute;
        if (co < endMin && earlyMult > 0) {
          final earlyMin = endMin - co;
          rowDeduction += (earlyMin / 60.0) * hourly * earlyMult;
        }
      }
      final dedStr = rowDeduction > 0 ? rowDeduction.toStringAsFixed(2) : '-';
      final timeStr = '${_fmtTime(r.checkInTime)} / ${_fmtTime(r.checkOutTime)}';
      return [
        _b(_fmtDate(r.date)),
        _b(timeStr),
        _b(statusA),
        _b(lateStr),
        _b(dedStr),
        _b(r.notes ?? r.overrideReason ?? '-'),
      ];
    }).toList();

    pw.Widget _employeeBlock(Staff s, List<Attendance> recs) {
      final empAbsent = recs.where((r) => r.status == 'absent').length;
      final empLateCount = recs.where(isLateEff).length;
      int empLateMin = 0; for (final r in recs) if (isLateEff(r) && r.checkInTime != null) { final ci = r.checkInTime!.hour*60+r.checkInTime!.minute; if (ci>graceEnd) empLateMin += ci-graceEnd; }
      final empOvertime = recs.fold(0.0, (a,r)=>a+(r.overtimeHours));
      final empLateHours = empLateMin / 60.0;
      return pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
        padding: const pw.EdgeInsets.all(6),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Container(color: PdfColors.grey300, padding: const pw.EdgeInsets.all(4), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(_b(s.name), style: pw.TextStyle(font: arabicBoldFont, fontSize: 9)), pw.Text(_b(s.staffId), style: pw.TextStyle(font: arabicFont, fontSize: 8))]),),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: [_b('التاريخ'), _b('حضور'), _b('انصراف'), _b('الحالة')],
            data: recs.map((r) { final eff = isLateEff(r) && r.status=='present' ? 'late' : r.status; final effTxt = r.excused ? (eff=='early_leave'?'انصراف بإذن':'متأخر بإذن') : (eff=='present'?'حاضر':eff=='absent'?'غائب':eff=='late'?'متأخر':eff=='leave'?'إجازة':'إجازة'); return [_b(_fmtDate(r.date)), _b(_fmtTime(r.checkInTime)), _b(_fmtTime(r.checkOutTime)), _b(effTxt)]; }).toList(),
            headerStyle: pw.TextStyle(font: arabicBoldFont, fontSize: 7), cellStyle: pw.TextStyle(font: arabicFont, fontSize: 7),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.3), headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.center,
          ),
          pw.SizedBox(height: 4),
          pw.Text(_b('المرتب: ${s.basicSalary.toStringAsFixed(0)} | اضافي:${empOvertime.toStringAsFixed(1)}س تأخير:${empLateHours.toStringAsFixed(1)}س ($empLateCount) غياب:${empAbsent}'), style: pw.TextStyle(font: arabicFont, fontSize: 7)),
        ]),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBoldFont),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.Column(children: [
                pw.Center(child: pw.Text(title, style: pw.TextStyle(font: arabicBoldFont, fontSize: 14))),
                pw.SizedBox(height: 6),
                pw.Text(_b('الفترة: ${startDate != null ? _fmtDate(startDate) : '-'} - ${endDate != null ? _fmtDate(endDate) : _fmtDate(DateTime.now())}'), style: pw.TextStyle(font: arabicFont, fontSize: 8)),
                pw.Text(_b('الموظف: ${staff.name} (${staff.staffId}) — المرتب: ${staff.basicSalary.toStringAsFixed(0)}'), style: pw.TextStyle(font: arabicFont, fontSize: 8)),
                pw.SizedBox(height: 8),
              ])
            : pw.SizedBox.shrink(),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(_b('إجمالي الخصومات: ${totalDeduction.toStringAsFixed(2)} ج.م (تأخير ${lateDeduction.toStringAsFixed(2)} + بدري ${earlyDeduction.toStringAsFixed(2)} + غياب ${absenceDeduction.toStringAsFixed(2)}) | ساعات: ${totalHours.toStringAsFixed(1)}'), style: pw.TextStyle(font: arabicFont, fontSize: 7)),
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headers: [_b('التاريخ'), _b('حضور'), _b('انصراف'), _b('الحالة'), _b('إضافي'), _b('تأخير'), _b('غياب'), _b('إذن')],
            data: records.map((r) {
              final effLate = isLateEff(r);
              final extra = (r.overtimeHours).toStringAsFixed(1);
              final late = effLate ? '${(r.checkInTime != null ? (r.checkInTime!.hour*60+r.checkInTime!.minute - graceEnd) : 0) ~/60}س' : '-';
              final eff = r.status=='present' && effLate ? 'late' : r.status;
              final effTxt = r.excused ? (eff=='early_leave'?'انصراف بإذن':'متأخر بإذن') : (eff=='present'?'حاضر':eff=='absent'?'غائب':eff=='late'?'متأخر':'إجازة');
              return [_b(_fmtDate(r.date)), _b(_fmtTime(r.checkInTime)), _b(_fmtTime(r.checkOutTime)), _b(effTxt), _b(extra), _b(late), _b(eff=='absent'?'1':''), _b(eff=='leave'||r.excused?'✓':'')];
            }).toList(),
            headerStyle: pw.TextStyle(font: arabicBoldFont, fontSize: 7), cellStyle: pw.TextStyle(font: arabicFont, fontSize: 7),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.3), headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.center,
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (f) async => pdf.save());
  }
}
