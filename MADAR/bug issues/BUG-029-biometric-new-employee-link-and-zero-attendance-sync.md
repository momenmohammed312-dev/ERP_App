---
id: BUG-029
title: "الموظف الجديد بعد ربط الـ ID بالاسم على البرنامج لا تظهر بصمته وتظهر صفر (0) في الحضور والمزامنة"
status: resolved
severity: P2
flavor: all
module: attendance
sensitive_zone: true
reported_by: "Customer Support / Production Client"
assigned_to: "Gemini 4 Argon (Architect) + Gemini 3.8 Flash + OpenCode (big-pickle)"
created_at: 2026-10-27
updated_at: 2026-10-27
related_commits: ["25b79ae"]
related_prs: []
---

## 1. الملخص (Summary)

عند قيام موظف جديد بالبصم على جهاز البصمة (ZKTeco)، يظهر رقم الـ ID الخاص به في برنامج **مدار ERP** (`موظف <ID>` أو ضمن مستخدمي الجهاز / البصمات غير المربوطة). عندما يقوم المستخدم بكتابة اسم الموظف وربطه بالـ ID في البرنامج ثم يقوم الموظف بالبصم على جهاز البصمة، يعطيه الجهاز تأكيداً بنجاح البصمة ("تمام بصم")، ولكن في برنامج **مدار ERP** لا تظهر البصمة للموظف وتظهر النتيجة **صفر (`0`)** (`0 من الأجهزة، 0 اتسجل حضور` أو `0 سجل` في صفحة حضور الموظف).

## 2. البيئة (Environment)

- **الفرع (Branch):** `integration/all-agents`
- **الـ Flavor:** `all` (`base`, `vegetable_market`)
- **نظام التشغيل:** Windows 10/11 Desktop
- **إصدار قاعـدة البيانات (`schemaVersion`):** الحالية بدون الحاجة لـ migration جديد

## 3. خطوات إعادة الإنتاج (Steps to Reproduce)

1. وجود جهاز بصمة ZKTeco متصل عبر الشبكة (`connectionType = 'tcp_ip'`)، مع احتمال وجود جهاز افتراضي `FILE-IMPORT` في جدول `biometric_devices` (يُنشأ تلقائياً عند استيراد ملف إكسل أو حفظ موظف قبل إضافة الجهاز).
2. قيام موظف جديد بالبصم على جهاز البصمة (مثلاً برقم بصمة `105`)، فتقوم المزامنة التلقائية بإنشاء سجل مؤقت باسم `موظف 105` وربط `(deviceId, '105')` به.
3. قيام المستخدم بكتابة اسم الموظف الحقيقي وربطه برقم البصمة `105` عبر إحدى الطرق المعتادة في البرنامج:
   - **الطريقة (أ):** تعديل `موظف 105` في شاشة `StaffFormPage` وكتابة اسمه الحقيقي ثم الحفظ.
   - **الطريقة (ب):** إضافة موظف جديد بالاسم الحقيقي في `StaffFormPage` (أو بعد حذف `موظف 105`) وكتابة `105` في حقل `رقم البصمة (ID على جهاز البصمة)` ثم الحفظ.
   - **الطريقة (ج):** ربط رقم البصمة بالموظف من شاشة `BiometricEnrollmentPage` أو `DeviceUserImportPage`.
4. قيام الموظف بالبصم على جهاز البصمة ومزامنة الحضور في البرنامج.
5. **الملاحظ:** تظهر النتيجة `0` في البرنامج (سواء `0 اتسجل حضور` عند المزامنة أو `0 سجل` في صفحة حضور الموظف).

## 4. السلوك المتوقع مقابل الفعلي (Expected vs. Actual)

