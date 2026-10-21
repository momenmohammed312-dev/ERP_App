# BUG-026 — إصلاح النسخ الاحتياطي الذري وتأمين الاستعادة بدون قفل الملفات وحماية بيانات العملاء

> تذكرة إصلاح وتثبيت موثوقية النسخ الاحتياطي والاستعادة المحلية بنسبة 100% بدون أي أثر سلبي على العملاء الحاليين (Zero Customer Impact).

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-026 |
| **العنوان** | عدم ذرية النسخ الاحتياطي ومخاطر قفل الملفات Windows Error 32 وفقدان المعاملات أثناء الاستعادة |
| **النوع** | Data Integrity / Defect / Reliability |
| **الأولوية** | P1 حرجة |
| **الحالة** | resolved |
| **الأبلغ** | فريق التدقيق المعماري (MADAR Architecture & Reliability Audit) |
| **تاريخ البلاغ** | 2026-10-20 |
| **تاريخ الاكتشاف** | أثناء الفحص المعماري الشامل لنظام النسخ والاستعادة (Phase 1 Audit) |
| **نسخة التطبيق** | 2.3.0+1 |
| **الفرع المتأثر** | `integration/all-agents` |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الشاشات / المسارات** | `lib/services/enhanced_backup_service.dart` و `lib/ui/backup/` |
| **الـ Feature Flag** | عام للنظام وحماية البيانات |
| **الـ Flavors المتأثرة** | كافة النكهات (base, vegetable, clothing) دون مساس بـ base |
| **منطقة حساسة** | ☑ نسخ احتياطي واستعادة ☑ حماية بيانات العملاء |
| **مستوى المخاطرة** | عالٍ (منطقة حساسة تستوجب سلامة تامة وعدم لمس داتابيز حية) |

> ⚠️ **قاعدة إيقاف:**
> 1. اختبار انحدار إجباري في `test/unit/services/`
> 2. عدم تعديل أي قاعدة بيانات حية للعميل
> 3. الحفاظ على التوافقية العكسية 100% مع كافة النسخ السابقة

## 3. إعادة الإنتاج

1. محاولة أخذ نسخة احتياطية أثناء وجود معاملات كتابية نشطة: استخدام `File.copy()` ينسخ ملف SQLite الحي دون انتظار تفريغ الـ Rollback Journal مما ينتج عنه لقطة غير متسقة.
2. محاولة استعادة نسخة احتياطية على نظام Windows: محاولة `File.copy()` فوق ملف الداتابيز المفتوح تسفر عن خطأ `OS Error 32: The process cannot access the file because it is being used by another process`.
3. استعادة ملف تالف أو من إصدار مستقبلي: يتم استبدال الملف الأصلي قبل التحقق من سلامة الملف المرشح، مما يؤدي إلى تلف قاعدة البيانات الحالية.

## 4. السبب الجذري

- **السطحي:** فشل الاستعادة بأخطاء نظام التشغيل أو تلف أجزاء من النسخ المستعادة.
- **الجذري:**
  1. `EnhancedBackupService.createBackup()` يقوم بنسخ مباشر لملف الداتابيز المفتوح عبر `dbFile.copy()` بدلاً من استخدام أمر SQLite الذري `VACUUM INTO`.
  2. لا يوجد فحص سلامة هيكلية مسبق `PRAGMA integrity_check` على الملف المعزول قبل اعتماده.
  3. `EnhancedBackupService.restoreBackup()` يستبدل الملف الحي مباشرة دون إغلاق اتصال Drift ودون التحقق المسبق من الملف المرشح في بيئة عزل، ودون آلية تراجع تلقائي (Rollback) عند الفشل.
  4. وجود تدوير وحذف تلقائي ساذج (`_cleanOldBackups`) قد يحذف نسخاً قديمة دون التحقق من أن النسخة الحالية صالحة.

## 5. الحل

1. تعديل `createBackup`:
   - استخدام أمر SQLite الذري `VACUUM INTO` لإنشاء لقطة متسقة تماماً وخالية من الفراغات دون إيقاف معاملات البيع.
   - التحقق الفوري من سلامة النسخة في بيئة العزل عبر `PRAGMA integrity_check`.
   - إيقاف الحذف التلقائي العشوائي للنسخ القديمة في هذه المرحلة لحماية تاريخ العميل.
   - **(SEC-01)** إضافة قفل تزامن (`BackupOperationInProgressException`) لمنع تعارض نسختين متزامنتين.
   - **(SEC-01)** حصر تنظيف المجلدات المؤقتة على المجلد الخاص بالعملية الحالية فقط وإلغاء المسح العشوائي لـ `temp_*`.
   - **(SEC-08)** إلغاء الـ fallback copy الخام الذي كان ينسخ ملف الداتابيز المفتوح، وإرجاع استثناء منضبط في حال فشل `VACUUM INTO`.
