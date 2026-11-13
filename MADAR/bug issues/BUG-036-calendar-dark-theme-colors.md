# BUG-036 — ألوان التقويم غير متوافقة مع Dark Theme

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-036 |
| **العنوان** | ألوان التقويم غير متوافقة مع Dark Theme |
| **النوع** | Defect / UI & Accessibility |
| **الأولوية** | P2 عالية |
| **الحالة** | resolved |
| **الأبلغ** | صاحب المشروع / عميل الإنتاج |
| **تاريخ البلاغ** | 2026-11-11 |
| **تاريخ الاكتشاف** | مراجعة واجهة التقويم ومحددات التاريخ في الوضع الداكن (Production) |
| **نسخة التطبيق** | 2.3.0+1 |
| **الفرع المتأثر** | `integration/all-agents` |
| **معرف صفحة Notion** | `415ac9ca-77d5-810a-9402-e426063b3c37` |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الشاشات / المسارات** | `lib/core/config/theme.dart`, `lib/ui/widgets/daily_sales_calendar.dart`, `lib/ui/reports/widgets/sales_report_tab.dart`, `lib/screens/reports/returns_report_screen.dart`, `lib/ui/customer/customer_statement_screen.dart`, `lib/ui/supplier/supplier_statement_screen.dart`, `lib/ui/setting/settings.dart` |
| **الـ Feature Flag** | عام للنظام |
| **الـ Flavors المتأثرة** | base / vegetable / clothing |
| **منطقة حساسة** | ☐ لا (UI & Theme) |
| **مستوى المخاطرة** | منخفض |

## 3. إعادة الإنتاج (إجباري قبل أي إصلاح)

**الخطوات:**
1. تفعيل الوضع الداكن (Dark Mode) من الإعدادات.
2. فتح أي محدد فترة زمنية (`showDateRangePicker` في تقارير المبيعات أو المرتجعات أو كشف حساب عميل/مورد) أو فتح تقويم المبيعات اليومية (`DailySalesCalendar`).
3. ملاحظة الألوان والخلفية وتباين اليوم المحدد واليوم الحالي والفترة المختارة وكارت التفاصيل.

**النتيجة المتوقعة:** التقويم ومحددات التاريخ تتبع ثيم التطبيق (`Dark` / `Light`) بتباين واضح لجميع الأيام والنصوص والأحداث.
**النتيجة الفعلية:** تباين ضعيف وألوان من الوضع الفاتح (`Colors.blue.shade50`, `ColorScheme.light(...)`, إعداد `CalendarThemeMode.light` الافتراضي، ونقص ألوان النطاق `rangeSelectionBackgroundColor` في `DatePickerThemeData`).

## 4. السبب الجذري

- **السطحي:** ظهور ألوان فاتحة أو نصوص غير مقروءة داخل التقويم ومحددات التاريخ في الوضع الداكن.
- **الجذري:**
  1. `lib/core/config/theme.dart:229-253`: `DatePickerThemeData` في `getDarkTheme()` استخدم `primary: Colors.white` دون تحديد `dayBackgroundColor`, `todayBackgroundColor`, `rangeSelectionBackgroundColor`, `rangePickerBackgroundColor`, `weekdayStyle`, `yearBackgroundColor`.
  2. `lib/ui/reports/widgets/sales_report_tab.dart:151-158` و `lib/screens/reports/returns_report_screen.dart:69-80`: إجبار `ColorScheme.light` داخل `builder` الخاص بـ `showDateRangePicker`.
  3. `lib/ui/customer/customer_statement_screen.dart:455-465` و `lib/ui/supplier/supplier_statement_screen.dart:260-270`: إجبار `ColorScheme.dark` داخل `builder` الخاص بـ `showDateRangePicker`.
  4. `lib/ui/widgets/daily_sales_calendar.dart:23,257`: الاعتماد على `CalendarThemeMode.light` الافتراضي بدلاً من ثيم التطبيق الحالي، واستخدام `Colors.blue.shade50` ثابت في `_buildSelectedDateDetails()`.

## 5. الحل

- استكمال `DatePickerThemeData` في `AppTheme.getLightTheme()` و`AppTheme.getDarkTheme()` بكافة الـ tokens الخاصة باليوم، اليوم الحالي، الفترة المختارة، والسنوات.
- إزالة الـ `builder` القسري لـ `ColorScheme.light/dark` من شاشات التقارير وكشوف الحساب ليتبع التقويم ثيم التطبيق تلقائياً.
- ربط `DailySalesCalendar` مباشرة بـ `Theme.of(context).brightness == Brightness.dark` واستبدال `Colors.blue.shade50` بألوان متوافقة مع الوضعين، وإزالة خيار "نمط ألوان التقويم" من الإعدادات بناءً على طلب صاحب المشروع.

## 6. الاختبارات والتحقق

| البند | القيمة |
|---|---|
| **اختبار انحدار أُضيف** | `test/unit/auth_and_calendar_theme_test.dart` |
| **الحالة التي يغطيها** | التحقق من ألوان `datePickerTheme` في Dark وLight وتوافق `DailySalesCalendar` مع الوضعين |
| **الأمر المُنفَّذ** | `flutter test --no-pub test/unit/auth_and_calendar_theme_test.dart test/unit/app_theme_responsive_test.dart` |
| **النتيجة الفعلية** | `00:02 +9: All tests passed!` (نجاح 9/9 اختبارات) |
| **تحليل ثابت** | `flutter analyze --no-pub ...` (20 ملفاً): `No issues found!` |

## 7. الأثر الخلفي

- هل يتغير حساب مالي قائم؟ ☑ لا
- هل يلزم Migration؟ ☑ لا
- هل يلزم تحديث النسخ الاحتياطي؟ ☑ لا

## 8. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-11-13 | Agent | فتح التذكرة محلياً وبدء التحقيق والإصلاح (مرجع Notion: BUG-036) |
| 2026-11-13 | Agent | إتمام الإصلاح والتحقق (`No issues found!`، ونجاح 9/9 اختبارات وحدة/ثيم) وتحديث الحالة إلى `resolved` |
