import 'dart:io';
import 'package:excel/excel.dart';

// توليد قالب إكسل للاستيراد التاريخي للحضور
// البنية تطابق بالظبط ما يقرأه HistoricalAttendanceImportService.parseSheetRows:
//   - البارس يبدأ القراءة من صف index=2 (اللوب من i=2)
//   - الصفوف اللي أول خلية فيها "التاريخ" تُتجاهل
//   - البلوك الأيسر: col 0=التاريخ, 2=حضور, 3=انصراف
//   - البلوك الأيمن: col 7=التاريخ, 9=حضور, 10=انصراف
//   - التاريخ لازم يكون DateTime حقيقي (وليس رقم اليوم) عشان parseDateCell يقرأه صح
void main(List<String> args) {
  // الشهر الافتراضي = سبتمبر 2026 (مطابق لتقارير أغسطس/سبتمبر عند العميل)
  final year = args.isNotEmpty ? int.parse(args[0]) : 2026;
  final month = args.length > 1 ? int.parse(args[1]) : 9;

  final excel = Excel.createExcel();

  TextCellValue t(String s) => TextCellValue(s);
  DateTimeCellValue dt(DateTime d) => DateTimeCellValue.fromDateTime(d);

  // ورقة الإرشادات
  final instructions = excel['إرشادات'];
  instructions.appendRow([t('قالب استيراد الحضور التاريخي — أغسطس/سبتمبر 2026')]);
  instructions.appendRow([t('')]);
  instructions.appendRow([t('1. كل موظف = ورقة (Sheet) مستقلة، واسم الورقة لازم يطابق اسم الموظف في البرنامج بالظبط (نفس الحروف/التشكيل حتى الهمزة والتاء المربوطة).')]);
  instructions.appendRow([t('2. انسخ بيانات الورق بالظبط كما هي: كل يوم له سطر فيه حضور وانصراف.')]);
  instructions.appendRow([t('3. لتسجيل الحضور اكتب الوقت في خلية (حضور) وفي خلية (انصراف) بصيغة 08:05 أو 8:05.')]);
  instructions.appendRow([t('4. اليوم الغائب تماماً: اترك خليتي الحضور والانصراف فاضيتين (تُحسب تلقائياً غياب).')]);
  instructions.appendRow([t('5. الجمعة (إجازة) تُحسب تلقائياً إجازة حتى لو الخلايا فاضية — لا تحتاج كتابة.')]);
  instructions.appendRow([t('6. ساعات العمل تُحسب تلقائياً = (انصراف - حضور) ناقص ساعة الراحة (من إعدادات الدوام).')]);
  instructions.appendRow([t('7. لا تغيّر أعمدة القالب (0,2,3 | 7,9,10) — البارس يعتمد على هذه المواضع الثابتة.')]);
  instructions.appendRow([t('8. إن كانت ورقة الموظف فاتحة في البلوك الأيمن أيضاً اكتب فيها نفس الشيء، أو اتركه فاضي تماماً.')]);

  // ورقة موظف جاهزة (تعدّلها وتغيّر اسم الورقة لاسم الموظف الحقيقي)
  final sheet = excel['(اسم الموظف)'];
  // header — أول خلية تحتوي "التاريخ" فتُتجاهل، والصف الأول عموماً يُتجاهل (i=2)
  sheet.appendRow([t('التاريخ'), t(''), t('حضور'), t('انصراف'), t(''), t(''), t(''), t('التاريخ'), t(''), t('حضور'), t('انصراف')]);
  // صف فارغ ثاني (index 1) — البارس يبدأ من index 2 فنتأكد إن الأيام مبتدا من السطر الصحيح
  sheet.appendRow([t(''), t(''), t(''), t(''), t(''), t(''), t(''), t(''), t(''), t(''), t('')]);
  // الأيام 1..31 كتواريخ حقيقية
  final daysInMonth = DateTime(year, month + 1, 0).day;
  for (int d = 1; d <= daysInMonth; d++) {
    final date = DateTime(year, month, d);
    // عمود 0 = التاريخ (يسار)، عمود 7 = التاريخ (يمين)
    sheet.appendRow([dt(date), t(''), t(''), t(''), t(''), t(''), t(''), dt(date), t(''), t(''), t('')]);
  }

  final path = 'G:\\development\\POS-Offline-Desktop-main\\'
      'قالب_استيراد_الحضور_${year}-${month.toString().padLeft(2, '0')}.xlsx';
  final output = File(path);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(excel.encode()!);

  print('تم توليد القالب:');
  print(output.path);
  print('عدد الأوراق: ${excel.tables.length}');
  print('أيام الشهر: $daysInMonth');
}