- **المتوقع (Expected):**
  - ارتباط رقم البصمة `externalUserId` بالموظف الفعلي على جميع أجهزة البصمة النشطة (`tcp_ip`) دون الكتابة فوق `deviceId` بجهاز `FILE-IMPORT` غير النشط.
  - عند ربط رقم بصمة كان مربوطاً بسجل تلقائي مؤقت (`موظف <ID>`) أو موظف محذوف، يتم نقل الربط وسجلات الحضور/الأحداث الخام تلقائياً وذرياً (`transaction`) إلى الموظف المسمى وإعادة معالجة الأحداث المعلقة فوراً.
  - عند تصحيح انحراف ساعة جهاز البصمة (`setDeviceTime`) أو وجود `lastSyncAt` مستقبلي بالنسبة لساعة الجهاز، يتم تصفير الكيرسور تلقائياً بحيث لا تُحجب البصمات الجديدة بفلتر `since`.
  - قراءة قائمة المستخدمين `getUsers()` وسجلات الحضور `fetchAttendanceReport()` من أجهزة ZKTeco بدقة مع إزالة بادئة الحجم (4-byte size prefix) لكل الأحجام القياسية.
- **الفعلي (Actual):**
  - دالة `StaffFormPage._saveForm` تستبدل `deviceId` دائماً بـ `devices.first.id` (الذي يكون غالباً `FILE-IMPORT`)، وتبتلع خطأ `UNIQUE(device_id, external_user_id)` بصمت (`catch (bioErr)`) مع إظهار رسالة `تم الحفظ بنجاح`!
  - دالة `StaffManagementDao.deleteStaff` تحذف الموظف منطقياً (`status = 'deleted'`) وتترك صف `staff_biometric_mappings` يربط رقم البصمة بالموظف المحذوف، فيرفض `processPendingEvents` كل بصمة جديدة لهذا الرقم (`matched = 0`).
  - دالة `processPendingEvents` لا تبحث في الربط عبر الأجهزة (`getEnrolledMappingByExternalIdAnyDevice`) قبل إنشاء `موظف <ID>` جديد.
  - دالة `syncDevice` تضبط ساعة الجهاز عند وجود انحراف > دقيقتين دون تصفير `lastSyncAt` إذا كان الانحراف أقل من ساعة، فيظل `overlapSince` في المستقبل وتظهر المزامنة `0 من الأجهزة، 0 اتسجل حضور`.
  - دالة `ZKTecoClient.getUsers()` لا تزيل بادئة الحجم (4 بايت) من حزمة البيانات، مما يزيح قراءة حقول المستخدم 4 بايت ويجعل `uid` و `userId` يظهران `0`.

## 5. الأدلة واللقطات (Evidence & Logs)

- `lib/ui/staff/staff_form_page.dart:838-863`:
  ```dart
  deviceId = devices.first.id;
  ...
  } catch (bioErr) {
    debugPrint('Error saving biometric mapping: $bioErr');
  }
  ```
- `lib/services/attendance/attendance_sync_service.dart:499-552`:
  يبحث فقط في `getMappingRecordByExternalId(deviceId, rawEvent.externalUserId)` ويرفض الحدث إذا كان الموظف القديم المرتبط بالرقم محذوفاً (`status == 'deleted'`) دون التحقق من وجود موظف نشط مرتبط بنفس الرقم.
- `lib/services/attendance/attendance_sync_service.dart:290-318`:
  يضبط ساعة الجهاز عبر `setDeviceTime(DateTime.now())` عند انحراف > دقيقتين لكن لا يصفر `effectiveSinceBase` إلا إذا تجاوز `lastSyncAt` ساعة كاملة (`_futureCursorTolerance = Duration(hours: 1)`).
- `lib/services/attendance/zkteco/zkteco_client.dart:266-302`:
  `getUsers()` لا يزيل الـ 4 بايت الخاصة بحجم البيانات (`possibleSize == data.length - 4`) قبل تقسيم السجلات (72 أو 28 بايت).

## 6. تحليل السبب الجذري (Root Cause Analysis — يُملأ أثناء التحقيق)

