import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/payroll_display.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
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
    // prepare details for each payroll
    final Map<int, Map<String, dynamic>> details = {};
    for (final p in payrolls) {
      // الغياب من المخزن أولاً (يشمل ×mult والأسبوعي ÷6)
      details[p.id] = {
        'absentDed': PayrollDisplay.absenceDeduction(
          p,
          weekly: staffMap[p.staffId]?.payFrequency == 'weekly',
        ),
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
                        _b(
                          PayrollDisplay.absenceDeduction(
                            p,
                            weekly:
                                staffMap[p.staffId]?.payFrequency == 'weekly',
                          ).toStringAsFixed(0),
                        ),
                        _b(p.advances.toStringAsFixed(0)),
                        _b(p.permissionDeduction.toStringAsFixed(0)),
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
              'المعادلة: أساسي + إضافي×1.5 + انتظام - تأخير×1.5 - غياب - إذن×1.0 - سلف = إجمالي',
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
  /// C3: delegates to the ONE shared fold ([PayrollDisplay.totalsOf]) so
  /// single + batch obey identical rules by construction.
  static PayrollTotals computeVoucherTotals(List<Payroll> payrolls) =>
      PayrollDisplay.totalsOf(payrolls);

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
    final shown = payrolls.take(voucherMaxRows).toList();
    final hidden = payrolls.length - shown.length;

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
            pw.SizedBox(height: 8),
            // شريط المجاميع: أساسي | إضافات | خصومات | الصافي
            pw.Row(
              children: [
                for (final cell in [
                  ('الأساسي', t.basic, PdfColors.black),
                  ('إضافات', t.additions, PdfColors.teal900),
                  ('خصومات', t.deductions, PdfColors.red900),
                  ('الصافي (${payrolls.length})', t.net, PdfColors.green900),
                ])
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.symmetric(horizontal: 2),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: cell.$3,
                          width: cell.$1.startsWith('الصافي') ? 1.2 : 0.6,
                        ),
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                      padding: const pw.EdgeInsets.symmetric(vertical: 6),
                      child: pw.Column(
                        children: [
                          pw.Text(
                            _b(cell.$1),
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 8,
                              color: PdfColors.grey700,
                            ),
                          ),
                          pw.Text(
                            _b(cell.$2.toStringAsFixed(0)),
                            style: pw.TextStyle(
                              font: arabicBoldFont,
                              fontSize: 14,
                              color: cell.$3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 8),
            // جدول المشمولين: اسم/كود/صافي (مضغوط، بحد أقصى للصفحة الواحدة)
            pw.TableHelper.fromTextArray(
              headers: [_b('م'), _b('الاسم'), _b('الكود'), _b('الصافي')],
              data: [
                for (int i = 0; i < shown.length; i++)
                  [
                    _b('${i + 1}'),
                    _b(staffMap[shown[i].staffId]?.name ?? shown[i].staffId),
                    _b(shown[i].staffId),
                    _b(shown[i].netSalary.toStringAsFixed(0)),
                  ],
              ],
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
              headerStyle: pw.TextStyle(font: arabicBoldFont, fontSize: 8),
              cellStyle: pw.TextStyle(font: arabicFont, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              columnWidths: {
                0: const pw.FlexColumnWidth(0.6),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(1.6),
              },
            ),
            if (hidden > 0)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  _b('و $hidden موظف آخرون ضمن الإجمالي أعلاه'),
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
            pw.SizedBox(height: 6),
            pw.Text(
              _b(
                'مدفوع مسبقاً: $paidCount • ${paidTotal.toStringAsFixed(0)} | منتهون: $excludedCount • ${excludedTotal.toStringAsFixed(0)} | الصرف: $methodLabel',
              ),
              style: pw.TextStyle(
                font: arabicFont,
                fontSize: 8,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              _b(
                'عهدة/مستلم المبلغ للتوزيع: ........................................',
              ),
              style: pw.TextStyle(font: arabicFont, fontSize: 10),
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
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (f) async => pdf.save());
  }

  /// تقرير مجمع: 3 قسائم مرتب في ورقة A4 واحدة (توفير ورق + قص).
  /// نفس أعمدة التصميم الحالي مصغرة + كل قسيمة سليمة لوحدها
  /// (اسم/كود/فترة/تاريخ صرف/تاريخ إصدار/توقيعات) + خط قص بين القسائم.
  /// يعتمد على قيم Payroll المحفوظة (netSalary مصدر الحقيقة) بدون استعلامات
  /// حضور إضافية — الحساب التلقائي للناقص يتم قبل الاستدعاء من صفحة الدفعة.
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

    // C3: batch-slips footer uses the same shared fold as single + voucher.
    final totalNet = PayrollDisplay.totalsOf(payrolls).net;

    pw.Widget buildSlip(Payroll p) {
      final staff = staffMap[p.staffId];
      final name = staff?.name ?? p.staffId;
      final code = staff?.staffId ?? p.staffId;
      final paymentDateStr = p.paymentDate != null
          ? dateFormat.format(p.paymentDate!)
          : dateFormat.format(p.periodEnd);
      // غياب القسيمة: من المخزن أولاً (نفس معادلة الكشف الحالي)
      final absentDed = PayrollDisplay.absenceDeduction(
        p,
        weekly: staff?.payFrequency == 'weekly',
      );
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
            // رأس القسيمة: اسم + كود + صافي
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
            // نفس أعمدة التصميم الحالي (مصغرة لتناسب ثلث الصفحة)
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
                  _b(p.permissionDeduction.toStringAsFixed(0)),
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
            // توقيعات لكل قسيمة (لازمة بعد القص)
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
                _b('✂ قص هنا'),
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
              _b('كشف مرتبات مجمع - $period'),
              style: pw.TextStyle(font: arabicBoldFont, fontSize: 14),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              _b(
                'عدد الموظفين: ${payrolls.length} - إجمالي الصافي: ${totalNet.toStringAsFixed(0)} - إصدار: $issueDateStr',
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
          // ذيل المطبوع: إجمالي المطبوع + توقيعات عامة
          pw.SizedBox(height: 10),
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.green900, width: 1.2),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            child: pw.Column(
              children: [
                pw.Text(
                  _b('إجمالي المطبوع (${payrolls.length} موظف)'),
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  _b(totalNet.toStringAsFixed(0)),
                  style: pw.TextStyle(
                    font: arabicBoldFont,
                    fontSize: 26,
                    color: PdfColors.green900,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _b('المحاسب: ............  التوقيع: ............'),
                style: pw.TextStyle(font: arabicFont, fontSize: 9),
              ),
              pw.Text(
                _b('المدير: ............  التوقيع: ............'),
                style: pw.TextStyle(font: arabicFont, fontSize: 9),
              ),
              pw.Text(
                _b('المستلم: ............  التوقيع: ............'),
                style: pw.TextStyle(font: arabicFont, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (f) async => pdf.save());
  }

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
      final atts = await db.staffManagementDao.getAttendanceByStaff(
        staff.staffId,
        startDate: p.periodStart,
        endDate: p.periodEnd.add(const Duration(days: 1)),
      );
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
          if (s.settingKey == 'grace_period_minutes')
            grace = int.tryParse(s.settingValue) ?? 15;
          if (s.settingKey == 'late_penalty_per_hour')
            lateMult = double.tryParse(s.settingValue) ?? 0;
          if (s.settingKey == 'early_leave_penalty_per_hour')
            earlyMult = double.tryParse(s.settingValue) ?? 0;
          if (s.settingKey == 'absence_penalty_amount')
            absencePerDay = double.tryParse(s.settingValue) ?? 0;
          if (s.settingKey == 'absence_penalty_days_multiplier')
            absenceMult = double.tryParse(s.settingValue) ?? 1.0;
        }
      } catch (_) {}
      if (!staff.useDefaultSchedule) {
        if (staff.workScheduleStart != null &&
            staff.workScheduleStart!.isNotEmpty)
          workStart = staff.workScheduleStart!;
        if (staff.workScheduleEnd != null && staff.workScheduleEnd!.isNotEmpty)
          workEnd = staff.workScheduleEnd!;
      }
      int sMin = 9 * 60;
      int eMin = 17 * 60;
      try {
        final pa = workStart.split(':');
        sMin = (int.tryParse(pa[0]) ?? 9) * 60 + (int.tryParse(pa[1]) ?? 0);
      } catch (_) {}
      try {
        final pa = workEnd.split(':');
        eMin = (int.tryParse(pa[0]) ?? 17) * 60 + (int.tryParse(pa[1]) ?? 0);
      } catch (_) {}
      // (grace تنطبق داخل computeLateness — لا مقارنة يدوية هنا)
      int lateMin = 0;
      int earlyMin = 0;
      // C1: نفس المسار الوحيد — isLateAtt يطابق قاعدة العد المجمدة، والدقائق
      // من computeLateness (من بداية الدوام شاملاً السماح).
      bool isLateAtt(Attendance a) => isEffectiveLateDay(
        status: a.status,
        checkInTime: a.checkInTime,
        scheduleStartMinutes: sMin,
        graceMinutes: grace,
        excused: a.excused,
        excusedHours: a.excusedHours,
      );

      int lateExcusedMin = 0;
      int earlyExcusedMin = 0;
      for (final a in atts) {
        // C1: الدقائق من الدالة الوحيدة (تعيد 0 داخل السماح).
        lateMin += computeLateness(
          checkInTime: isLateAtt(a) ? a.checkInTime : null,
          scheduleStartMinutes: sMin,
          graceMinutes: grace,
        );
        if (a.excused && a.excusedHours > 0) {
          if (a.status == 'early_leave')
            earlyExcusedMin += (a.excusedHours * 60).round();
          else if (isLateAtt(a) || a.status == 'late')
            lateExcusedMin += (a.excusedHours * 60).round();
          else if (a.checkOutTime != null) {
            final co = a.checkOutTime!.hour * 60 + a.checkOutTime!.minute;
            if (co < eMin)
              earlyExcusedMin += (a.excusedHours * 60).round();
            else
              lateExcusedMin += (a.excusedHours * 60).round();
          } else
            lateExcusedMin += (a.excusedHours * 60).round();
        }
        if (a.checkOutTime != null) {
          final co = a.checkOutTime!.hour * 60 + a.checkOutTime!.minute;
          if (co < eMin) {
            if (a.excused && a.excusedHours <= 0) {
            } else {
              final actual = eMin - co;
              earlyMin += actual;
            }
          }
        }
      }
      // الإذن منفصل: lateMin×1.5 + إذن منفصل×1.0 (القاعدة الأسبوعية ÷6)
      final _sbase = PayrollDisplay.baseOf(staff);
      final hourly = staff.hourlyRate ?? (_sbase.base / _sbase.divisor / 8);
      final daily = _sbase.base / _sbase.divisor;
      final lateDed =
          (lateMin / 60.0) * hourly * (lateMult > 0 ? lateMult : 0) +
          (lateExcusedMin / 60.0) * hourly;
      final earlyDed =
          (earlyMin / 60.0) * hourly * (earlyMult > 0 ? earlyMult : 0) +
          (earlyExcusedMin / 60.0) * hourly;
      final lateExcusedDed = (lateExcusedMin / 60.0) * hourly;
      final earlyExcusedDed = (earlyExcusedMin / 60.0) * hourly;
      final absentDed = absencePerDay > 0
          ? p.absentDays * absencePerDay
          : p.absentDays * daily * absenceMult;
      payrollDetails[p.id] = {
        'lateMin': lateMin,
        'earlyMin': earlyMin,
        'lateExcusedMin': lateExcusedMin,
        'earlyExcusedMin': earlyExcusedMin,
        'lateDed': lateDed,
        'earlyDed': earlyDed,
        'lateExcusedDed': lateExcusedDed,
        'earlyExcusedDed': earlyExcusedDed,
        'absentDed': absentDed,
      };
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBoldFont),
        build: (pw.Context context) {
          // تصميم جديد حسب ورقة العميل: الإسم / المرتب الأساسي / إضافي / انتظام / تأخير / غياب / سلف / إذن / إجمالي
          return [
            pw.Center(
              child: pw.Text(
                _b('كشف المرتبات - ${payrollRecords.first.payrollPeriod}'),
                style: pw.TextStyle(font: arabicBoldFont, fontSize: 16),
              ),
            ),
            pw.SizedBox(height: 12),
            // جدول واحد مجمع لكل الموظفين بتصميم الورقة
            pw.TableHelper.fromTextArray(
              headers: [
                _b('الإسم'),
                _b('المرتب الأساسي'),
                _b('إضافي'),
                _b('انتظام'),
                _b('تأخير'),
                _b('غياب'),
                _b('سلف'),
                _b('إذن'),
                _b('إجمالي المرتب'),
              ],
              data: payrollRecords.map((p) {
                // الغياب من القيم المخزنة أولاً (تشمل ×mult) — إعادة الحساب
                // اللحظية بدون المضاعف كانت تعرض رقماً مخالفاً للمخزن.
                final d = payrollDetails[p.id];
                double absentDed =
                    p.deductions -
                    p.lateDeduction -
                    p.permissionDeduction -
                    p.advances -
                    p.penaltiesTotal;
                if (absentDed < 0) absentDed = 0;
                if (p.deductions == 0 && d != null) {
                  absentDed =
                      (d['absentDed'] as double?) ??
                      p.absentDays * (p.basicSalary / 30);
                }
                // لو payroll قديم و lateDeduction صفر، استخدم الحساب اللحظي
                double lateVal = p.lateDeduction;
                double permVal = p.permissionDeduction;
                if (lateVal == 0 && d != null)
                  lateVal = (d['lateDed'] as double?) ?? 0;
                if (permVal == 0 && d != null)
                  permVal =
                      (d['lateExcusedDed'] as double? ?? 0) +
                      (d['earlyExcusedDed'] as double? ?? 0);
                // انتظام = بونص
                final intz = p.bonus;
                return [
                  _b(staff.name),
                  _b(p.basicSalary.toStringAsFixed(0)),
                  _b(p.overtimePay.toStringAsFixed(0)),
                  _b(intz.toStringAsFixed(0)),
                  _b(lateVal.toStringAsFixed(0)),
                  _b(absentDed.toStringAsFixed(0)),
                  _b(p.advances.toStringAsFixed(0)),
                  _b(permVal.toStringAsFixed(0)),
                  _b(p.netSalary.toStringAsFixed(0)),
                ];
              }).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.7),
              headerStyle: pw.TextStyle(
                font: arabicBoldFont,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: pw.TextStyle(font: arabicFont, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
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
            pw.SizedBox(height: 8),
            pw.Text(
              _b(
                'المعادلة: أساسي + إضافي×1.5 + انتظام 200 (لو 0 غياب) - تأخير×1.5 - غياب×(أساسي÷30) - إذن×1.0 - سلف = إجمالي',
              ),
              style: pw.TextStyle(
                font: arabicFont,
                fontSize: 7,
                color: PdfColors.grey600,
              ),
            ),
            pw.SizedBox(height: 16),
            // توقيعات
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _b('توقيع المحاسب: ................'),
                  style: pw.TextStyle(font: arabicFont, fontSize: 9),
                ),
                pw.Text(
                  _b('توقيع المدير: ................'),
                  style: pw.TextStyle(font: arabicFont, fontSize: 9),
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
}