2. تعديل `restoreBackup`:
   - فحص وتوثيق سلامة الملف المرشح في مجلد مؤقت معزول والتأكد من مطابقة الـ `integrity_check` وتوافق `schemaVersion <= 80`.
   - أخذ لقطة أمان مسبقة (Safety Snapshot) من الداتابيز الحالية ومن أي ملفات جانبية (`-wal`, `-shm`, `-journal`).
   - إغلاق اتصال Drift بأمان قبل استبدال الملف لمنع قفل الويندوز `errno = 32`.
   - تنظيف ملفات الـ Sidecars القديمة قبل استبدال الملف الجديد لضمان عدم حدوث تلوث في الاسترداد.
   - استبدال الملف مع آلية تراجع فوري (Rollback) في حال حدوث أي خطأ في نظام التشغيل لكافة الملفات.
   - **(SEC-03)** تصحيح مسار استعادة ملفات الإعدادات في `_restoreConfigFiles` بالاعتماد على `getApplicationDocumentsDirectory` بدلاً من المسار النسبي، مع استثناء `backup_info.json` وفحص المسارات ضد path traversal.
3. معالجة دورة حياة الموفرات والشاشات (SEC-02 & SEC-06):
   - **(SEC-02)** توحيد تحديث `appDatabaseProvider` في كل من `EnhancedBackupScreen` و `BackupManagementScreen`.
   - **(SEC-06)** إلغاء الابتلاع الصامت للأخطاء في `catch (_) {}`؛ إذا فشلت إعادة قراءة قاعدة البيانات يظهر خطأ صريح ولا تظهر رسالة نجاح مضللة.
4. أقفال SQLite والمعاملات المتزامنة (SEC-04):
   - **(SEC-04)** ضبط `PRAGMA busy_timeout = 5000;` في `AppDatabase.beforeOpen` وفي لقطة النسخ الاحتياطي لمنع انهيار فواتير الكاشير برمز `SQLITE_BUSY`.
5. الحفاظ الكامل على التوافقية مع كافة مفاتيح وفورمات النسخ القديمة لضمان قراءة أي نسخة سابقة للعميل.

## 6. الاختبارات والتحقق (إجباري)

- تم تنفيذ اختبار انحدار شامل ومعزول تماماً في `test/unit/services/safe_atomic_backup_test.dart` (10 اختبارات ناجحة بنسبة 100%):
  1. `createBackup uses VACUUM INTO, produces valid snapshot, leaves source unchanged`: PASSED (تحقق ذري للقطة وعدم مساس المصدر).
  2. `restoreBackup successfully restores database without locking error`: PASSED (استعادة كاملة بدون أي قفل ملفات على Windows).
  3. `restoreBackup rejects corrupt candidate before overwriting live database`: PASSED (رفض قاطع للنسخ التالفة وحماية الداتابيز الحية).
  4. `restoreBackup creates safety snapshot before replacement`: PASSED (إنشاء ملف لقطة أمان `.before_restore_` تلقائياً).
  5. `Phase 1 does not delete old backups automatically during creation`: PASSED (تأكيد عدم حذف أي نسخة سابقة في المرحلة الأولى).
  6. `Existing legacy backup files remain discoverable and valid`: PASSED (توافق كامل مع قراءة النسخ السابقة).
  7. `concurrent backup attempts reject second request with BackupOperationInProgressException`: PASSED (رفض التنافس وتأمين القفل).
  8. `temporary directory ownership: backup cleans only its own temp directory`: PASSED (عزل وتنظيف المجلد المؤقت الخاص بالعملية فقط).
  9. `write transaction during backup does not deadlock or crash with busy_timeout configured`: PASSED (نجاح معاملات الكتابة المتزامنة بفضل busy_timeout).
  10. `restoreBackup safely handles and archives sidecar files`: PASSED (أرشفة وتنظيف ملفات الـ sidecars بأمان).
- اختبار جداول النسخ الحالية `test/unit/services/backup_tables_test.dart`: PASSED (جميع الجداول مطابقة والترتيب سليم).
- فحص الكود الساكن `flutter analyze`: 0 errors, 0 warnings (خالٍ تماماً من المشاكل عبر كافة الملفات المعدلة).

## 7. الأثر الخلفي

- هل يتغير حساب مالي قائم؟ لا.
- هل يلزم Migration؟ لا، schemaVersion يبقى 80.
- هل تلغى أي مفاتيح تشفير سابقة؟ لا، التوافقية محفوظة 100%.
- هل تم الحفاظ على تعديلات أندرويد ومشاركة الملفات؟ نعم، محفوظة 100% في `enhanced_backup_screen.dart`.
- خطة الرجوع (Rollback): تراجع موضعي محدد للملفات دون استخدام `git checkout HEAD --` العام حتى لا تُمحى ميزات الموبايل.

## 8. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-20 | MADAR Reliability Agent | إنشاء البلاغ بحالة in-progress وبدء تنفيذ التثبيت الفني الآمن |
| 2026-10-20 | MADAR Reliability Agent | اكتمال التنفيذ الأولي للمرحلة الأولى |
| 2026-10-21 | MADAR Reliability Agent | مراجعة أمنية مستقلة وتطبيق حزمة الإصلاحات الدقيقة (SEC-01 حتى SEC-06) وتحويل الحالة إلى resolved |