- **الملف والسطر (`file:line`):**
  1. `lib/ui/staff/staff_form_page.dart:824-864` (`_saveForm`)
  2. `lib/ui/staff/biometric_enrollment_page.dart:205-225` (`_showAddMappingDialog`)
  3. `lib/ui/staff/device_user_import_page.dart:142-181` (`_persistEnrolledMapping`)
  4. `lib/services/attendance/attendance_sync_service.dart:290-319` (`syncDevice` clock drift vs cursor) & `496-553` (`processPendingEvents` cross-device & placeholder/deleted staff reconciliation)
  5. `lib/core/database/dao/staff_management_dao.dart:51-60` (`deleteStaff` leaving orphan biometric mappings)
  6. `lib/services/attendance/zkteco/zkteco_client.dart:263-305, 342-353, 467-487` (`getUsers` & `fetchAttendanceReport` 4-byte size header & 28-byte user ID parsing)
- **لماذا حدث الخطأ؟**
  تفاعل سلسلة الربط بين واجهة الموظفين (`StaffFormPage` / `BiometricEnrollmentPage` / `DeviceUserImportPage`) ومحرك المزامنة (`AttendanceSyncService`) وبروتوكول ZKTeco:
  1. عند أول بصمة للموظف الجديد، ينشئ المحرك تلقائياً موظفاً مؤقتاً `موظف <ID>` ويحجز `(deviceId, externalUserId)` في جدول `staff_biometric_mappings` (أو يظل محجوزاً لموظف محذوف سابقاً).
  2. عند قيام المستخدم بكتابة اسم الموظف وربطه بالـ ID في `StaffFormPage`، إما أن يتم نقل الربط بالخطأ إلى `devices.first.id` (`FILE-IMPORT`) عند التعديل، أو يفشل إدراج الربط بسبب قيد التفرد `UNIQUE(device_id, external_user_id)` ويتم ابتلاع الخطأ بصمت عند الإضافة.
  3. كما أن الأحداث التي تمت معالجتها تحت السجل المؤقت `موظف <ID>` تأخذ الحالة `processed` فلا تعيد دالة `requeueUnmatchedEventsForExternalId` معالجتها للموظف الحقيقي.
  4. بالإضافة لذلك، عند تصحيح ساعة جهاز البصمة (`setDeviceTime`) دون تصفير `lastSyncAt` المستقبلي، يتم استبعاد البصمات الجديدة عبر فلتر `since` فتعود المزامنة بـ `0`.
- **لماذا لم تمنعه الحواجز الحالية؟**
  الاختبارات السابقة كانت تختبر `processPendingEvents` بمعزل عن تدفق ربط الموظف من شاشة `StaffFormPage` وعن حالة وجود جهاز `FILE-IMPORT` بجانب جهاز `tcp_ip`، ولم تختبر تفاعل `setDeviceTime` مع `lastSyncAt` أو بادئة الـ 4 بايت في `getUsers()`.

## 7. الإصلاح المقترح / المنفّذ (Fix)

