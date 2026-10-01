import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/utils/pdf_bidi_helper.dart';

/// Restored batch payroll printing (old batch slips page):
/// - generateAndPrintAll: كشف إجمالي بكل الموظفين + الإجمالي
/// - generateAndPrintBatchSlips: 3 قسائم في ورقة A4 مع خط قص وتوقيعات
/// Reads only stored Payroll values (netSalary is the source of truth).
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

  static bool _isWeekly(Staff? staff) =>
      staff?.employmentType == 'weekly';

  /// Permission / early-leave share, read from the FIRST-CLASS payroll column
  /// written by `StaffManagementService.calculatePayroll`.
  ///
  /// v72: this used to read `otherDeductions`, a legacy catch-all column. The
  /// service no longer writes permission into it, so the PDF statement showed
  /// 0 for the permission line and pushed the amount onto the absence line.
  ///
  /// The `otherDeductions` fallback only applies to slips calculated before the
  /// v72 migration, where the first-class columns are still zero. `otherDeductions`
  /// is never written with permission again.
  static double _permissionDeductionOf(Payroll p) {
    if (p.permissionDeduction > 0) return p.permissionDeduction;
    return p.otherDeductions > 0 ? p.otherDeductions : 0.0;
  }

  /// Absence share folded into the aggregate deductions.
  ///
  /// The permission share is subtracted from its own column so it can no longer
  /// fall into this residual and be printed as an absence amount.
  static double _absenceDeduction(Payroll p, {required bool weekly}) {
    var absentDed = p.deductions -
        p.lateDeduction -
        p.advances -
        p.penaltiesTotal -
        _permissionDeductionOf(p);
    if (absentDed < 0) absentDed = 0;
    if (p.deductions == 0 && p.absentDays > 0) {
      absentDed = p.absentDays * (p.basicSalary / (weekly ? 6 : 30));
    }
    return absentDed;
  }

  static Future<void> generateAndPrintAll({
    required BuildContext context,
    required AppDatabase db,
    required List<Payroll> payrolls,
    required Map<String, Staff> staffMap,
    required String period,
  }) async {
    final fonts = await _loadFonts();
    final arabicFont = fonts['arabic'];
    final arabicBoldFont = fonts['arabicBold'];
    final pdf = pw.Document();

    double totalNet = 0;
    final Map<int, Map<String, double>> details = {};
    for (final p in payrolls) {
      totalNet += p.netSalary;
      details[p.id] = {
        'absentDed': _absenceDeduction(
          p,
          weekly: _isWeekly(staffMap[p.staffId]),
        ),
        'permDed': _permissionDeductionOf(p),
      };
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(8),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBoldFont),
        build: (pw.Context ctx) => [
          pw.Center(
            child: pw.Text(
              _b('كشف حساب كلي - $period'),
              style: pw.TextStyle(font: arabicBoldFont, fontSize: 14),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              _b(
                'عدد الموظفين: ${payrolls.length} - إجمالي الصافي: ${totalNet.toStringAsFixed(0)}',
              ),
              style: pw.TextStyle(
                font: arabicFont,
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          for (final p in payrolls)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        _b(staffMap[p.staffId]?.name ?? p.staffId),
                        style: pw.TextStyle(font: arabicBoldFont, fontSize: 9),
                      ),
                      pw.Text(
                        _b('صافي: ${p.netSalary.toStringAsFixed(0)}'),
                        style: pw.TextStyle(
                          font: arabicBoldFont,
                          fontSize: 9,
                          color: PdfColors.green900,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.TableHelper.fromTextArray(
                    headers: [
                      _b('أساسي'),
                      _b('إضافي'),
                      _b('انتظام'),
                      _b('تأخير'),
                      _b('غياب'),
                      _b('سلف'),
                      _b('إذن'),
                      _b('إجمالي'),
                    ],
                    data: [
                      [
                        _b(p.basicSalary.toStringAsFixed(0)),
                        _b(p.overtimePay.toStringAsFixed(0)),
                        _b(p.bonus.toStringAsFixed(0)),
                        _b(p.lateDeduction.toStringAsFixed(0)),
                        _b((details[p.id]!['absentDed']!).toStringAsFixed(0)),
                        _b(p.advances.toStringAsFixed(0)),
                        _b((details[p.id]!['permDed']!).toStringAsFixed(0)),
                        _b(p.netSalary.toStringAsFixed(0)),
                      ],
                    ],
                    border: pw.TableBorder.all(
                      color: PdfColors.grey300,
                      width: 0.4,
                    ),
                    headerStyle: pw.TextStyle(
                      font: arabicBoldFont,
                      fontSize: 7,
                    ),
                    cellStyle: pw.TextStyle(font: arabicFont, fontSize: 7),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    cellAlignment: pw.Alignment.center,
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 8),
          pw.Text(
            _b(
              'المعادلة: أساسي + إضافي + انتظام - تأخير - غياب - إذن - سلف = إجمالي',
            ),
            style: pw.TextStyle(
              font: arabicFont,
              fontSize: 7,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (f) async => pdf.save());
  }

  /// مجاميع شريط الوثيقة من قيم Payroll المحفوظة (مصدر الحقيقة):
  /// أساسي + إضافات (إضافي/انتظام/بدلات/مكافآت) - خصومات (المخزنة) = صافي.
  static ({double basic, double additions, double deductions, double net})
  computeVoucherTotals(List<Payroll> payrolls) {
    double basic = 0, additions = 0, deductions = 0, net = 0;
    for (final p in payrolls) {
      basic += p.basicSalary;
      additions += p.overtimePay + p.bonus + p.allowances + p.rewardsTotal;
      deductions += p.deductions;
      net += p.netSalary;
    }
    return (
      basic: basic,
      additions: additions,
      deductions: deductions,
      net: net,
    );
  }

  /// مستند صرف رسمي: صفحة A4 واحدة مضمونة — ترويسة + شريط مجاميع +
  /// جدول (اسم/كود/صافي) + سطر استبعاد + الطريقة/المستلم + 3 توقيعات.
  /// الجدول يُعرض أول 22 اسماً فقط مع سطر 「و N آخرون」 عند التجاوز
  /// (المجاميع دائماً على الكل) — لضمان عدم تجاوز صفحة واحدة أياً كان العدد.
  static const int voucherMaxRows = 22;

  static Future<void> generateAndPrintBatchVoucher({
    required BuildContext context,
    required AppDatabase db,
    required String period,
    required String voucherNo,
    required List<Payroll> payrolls,
    required Map<String, Staff> staffMap,
    required int paidCount,
    required double paidTotal,
    required int excludedCount,
    required double excludedTotal,
    required String methodLabel,
  }) async {
    final fonts = await _loadFonts();
    final arabicFont = fonts['arabic'];
    final arabicBoldFont = fonts['arabicBold'];
    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');
    final issueDateStr = dateFormat.format(DateTime.now());
    final t = computeVoucherTotals(payrolls);

    pw.Widget signatureBox(String role) {
      return pw.Container(
        width: 150,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey500, width: 0.6),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        padding: const pw.EdgeInsets.all(8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _b(role),
              style: pw.TextStyle(font: arabicBoldFont, fontSize: 10),
            ),
            pw.SizedBox(height: 14),
            pw.Text(
              _b('الاسم: ....................'),
              style: pw.TextStyle(font: arabicFont, fontSize: 8),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              _b('التوقيع: ....................'),
              style: pw.TextStyle(font: arabicFont, fontSize: 8),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              _b('التاريخ: .... / .... / ....'),
              style: pw.TextStyle(font: arabicFont, fontSize: 8),
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBoldFont),
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                _b('مستند صرف مرتبات'),
                style: pw.TextStyle(font: arabicBoldFont, fontSize: 20),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _b('رقم المستند: $voucherNo'),
                  style: pw.TextStyle(font: arabicBoldFont, fontSize: 11),
                ),
                pw.Text(
                  _b('تاريخ الإصدار: $issueDateStr'),
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              _b('الفترة: $period'),
              style: pw.TextStyle(font: arabicBoldFont, fontSize: 13),
            ),
            pw.SizedBox(height: 16),
            // مربع الإجمالي الصافي فقط
            pw.Center(
              child: pw.Container(
                width: 280,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColors.green900,
                    width: 1.5,
                  ),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                  color: PdfColors.green50,
                ),
                padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                child: pw.Column(
                  children: [
                    pw.Text(
                      _b('إجمالي (${payrolls.length} مرتب)'),
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 12,
                        color: PdfColors.grey800,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      _b(t.net.toStringAsFixed(0)),
                      style: pw.TextStyle(
                        font: arabicBoldFont,
                        fontSize: 28,
                        color: PdfColors.green900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _b(
                      'طريقة الصرف: $methodLabel',
                    ),
                    style: pw.TextStyle(
                      font: arabicBoldFont,
                      fontSize: 10,
                      color: PdfColors.grey800,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    _b(
                      'عهدة/مستلم المبلغ للتوزيع: ........................................',
                    ),
                    style: pw.TextStyle(font: arabicFont, fontSize: 10),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    _b(
                      'ملاحظات: ........................................................................................................',
                    ),
                    style: pw.TextStyle(font: arabicFont, fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                signatureBox('أعدّه (المحاسب)'),
                signatureBox('اعتمده (المدير)'),
                signatureBox('استلم المبلغ (الموزع)'),
              ],
            ),
            pw.SizedBox(height: 16),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (f) async => pdf.save());
  }

  /// قسيمة مرتب فردية لموظف واحد
  static Future<void> generateAndPrintSingleSlip({
    required BuildContext context,
    required AppDatabase db,
    required Payroll payroll,
    required Staff staff,
  }) async {
    await generateAndPrintBatchSlips(
      context: context,
      db: db,
      payrolls: [payroll],
      staffMap: {staff.staffId: staff},
      period: payroll.payrollPeriod,
    );
  }

  /// 3 قسائم مرتب في ورقة A4 واحدة (توفير ورق + قص).
  /// كل قسيمة سليمة لوحدها (اسم/كود/فترة/تواريخ/توقيعات) + خط قص بين القسائم.
  static Future<void> generateAndPrintBatchSlips({
    required BuildContext context,
    required AppDatabase db,
    required List<Payroll> payrolls,
    required Map<String, Staff> staffMap,
    required String period,
  }) async {
    final fonts = await _loadFonts();
    final arabicFont = fonts['arabic'];
    final arabicBoldFont = fonts['arabicBold'];
    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');
    final issueDateStr = dateFormat.format(DateTime.now());

    double totalNet = 0;
    for (final p in payrolls) {
      totalNet += p.netSalary;
    }
    final Map<int, Map<String, double>> details = {};
    for (final p in payrolls) {
      details[p.id] = {
        'absentDed': _absenceDeduction(
          p,
          weekly: _isWeekly(staffMap[p.staffId]),
        ),
        'permDed': _permissionDeductionOf(p),
      };
    }

    pw.Widget buildSlip(Payroll p) {
      final staff = staffMap[p.staffId];
      final name = staff?.name ?? p.staffId;
      final code = staff?.staffId ?? p.staffId;
      final paymentDateStr = p.paymentDate != null
          ? dateFormat.format(p.paymentDate!)
          : dateFormat.format(p.periodEnd);
      final absentDed = details[p.id]!['absentDed']!;
      final permDed = details[p.id]!['permDed']!;
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 4),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey600, width: 0.7),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        padding: const pw.EdgeInsets.all(6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _b(name),
                      style: pw.TextStyle(font: arabicBoldFont, fontSize: 10),
                    ),
                    pw.Text(
                      _b('كود: $code'),
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 7,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      _b('صافي: ${p.netSalary.toStringAsFixed(0)}'),
                      style: pw.TextStyle(
                        font: arabicBoldFont,
                        fontSize: 11,
                        color: PdfColors.green900,
                      ),
                    ),
                    pw.Text(
                      _b('الفترة: $period'),
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 7,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _b('صرف: $paymentDateStr'),
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 7,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  _b('إصدار: $issueDateStr'),
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 7,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: [
                _b('الإسم'),
                _b('الأساسي'),
                _b('إضافي'),
                _b('انتظام'),
                _b('تأخير'),
                _b('غياب'),
                _b('سلف'),
                _b('إذن'),
                _b('إجمالي'),
              ],
              data: [
                [
                  _b(name),
                  _b(p.basicSalary.toStringAsFixed(0)),
                  _b(p.overtimePay.toStringAsFixed(0)),
                  _b(p.bonus.toStringAsFixed(0)),
                  _b(p.lateDeduction.toStringAsFixed(0)),
                  _b(absentDed.toStringAsFixed(0)),
                  _b(p.advances.toStringAsFixed(0)),
                  _b(permDed.toStringAsFixed(0)),
                  _b(p.netSalary.toStringAsFixed(0)),
                ],
              ],
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerStyle: pw.TextStyle(font: arabicBoldFont, fontSize: 7),
              cellStyle: pw.TextStyle(font: arabicFont, fontSize: 7),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1.4),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1),
                5: const pw.FlexColumnWidth(1),
                6: const pw.FlexColumnWidth(1),
                7: const pw.FlexColumnWidth(1),
                8: const pw.FlexColumnWidth(1.5),
              },
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              _b('أساسي + إضافي + انتظام - تأخير - غياب - إذن - سلف = إجمالي'),
              style: pw.TextStyle(
                font: arabicFont,
                fontSize: 6,
                color: PdfColors.grey600,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _b('المحاسب: ............'),
                  style: pw.TextStyle(font: arabicFont, fontSize: 7),
                ),
                pw.Text(
                  _b('المدير: ............'),
                  style: pw.TextStyle(font: arabicFont, fontSize: 7),
                ),
                pw.Text(
                  _b('الموظف: ............'),
                  style: pw.TextStyle(font: arabicFont, fontSize: 7),
                ),
              ],
            ),
          ],
        ),
      );
    }

    pw.Widget buildCutLine() {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Divider(color: PdfColors.grey400, thickness: 0.5),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6),
              child: pw.Text(
                _b('قص هنا'),
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 7,
                  color: PdfColors.grey600,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Divider(color: PdfColors.grey400, thickness: 0.5),
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(8),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBoldFont),
        header: (pw.Context ctx) {
          if (ctx.pageNumber > 1) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Center(
                child: pw.Text(
                  _b('كشف مرتبات مجمع - $period'),
                  style: pw.TextStyle(font: arabicBoldFont, fontSize: 9),
                ),
              ),
            );
          }
          return pw.SizedBox();
        },
        footer: (pw.Context ctx) => pw.Center(
          child: pw.Text(
            _b('صفحة ${ctx.pageNumber} / ${ctx.pagesCount}'),
            style: pw.TextStyle(
              font: arabicFont,
              fontSize: 7,
              color: PdfColors.grey600,
            ),
          ),
        ),
        build: (pw.Context ctx) => [
          pw.Center(
            child: pw.Text(
              _b(payrolls.length == 1 ? 'قسيمة راتب - $period' : 'كشف مرتبات مجمع - $period'),
              style: pw.TextStyle(font: arabicBoldFont, fontSize: 14),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              _b(
                payrolls.length == 1
                    ? 'الموظف: ${staffMap[payrolls.first.staffId]?.name ?? payrolls.first.staffId} - الصافي: ${totalNet.toStringAsFixed(0)} - إصدار: $issueDateStr'
                    : 'عدد الموظفين: ${payrolls.length} - إجمالي الصافي: ${totalNet.toStringAsFixed(0)} - إصدار: $issueDateStr',
              ),
              style: pw.TextStyle(
                font: arabicFont,
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          for (int i = 0; i < payrolls.length; i++) ...[
            buildSlip(payrolls[i]),
            if (i != payrolls.length - 1) buildCutLine(),
          ],
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (f) async => pdf.save());
  }
}
