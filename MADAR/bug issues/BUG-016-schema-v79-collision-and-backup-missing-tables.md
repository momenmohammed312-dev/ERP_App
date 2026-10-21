# BUG-016 — تعارض Schema v79 بين الفروع وغياب 6 جداول حيوية من BackupService

> بلاغ خطأ يوثق تعارض إصدار Schema v79 بين فرع integration/all-agents وفرع demo/all-features، وفجوة النسخ الاحتياطي الخطيرة المكتشفة في الفحص العملي لداتابيز العميل.

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-016 |
| **العنوان** | تعارض Schema v79 بين الفروع وغياب جداول الحسابات والملخص الشهري من BackupService |
| **النوع** | Data Integrity / Defect / Regression |
| **الأولوية** | P1 حرجة |
| **الحالة** | resolved |
| **الأبلغ** | فريق التحليل والتطوير (MADAR Agentic Audit) |
| **تاريخ البلاغ** | 2026-10-19 |
| **تاريخ الاكتشاف** | أثناء الفحص المعزول لداتابيز العميل (المراحل 1 إلى 4) |
| **نسخة التطبيق** | 2.3.0+1 |
| **الفرع المتأثر** | `integration/all-agents` |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الشاشات / المسارات** | `lib/core/database/` و `lib/core/services/backup_service.dart` |
| **الـ Feature Flag** | عام للنظام وحماية البيانات |
| **الـ Flavors المتأثرة** | كافة النكهات (base, vegetable, clothing) |
| **منطقة حساسة** | ☑ ترخيص ☑ دفتر حسابات ☑ فواتير ☑ نسخ احتياطي ☑ حضور/ZKTeco |
| **مستوى المخاطرة** | عالٍ جداً (فقدان بيانات محاسبية وتاريخية للعميل) |

## 3. إعادة الإنتاج

1. فحص قاعدة بيانات عميل تحتوي مسبقاً على جداول الحسابات (`accounts`, `journal_entries`, `journal_lines`) وعلى `monthly_attendance_summary_table` عند الإصدار `user_version = 78`.
2. تشغيل الترقية في فرع كان يعرف v79 كجداول منتجات فقط أو بدون idempotence يسبب تعارضات أو فقدان التنسيق.
3. إجراء عملية تصدير نسخة احتياطية واستعادتها عبر `BackupService`: لا يتم استعادة أي من جداول الحسابات الستة مما يمسح 150-205 صفاً حيوياً.

## 4. السبب الجذري

- **السطحي:** تعارض رقم الـ schema 79 بين فرعين متوازيين، وعدم اشتمال جداول المحاسبة المؤسسة في commit f4c5878 داخل `BackupService`.
- **الجذري:**
  1. فرع `integration/all-agents` سمى خطوة `product_variants` بـ v79، بينما فرع `demo/all-features` سمى خطوة الحسابات والشركاء بـ v79.
  2. في `lib/core/services/backup_service.dart` لم يتم إدراج الجداول الستة (`accounts`, `journal_entries`, `journal_lines`, `partners`, `equity_transactions`, `monthly_attendance_summary_table`) في قائمتي `tables` و `tableOrder`.
  3. جدول الملخص الشهري معرّف باسم `MonthlyAttendanceSummaryTable` وينتجه Drift تلقائياً كـ `monthly_attendance_summary` ما لم يتم تحديد `tableName` صراحة كـ `monthly_attendance_summary_table` لمطابقة بيانات العميل.

## 5. الحل

1. رفع `schemaVersion` إلى 80 كخطوة تأسيسية موحدة `_runV80UnifiedFoundation` تكون Idempotent 100%:
   - فحص وجود الجداول الـ 7 عبر `sqlite_master` وإنشاؤها عند الحاجة.
   - فحص الأعمدة الحيوية الـ 5 وإضافتها عبر `_ensureColumnExists`.
   - إنشاء الفهارس الخمسة (`IF NOT EXISTS`).
   - زرع حسابات النظام الـ 11 عبر `INSERT OR IGNORE` حتى لا يتم استبدال أي حساب موجود مسبقاً.
2. استجلاب كلاسات الجداول والـ DAOs المحاسبية من f4c5878 وضبط `tableName` لجدول الملخص الشهري ليكون صراحة `monthly_attendance_summary_table`.
3. إدراج الجداول الستة في `tables` و `tableOrder` في `BackupService` بالترتيب الصحيح لقيود المفاتيح الخارجية.
4. كتابة اختبار انحدار شامل `test/unit/migration_v80_unified_test.dart` والتحقق من `backup_tables_test.dart` ونسخة العميل.

## 6. التحقق والاختبارات

- **اختبار الترقية الموحدة (`test/unit/migration_v80_unified_test.dart`):**
  - الاختبار (a): Fresh DB يبدأ بـ v80 ويحتوي على كافة الجداول والأعمدة والفهارس وزرع الـ 11 حساباً -> **نجح**.
  - الاختبار (b): ترقية قاعدة بيانات v79 بدون جداول محاسبية إلى v80 وإنشاء الجداول وزرع الحسابات بنجاح -> **نجح**.
  - الاختبار (c): ترقية نسخة حقيقية من داتابيز العميل (v78) إلى v80 دون فقدان أي صف:
    * `accounts`: 12 صفاً (الحسابات الأصلية محفوظة 100%).
    * `journal_entries`: 35 صفاً.
    * `journal_lines`: 70 صفاً.
    * `monthly_attendance_summary_table`: 33 صفاً.
    * `invoices`: 108 صفاً.
    * `PRAGMA integrity_check`: ok.
    -> **نجح**.
- **اختبار النسخ الاحتياطي (`test/unit/services/backup_tables_test.dart`):**
  - مطابقة أسماء الـ 78 جدولاً الفعلية مع `BackupService` -> **نجح**.
  - التحقق من ترتيب الاستعادة FK-safe وعدم حدوث دورات -> **نجح**.
- **التحليل الساكن (`flutter analyze`):**
  - `lib/core/database/app_database.dart`: 0 أخطاء و 0 تحذيرات.
  - `lib/core/services/backup_service.dart`: 0 أخطاء و 0 تحذيرات.
  - ملفات الاختبار: 0 أخطاء و 0 تحذيرات.

## 7. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-19 | MADAR Agent | إنشاء البلاغ بحالة in-progress وبدء التنفيذ الفني |
| 2026-10-19 | MADAR Agent | اكتمال الحل ورفع schemaVersion إلى 80 وتأمين BackupService واجتياز كافة الاختبارات والتحويل إلى resolved |