- **الاستراتيجية:**
  1. إضافة دالة ذرية شاملة `reconcileAndLinkBiometricId` في `AttendanceSyncService` (تعمل داخل `db.transaction`) تقوم بـ:
     - اختيار أجهزة البصمة النشطة (`tcp_ip` / `isActive`) وعدم الكتابة فوق `deviceId` النشط بجهاز `FILE-IMPORT`.
     - إذا كان `externalUserId` مربوطاً بسجل مؤقت تلقائي (`موظف <ID>` براتب 0) أو موظف محذوف/غير نشط، يتم نقل سجلات الحضور (`attendance_table`) والأحداث الخام (`attendance_raw_events`) وتحديث صف الربط (`staff_biometric_mappings`) إلى الموظف الحقيقي، وحذف السجل المؤقت المكرر منطقياً.
     - إعادة جدولة ومعالجة أي بصمات معلقة أو غير مربوطة فوراً (`requeueUnmatchedEventsForExternalId` + `processPendingEvents`).
  2. تحديث `StaffFormPage` و `BiometricEnrollmentPage` و `DeviceUserImportPage` و `UnmatchedAttendancePage` لاستخدام `reconcileAndLinkBiometricId`.
  3. تحديث `AttendanceSyncService.processPendingEvents` للتحقق من وجود ربط نشط لنفس `externalUserId` على أي جهاز (`getEnrolledMappingByExternalIdAnyDevice`) أو إعادة توجيه الربط إذا كان الموظف المرتبط على الجهاز الحالي محذوفاً أو مؤقتاً.
  4. تنظيف ربط البصمة عند حذف موظف في `StaffManagementDao.deleteStaff`.
  5. في `AttendanceSyncService.syncDevice`: تصفير `effectiveSinceBase` عند تعديل ساعة الجهاز (`setDeviceTime`) أو عندما يكون `lastSyncAt` متقدماً على ساعة الجهاز أو الساعة الحالية بأكثر من دقيقتين.
  6. في `ZKTecoClient`: إزالة بادئة الحجم (4 بايت `possibleSize == length - 4`) في `getUsers()` و `fetchAttendanceReport()` لكافة أحجام السجلات، وقراءة `PIN2` في `_parse28ByteUser`.
- **الملفات المعدّلة:**
  - `lib/services/attendance/zkteco/zkteco_client.dart`
  - `lib/services/attendance/attendance_sync_service.dart`
  - `lib/core/database/dao/staff_management_dao.dart`
  - `lib/ui/staff/staff_form_page.dart`
  - `lib/ui/staff/biometric_enrollment_page.dart`
  - `lib/ui/staff/device_user_import_page.dart`
  - `lib/ui/staff/unmatched_attendance_page.dart`
- **هل يتطلب Migration؟** لا

## 8. اختبار منع الانحدار (Regression Test)

- **ملف الاختبار:** `test/unit/biometric_employee_link_sync_bug029_test.dart`
- **ما الذي يثبته الاختبار؟**
  1. تعديل موظف منشأ تلقائياً (`موظف 105`) وكتابة اسمه الحقيقي مع وجود جهاز `FILE-IMPORT` كأول جهاز وجهاز `tcp_ip` كجهاز ثانٍ يحافظ على الربط بجهاز `tcp_ip` ويسجل البصمات الجديدة للموظف (لا يظهر 0).
  2. إضافة موظف جديد بالاسم ورقم البصمة `105` بعد أن أنشأ الجهاز `موظف 105` (أو بعد حذف موظف سابق بنفس الرقم) ينقل الربط وسجلات الحضور للموظف الجديد دون خطأ `UNIQUE constraint` مكتوم، وتظهر بصماته الجديدة فوراً.
  3. استيراد/مطابقة الموظف في `processPendingEvents` عبر الأجهزة (`cross-device mapping`) يربط البصمة بالموظف المسمى بدلاً من إنشاء `موظف <ID>` مكرر.
  4. تصحيح انحراف ساعة الجهاز (`setDeviceTime` / كيرسور متقدم 20 دقيقة) يصفر الكيرسور ويسحب بصمة الموظف الجديد بدلاً من إرجاع `0`.
  5. `ZKTecoClient.getUsers()` و `fetchAttendanceReport()` مع بادئة الحجم (4 بايت) يقرآن `userId` وسجلات الحضور بدقة دون إزاحة أو تصفير الـ ID.

## 9. قائمة التحقق قبل الإغلاق (Verification Checklist)

- [x] `flutter analyze` بدون أخطاء على الملفات المعدلة
- [x] `flutter test test/unit/biometric_employee_link_sync_bug029_test.dart` يمر بالكامل (42/42 اختبار حضور وبصمة ناجح)
- [x] لا توجد بيانات عملاء حقيقية في التذكرة أو الاختبار
- [x] التغيير ذري (atomic transaction) لكل مسار يمس ربط الموظفين والحضور
- [x] تم التحديث في `CHANGELOG` أو ملاحظات الإصدار إن لزم
