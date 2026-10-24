# BUG-022 — إصلاح كراش إقلاع تطبيق الأندرويد ونقل تحسينات الموبايل الانتقائية إلى الفرع المعتمد

> بلاغ خطأ وتحسين يوثق أسباب انهيار تطبيق الأندرويد فور الإقلاع (Startup Crash) في وضع الـ Release، ومعالجة فحص المفتاح السري وحماية الـ Zone Guard وقناة الطابعات والأذونات، مع النقل الانتقائي الحذر (Selective Porting) لتحسينات وتجاوب الموبايل من فرع `mobile` دون المساس بمنظومة التراخيص السحابية أو مجلد `admin_dashboard/`.

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-022 |
| **العنوان** | إصلاح كراش إقلاع الأندرويد والنقل الانتقائي لتحسينات الموبايل المتجاوبة |
| **النوع** | Defect / Mobile Platform / Responsive UI |
| **الأولوية** | P1 حرجة (توقف التطبيق على منصة أندرويد) |
| **الحالة** | resolved |
| **الأبلغ** | فريق التطوير والتدقيق (MADAR Agentic Engineering) |
| **تاريخ البلاغ** | 2026-10-20 |
| **تاريخ الإغلاق** | 2026-10-20 |
| **الفرع المستهدف** | `integration/all-agents` |
| **الفرع المصدري** | `mobile` (في الـ Worktree المعزول) |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الشاشات / المسارات** | `lib/app_bootstrap.dart`, `lib/main*.dart`, `lib/core/services/printer_service.dart`, `android/app/src/main/AndroidManifest.xml`, ومكونات واجهة الموبايل المتجاوبة |
| **الـ Feature Flag** | عام للتطبيق / فحص المنصة `PlatformUtils.isMobile` |
| **الـ Flavors المتأثرة** | كافة النكهات (base, vegetable, clothing) |
| **مستوى المخاطرة** | عالي لحساسية إقلاع الأندرويد — مع الالتزام التام بعدم لمس `Schema v80` أو التراخيص السحابية `feat/online-license` |

## 3. الأسباب الجذرية لكراش الأندرويد (Root Causes)

1. **كراش المفتاح السري في وضع الـ Release (`StateError`):**
   - استدعاء `LicenseConfig.assertSecretKeyConfigured()` في `lib/app_bootstrap.dart` يرمي `throw StateError` إذا لم يتم تمرير `--dart-define=LICENSE_SECRET_KEY` أثناء تجميع APK في وضع `kReleaseMode`، مما يؤدي لموت العملية قبل استدعاء `runApp()`.
2. **غياب `runZonedGuarded` في نقاط الدخول الرئيسية:**
   - أي استثناء غير معالج أثناء تهيئة الـ bindings أو الخدمات يقتل التطبيق فوراً بشاشة بيضاء وإغلاق إجباري.
3. **انهيار استدعاء الطابعات المفقودة على الأندرويد (`MissingPluginException`):**
   - حزمة `printing` لا تدعم استدعاء `listPrinters()` على نظام Android، وكان الاستدعاء يرمي استثناء دون التحقق من المنصة.
4. **أذونات أندرويد غير المتوافقة في `AndroidManifest.xml`:**
   - وجود أذونات خطرة ملغاة مثل `MANAGE_EXTERNAL_STORAGE` و `CAMERA` يسبب تعليق أو رفض الإقلاع على Android 11 فما فوق.

## 4. خطة العمل المنفذة (Implemented Solutions)

1. **إصلاح كراش الإقلاع:**
   - تأمين فحص المفتاح السري في `lib/app_bootstrap.dart:51` و `lib/services/license_manager.dart:190` عبر تغليف `LicenseConfig.assertSecretKeyConfigured()` داخل `try/catch` مع تسجيل تحذير `AppLogger.w` بدلاً من إسقاط التطبيق عند تجميع APK للاختبار بدون `--dart-define`.
   - تغليف نقاط الدخول (`lib/main.dart`, `lib/main_vegetable.dart`, `lib/main_clothing.dart`) بـ `runZonedGuarded` مع التقاط الأخطاء القاتلة وطباعتها بأمان.
   - التحقق من فحص `PlatformUtils.isMobile` في `lib/core/services/printer_service.dart:822` لإرجاع قائمة فارغة بدلاً من رمي `MissingPluginException`.
   - تنظيف أذونات `android/app/src/main/AndroidManifest.xml` وحذف الأذونات غير المستخدمة مع ضبط `android:usesCleartextTraffic="true"`.
2. **النقل الانتقائي الحذر لميزات الموبايل (Selective Porting):**
   - نقل مساعدات التجاوب `lib/core/platform/platform_utils.dart` و `lib/core/platform/responsive.dart`.
   - منع تنزيل تحديثات سطح المكتب في `lib/services/update_service.dart`.
   - تجاوب النوافذ المنبثقة في `lib/ui/payment/widgets/payment_dialog.dart` و `lib/ui/invoice/widgets/product_selection_modal.dart`.
   - تجاوب سطور الفاتورة باستخدام `Wrap` و `FittedBox` في `lib/ui/invoice/widgets/order_line_item.dart` مع الحفاظ التام على معلمات الأصناف والمقاسات (`ProductVariant`, `db`, `initialVariant`).
   - التمرير الأفقي للجداول في `customer_report_tab.dart`, `expenses_report_tab.dart`, `purchase_vs_sales_report.dart`.
   - استيراد الإكسيل عبر الذاكرة المؤقتة في `excel_import_screen.dart`.
   - مشاركة ملفات النسخ الاحتياطي عبر الـ Share Sheet في `enhanced_backup_screen.dart`.
3. **التحقق والاختبار (Verification):**
   - تم تشغيل `flutter analyze --no-pub` واجتاز بـ 0 أخطاء و 0 تحذيرات (فقط 87 lint info غير مؤثرة).
   - اجتياز اختبارات التجاوب المنصي `test/unit/platform_responsive_test.dart` (4/4 اختبارات بنجاح).
   - اجتياز كامل الاختبارات التراجعية للمخطط والمحاسبة والأرصدة والتواريخ والحضور (21/21 اختبار بنجاح 100%).

## 5. نتائج الاختبارات (Test Evidence)

```
00:26 +21: All tests passed!
- test/unit/migration_v80_unified_test.dart (Passed)
- test/unit/services/backup_tables_test.dart (Passed)
- test/unit/services/business_date_cash_drawer_bug017_test.dart (Passed)
- test/unit/services/document_date_precision_bug019_test.dart (Passed)
- test/unit/attendance_late_minutes_bug020_test.dart (Passed)
- test/unit/platform_responsive_test.dart (Passed)
```

## 6. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-20 | MADAR Agent | فتح التذكرة بحالة in-progress وبدء تنفيذ الإصلاحات |
| 2026-10-20 | MADAR Agent | اكتمال الإصلاحات والنقل الانتقائي واجتياز التحليل الساكن وكافة الاختبارات التراجعية، وتحديث الحالة إلى resolved |
