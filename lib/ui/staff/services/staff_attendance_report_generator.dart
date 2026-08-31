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
    int grace = 15;
    String workStartStr = '09:00';
    String workEndStr = '17:00';
    try {
      final rows = await db.select(db.attendanceSettings).get();
      for (final r in rows) {
        if (r.settingKey == 'late_penalty_per_hour') lateMult = double.tryParse(r.settingValue) ?? 0;
        if (r.settingKey == 'early_leave_penalty_per_hour') earlyMult = double.tryParse(r.settingValue) ?? 0;
        if (r.settingKey == 'absence_penalty_amount') absencePerDay = double.tryParse(r.settingValue) ?? 0;
        if (r.settingKey == 'grace_period_minutes') grace = int.tryParse(r.settingValue) ?? 15;
        if (r.settingKey == 'default_work_start') workStartStr = r.settingValue;
        if (r.settingKey == 'default_work_end') workEndStr = r.settingValue;
      }
    } catch (_) {}
    final hourly = staff.hourlyRate ?? (staff.basicSalary / 160.0);

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

    // إحصائيات
    int absent = records.where((r) => r.status == 'absent').length;
    int lateCount = records.where((r) => r.status == 'late').length;
    int totalLateMin = 0;
    int totalEarlyMin = 0;
    for (final r in records) {
      if (r.status == 'late' && r.checkInTime != null) {
        final ci = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
        if (ci > graceEnd) totalLateMin += ci - graceEnd;
      }
      if (r.checkOutTime != null) {
        final co = r.checkOutTime!.hour * 60 + r.checkOutTime!.minute;
        if (co < endMin) totalEarlyMin += endMin - co;
      }
    }
    double totalLateHours = totalLateMin / 60.0;
    double totalEarlyHours = totalEarlyMin / 60.0;
    double lateDeduction = lateMult > 0 ? totalLateHours * hourly * lateMult : 0;
    double earlyDeduction = earlyMult > 0 ? totalEarlyHours * hourly * earlyMult : 0;
    double absenceDeduction = absent * absencePerDay;
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
      String statusA = r.status;
      switch (r.status) {
        case 'present': statusA = 'حاضر'; break;
        case 'absent': statusA = 'غائب'; break;
        case 'late': statusA = 'متأخر'; break;
        case 'leave': statusA = 'إجازة'; break;
      }
      int lateMin = 0;
      if (r.status == 'late' && r.checkInTime != null) {
        final ci = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
        if (ci > graceEnd) lateMin = ci - graceEnd;
      }
      final lateStr = lateMin > 0 ? '${lateMin ~/ 60}س ${lateMin % 60}د' : '-';
      double rowDeduction = 0;
      if (r.status == 'late' && lateMin > 0 && lateMult > 0) rowDeduction = (lateMin / 60.0) * hourly * lateMult;
      if (r.status == 'absent' && absencePerDay > 0) rowDeduction = absencePerDay;
      // انصراف مبكر
      if (r.checkOutTime != null) {
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBoldFont),
        build: (ctx) => [
          pw.Center(child: pw.Text(title, style: pw.TextStyle(font: arabicBoldFont, fontSize: 18))),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: staffInfo.map((s) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 2), child: pw.Text(s, style: pw.TextStyle(font: arabicFont, fontSize: 10)))).toList()),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            headerStyle: pw.TextStyle(font: arabicBoldFont, fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: pw.TextStyle(font: arabicFont, fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.center,
            headerAlignment: pw.Alignment.center,
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(_b('الملخص'), style: pw.TextStyle(font: arabicBoldFont, fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Text(_b('إجمالي ساعات العمل: ${totalHours.toStringAsFixed(1)} ساعة'), style: pw.TextStyle(font: arabicFont, fontSize: 10)),
              pw.Text(_b('إجمالي التأخير: ${totalLateMin ~/ 60}س ${totalLateMin % 60}د ($lateCount يوم متأخر)'), style: pw.TextStyle(font: arabicFont, fontSize: 10)),
              pw.Text(_b('إجمالي الانصراف المبكر: ${totalEarlyMin ~/ 60}س ${totalEarlyMin % 60}د'), style: pw.TextStyle(font: arabicFont, fontSize: 10)),
              pw.Text(_b('أيام الغياب: $absent يوم'), style: pw.TextStyle(font: arabicFont, fontSize: 10)),
              pw.Divider(),
              pw.Text(_b('إجمالي الخصومات التقديرية: ${totalDeduction.toStringAsFixed(2)} ج.م (تأخير: ${lateDeduction.toStringAsFixed(2)} + بدري: ${earlyDeduction.toStringAsFixed(2)} + غياب: ${absenceDeduction.toStringAsFixed(2)})'), style: pw.TextStyle(font: arabicBoldFont, fontSize: 11)),
            ]),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (f) async => pdf.save());
  }
}
