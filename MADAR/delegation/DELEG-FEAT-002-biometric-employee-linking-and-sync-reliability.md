---
id: DELEG-FEAT-002
title: "إصلاح واختبار ربط بصمة الموظف الجديد وعدم ظهور الحضور بصفر (BUG-029)"
status: verified
thinking_model: "Gemini 4 Argon (Architect & Orchestrator)"
implementer_model: "Gemini 3.8 Flash (Production Fix) + OpenCode opencode/big-pickle (Unit Test Suite)"
flavor: all
module: attendance
sensitive_zone: true
created_at: 2026-10-27
updated_at: 2026-10-27
related_tickets:
  - BUG-029
---

# 1. التحليل المعماري والتفكير العميق (Thinking Model Analysis)

## 1.1 الهدف وسياق الأعمال (Business Context)
بلّغ العميل عن مشكلة حرجة في موديول **الموظفين والحضور والانصراف (Biometric Attendance - ZKTeco)**:
1. عندما يبصم موظف جديد على جهاز البصمة، يظهر الـ ID الخاص به في برنامج **مدار ERP** (سواء كموظف تلقائي `موظف <ID>` أو في شاشات استيراد/ربط البصمة).
2. يقوم المستخدم بكتابة اسم الموظف وربطه بالـ ID في البرنامج ويظهر له أنه تم الحفظ بنجاح.
3. عندما يذهب هذا الموظف ليبصم على جهاز البصمة، يعطيه الجهاز أنه بصم بنجاح ("تمام بصم")، ولكن في برنامج **مدار ERP** لا تظهر البصمة وتظهر النتيجة **صفر (`0`)** (`0 من الأجهزة، 0 اتسجل حضور` أو `0 سجل` في صفحة حضور الموظف).

## 1.2 التشخيص الجذري (Root-Cause Synthesis)
بعد فحص كامل مسار الموظفين والبصمة (`ZKTecoClient` -> `ZKTecoTcpAttendanceSource` -> `AttendanceSyncService` -> `AttendanceDeviceDao` / `StaffManagementDao` -> `StaffFormPage` / `BiometricEnrollmentPage` / `DeviceUserImportPage`)، تبين وجود **5 أسباب جذرية مترابطة**:

1. **السبب الجذري الأول (`lib/ui/staff/staff_form_page.dart:824-864`):**
   - عند حفظ الموظف مع رقم بصمة (`bioId`)، تقوم `_saveForm` دائماً باختيار `deviceId = devices.first.id`! إذا كان أول جهاز في الجدول هو الجهاز الافتراضي `FILE-IMPORT` (`id = 1`، غير نشط) بينما جهاز البصمة الحقيقي `tcp_ip` هو `id = 2`، فإن تعديل اسم `موظف <ID>` ينقل ربطه من جهاز البصمة الحقيقي `2` إلى `FILE-IMPORT` رقم `1`!
   - وعند إضافة موظف جديد بالاسم ورقم البصمة `bioId` (بعد أن تم إنشاء `موظف <ID>` تلقائياً أو بعد حذف موظف قديم كان يحمل نفس الرقم)، يفشل `deviceDao.addMapping` بسبب قيد `UNIQUE(device_id, external_user_id)`، ويقوم بلوك `catch (bioErr)` بابتلاع الخطأ بصمت مع عرض رسالة `تم الحفظ بنجاح` للمستخدم!
   - كما أن `_saveForm` لا تقوم بنقل سجلات الحضور من السجل المؤقت `موظف <ID>` ولا تستدعي `requeueUnmatchedEventsForExternalId` أو `processPendingEvents`.

2. **السبب الجذري الثاني (`lib/services/attendance/attendance_sync_service.dart:496-553`):**
   - في `processPendingEvents`: يتم البحث فقط في `getMappingRecordByExternalId(deviceId, rawEvent.externalUserId)` للجهاز الواحد، دون استخدام `getEnrolledMappingByExternalIdAnyDevice` (على عكس `AttendanceFileImportService`). فإذا رُبط الموظف على جهاز آخر (مثل `FILE-IMPORT`)، ينشئ المحرك موظفاً وهمياً جديداً `موظف <ID>` براتب `0` ويسجل البصمة تحته بينما يظل الموظف الحقيقي بـ `0` حضور.
   - إذا كان صف `staff_biometric_mappings` على الجهاز يشير إلى موظف تم حذفه منطقياً (`status == 'deleted'`) أو سجل مؤقت `موظف <ID>`، فإن `processPendingEvents` يرفض البصمة كـ `unmatched` (`Staff is inactive or terminated (deleted)`) وتظهر النتيجة `0 اتسجل حضور`.

3. **السبب الجذري الثالث (`lib/core/database/dao/staff_management_dao.dart:51-60`):**
   - دالة `deleteStaff` تقوم بعمل soft-delete للموظف (`status = 'deleted', isActive = false`) لكنها تترك صفوف `staff_biometric_mappings` الخاصة به في قاعدة البيانات، مما يحجز `(device_id, external_user_id)` ويمنع ربطه بموظف جديد ويجعل أي بصمة قادمة لهذا الـ ID تفشل.

4. **السبب الجذري الرابع (`lib/services/attendance/attendance_sync_service.dart:290-319`):**
   - عند وجود فرق توقيت في ساعة جهاز البصمة (`drift > 2 minutes`)، تقوم `syncDevice` بتصحيح ساعة الجهاز عبر `setDeviceTime(DateTime.now())`. إذا كانت ساعة الجهاز متقدمة سابقاً (مثلاً بـ 16 إلى 59 دقيقة)، فإن `lastSyncAt` المحفوظ من مزامنة سابقة يظل في المستقبل لأن `_futureCursorTolerance` مضبوط على ساعة كاملة (`Duration(hours: 1)`). وبذلك يكون `overlapSince = lastSyncAt - 15m` في المستقبل بالنسبة لساعة الجهاز المصححة، فيستبعد فلتر `isAfter(since)` جميع البصمات الجديدة ويعيد `0 من الأجهزة، 0 اتسجل حضور`.

5. **السبب الجذري الخامس (`lib/services/attendance/zkteco/zkteco_client.dart:263-305, 342-353, 467-487`):**
   - في `getUsers()`، لا تتم إزالة بادئة الحجم ذات الـ 4 بايت (`possibleSize == data.length - 4`) من بداية البيانات المستقبلة، مما يؤدي إلى إزاحة قراءة سجلات الـ 72 بايت بمقدار 4 بايت، فتُقرأ الـ 4 بايت الأخيرة الفارغة (`0x00000000`) من `userId` للمستخدم السابق على أنها `uid = 0` للمستخدم التالي ويظهر الـ ID صفراً أو تالفاً.
   - وفي `fetchAttendanceReport()`، كانت إزالة الـ 4 بايت تقتصر على `payload.length % 40 == 4` ولا تشمل سجلات الـ 16 أو 8 بايت.

## 1.3 الثوابت الصارمة (Non-Negotiable Domain Invariants)
- **الذرية (Atomicity):** أي عملية ربط بصمة أو دمج سجل مؤقت `موظف <ID>` مع الموظف الفعلي أو حذف موظف يجب أن تتم داخل `db.transaction()` واحدة.
- **عدم تعديل Migrations قديمة:** لا يتطلب هذا الإصلاح أي تغيير في schema قاعدة البيانات؛ تُستخدم الجداول الحالية (`staff_table`, `staff_biometric_mappings`, `attendance_raw_events`, `attendance_table`).
- **حماية سجلات الحضور:** عند نقل حضور من سجل مؤقت `موظف <ID>` إلى الموظف الفعلي، إذا كان للموظف الفعلي سجل في نفس اليوم يُدمج أقرب وقت حضور (`checkInTime`) وأحدث وقت انصراف (`checkOutTime`) دون كسر قيد التفرد أو تكرار الأيام.

---

# 2. عقد التنفيذ المتوازي (Split-Lane Execution Contract)

يتم تقسيم العمل بالتوازي مع النقاش والمراجعة المتبادلة بين:
1. **المسار A (Gemini 3.8 Flash — Production Implementation):** تنفيذ الإصلاحات الإنتاجية في `lib/`.
2. **المسار B (OpenCode `opencode/big-pickle` — Comprehensive Unit Test Suite):** كتابة اختبارات الوحدة والانحدار الشاملة في `test/unit/biometric_employee_link_sync_bug029_test.dart`.
3. **الموديل المفكر (Gemini 4 Argon — Architect):** تنسيق العقود البرمجية بين النموذجين، مراجعة الكود والـ diff، وتشغيل التحقق النهائي.

## 2.1 عقد الدوال الجديدة والمعدلة (Exact API Signatures)

### أ) في `lib/services/attendance/attendance_sync_service.dart`:
إضافة دالة ذرية لربط الموظف برقم البصمة ودمج أي سجل مؤقت `موظف <ID>` وإعادة معالجة البصمات فوراً:
```dart
Future<void> reconcileAndLinkBiometricId({
  required String staffId,
  required String externalUserId,
  String? staffNameOnDevice,
  String? cardNumber,
  int? preferredDeviceId,
})
```
**السلوك المطلوب من `reconcileAndLinkBiometricId`:**
1. تنظيف `externalUserId = externalUserId.trim()`. إذا كان فارغاً لا تفعل شيئاً.
2. تحديد الأجهزة المستهدفة للربط:
   - إذا تم تمرير `preferredDeviceId`، يتم تضمينه، بالإضافة إلى جميع الأجهزة النشطة ذات `connectionType == 'tcp_ip'` (أو جميع الأجهزة النشطة إن لم يوجد `tcp_ip`).
   - إذا لم توجد أي أجهزة في جدول `biometric_devices`، يتم إنشاء جهاز `FILE-IMPORT` افتراضي.
   - إذا وُجدت أجهزة نشطة، يُمنع ربط الموظف بجهاز `FILE-IMPORT` غير نشط فقط وترك جهاز `tcp_ip` النشط بدون ربط.
3. داخل `_deviceDao.attachedDatabase.transaction(() async { ... })`:
   - البحث عن أي ربط حالي لنفس `externalUserId` على جميع الأجهزة (`_deviceDao.getMappingsByExternalIdAllDevices(externalUserId)` أو فحص الأجهزة).
   - لكل جهاز مستهدف (ولكل جهاز كان يحمل ربطاً لنفس `externalUserId` مع سجل مؤقت `موظف $externalUserId` براتب أساسي `0` أو موظف غير نشط/محذوف):
     - إذا كان الربط القديم يشير إلى `oldStaffId != staffId`:
       - فحص `oldStaff = await _staffDao.getStaffById(oldStaffId)`.
       - إذا كان `oldStaff` سجلاً مؤقتاً تلقائياً (`oldStaff.name.trim() == 'موظف $externalUserId'` و `oldStaff.basicSalary == 0`) أو محذوفاً/غير نشط (`oldStaff == null || !oldStaff.isActive || oldStaff.status != 'active'`):
         - نقل سجلات `attendance_table` الخاصة بـ `oldStaffId` إلى `staffId` (إذا لم يكن لـ `staffId` سجل في نفس التاريخ يتم تحديث `staffId`؛ وإذا كان له سجل يتم أخذ أبكر `checkInTime` وأحدث `checkOutTime` وحذف صف `oldStaffId`).
         - تحديث `attendance_raw_events` التي تحمل `matchedStaffId == oldStaffId` و `externalUserId == externalUserId` لتشير إلى `matchedStaffId = staffId`.
         - إذا كان `oldStaff` سجلاً مؤقتاً تلقائياً (`موظف $externalUserId`)، يتم حذفه منطقياً (`_staffDao.deleteStaff(oldStaffId)`).
     - تحديث أو إدراج صف `staff_biometric_mappings` للجهاز المستهدف بحيث يشير `(deviceId, externalUserId)` إلى `staffId` بالحالة `enrollmentStatus: 'enrolled'`.
     - استدعاء `_deviceDao.requeueUnmatchedEventsForExternalId(deviceId, externalUserId)`.
4. بعد انتهاء الـ transaction، استدعاء `processPendingEvents(deviceId)` لكل جهاز متأثر حتى تتحول أي بصمات معلقة/غير مربوطة إلى حضور مسجل فوراً.

### ب) في `lib/services/attendance/attendance_sync_service.dart` (`processPendingEvents` & `syncDevice`):
1. في `processPendingEvents(int deviceId)`:
   - إذا كان `mapping == null` على `deviceId`:
     - قبل استدعاء `_autoCreateStaffForExternalId(deviceId, rawEvent.externalUserId)`، افحص `_deviceDao.getEnrolledMappingByExternalIdAnyDevice(rawEvent.externalUserId)`.
     - إذا وُجد ربط لموظف نشط (`staff != null && staff.isActive && staff.status == 'active'`)، قم بإنشاء ربط `enrolled` لهذا الـ `staff.staffId` على `deviceId` واستخدمه مباشرة!
   - إذا كان `mapping != null` ولكن الموظف المرتبط به `staff == null || !staff.isActive || staff.status != 'active'`:
     - افحص إن كان هناك موظف نشط آخر مربوط بنفس `rawEvent.externalUserId` على أي جهاز؛ إن وُجد، حدّث الربط على `deviceId` ليشير إلى الموظف النشط وعالج البصمة! وإن كان الموظف القديم محذوفاً (`status == 'deleted'`) ولا يوجد موظف آخر، قم بحذف الربط اليتيم وإنشاء موظف تلقائي جديد عبر `_autoCreateStaffForExternalId` بدلاً من إسقاط البصمة للأبد.
   - إذا كان `mapping != null` ويشير إلى سجل مؤقت تلقائي (`staff.name == 'موظف ${rawEvent.externalUserId}' && staff.basicSalary == 0`)، ولكن يوجد موظف نشط آخر مسمّى (غير مؤقت) مربوط بنفس `rawEvent.externalUserId` على جهاز آخر (مثل `FILE-IMPORT`)، قم بدمج وتحويل الربط إلى الموظف المسمّى عبر `reconcileAndLinkBiometricId`!
2. في `syncDevice(BiometricDevice device, ...)`:
   - عند فحص `info = await tcpSource.getDeviceInfo()`:
     - احفظ متغيراً `bool clockAdjusted = false;` وعند تنفيذ `await tcpSource.setDeviceTime(DateTime.now())` اجعل `clockAdjusted = true;`.
     - إذا كان `lastSyncAt != null` وكان `clockAdjusted == true`، أو كان `info.deviceTime != null && lastSyncAt.isAfter(info.deviceTime!.add(const Duration(minutes: 2)))`، أو كان `lastSyncAt.isAfter(DateTime.now().add(_futureCursorTolerance))`:
       صفّر `effectiveSinceBase = null` واستدعِ `_deviceDao.resetDeviceSyncCursor(device.id)` مع إضافة ملاحظة في `notes`.

### ج) في `lib/services/attendance/zkteco/zkteco_client.dart`:
1. إضافة دالة مساعدة `_stripSizePrefixIfPresent(Uint8List data, List<int> recordSizes)` تزيل أول 4 بايت إذا كان `possibleSize == data.length - 4` (أو عندما يكون `data.length % size == 4` و `possibleSize == data.length - 4`).
2. استخدامها في `getUsers()` (مع أحجام `[72, 28]`) وفي `fetchAttendanceReport()` (مع أحجام `[40, 32, 16, 8]`).
3. تحديث `_parse28ByteUser(Uint8List bytes)` لقراءة `PIN2` عند البايتات `24..28` (`view.getUint32(24, Endian.little)`) إذا كانت القيمة `> 0`، وإلا العودة إلى `uid.toString()`.

### د) في `lib/core/database/dao/staff_management_dao.dart`:
- في `deleteStaff(String staffId)`: حذف صفوف `staffBiometricMappings` المرتبطة بـ `staffId` داخل transaction مع تحديث حالة الموظف إلى `'deleted'` حتى لا يظل رقم البصمة محجوزاً لموظف محذوف.

---

# 3. سجل المراجعة والتحقق (Verification Log)

## 3.1 توزيع العمل والنقاش بين النماذج (Multi-Model Collaboration)
1. **الموديل المفكر (Gemini 4 Argon — Architect):**
   - فحص دورة حياة البصمة والموظفين بالكامل وحدد الأسباب الجذرية الخمسة التي تؤدي لظهور صفر (`0`) بعد ربط رقم بصمة الموظف الجديد بالاسم.
   - صاغ عقد الدالة الذرية `reconcileAndLinkBiometricId` وشروط تصفير الكيرسور المستقبلي وتنظيف البادئة ذات الـ 4 بايت في بروتوكول ZKTeco.
   - راجع الكود الناتج من كلا النموذجين المنفذين:
     - راجع ملف الاختبار الناتج من **OpenCode (`opencode/big-pickle`)** (`test/unit/biometric_employee_link_sync_bug029_test.dart`) ووحّد مسارات استيراد `zkteco_client.dart` وحقل `a.date` وخطوات مصافحة الخادم الوهمي `_withFakeZkServer`.
     - راجع تعديلات **Gemini 3.8 Flash** في `lib/` وصحح تمرير `_nameController.text.trim()` في `StaffFormPage._saveForm` وأزال الـ import غير المستخدم في `DeviceUserImportPage`.
2. **المسار A (Gemini 3.8 Flash — Production Implementer):**
   - نفّذ التعديلات الإنتاجية في:
     - `lib/services/attendance/zkteco/zkteco_client.dart` (`_stripSizePrefixIfPresent`, `getUsers`, `fetchAttendanceReport`, `_parse28ByteUser`).
     - `lib/services/attendance/attendance_sync_service.dart` (`reconcileAndLinkBiometricId`, `_mergeStaffAttendanceRecords`, `_isAutoCreatedPlaceholder`, `processPendingEvents`, `syncDevice`).
     - `lib/core/database/dao/staff_management_dao.dart` (`deleteStaff`).
     - `lib/ui/staff/staff_form_page.dart`, `lib/ui/staff/biometric_enrollment_page.dart`, `lib/ui/staff/device_user_import_page.dart`, `lib/ui/staff/unmatched_attendance_page.dart`.
3. **المسار B (OpenCode `opencode/big-pickle` — Free Test Implementer):**
   - أنشأ ملف اختبارات الوحدة والانحدار `test/unit/biometric_employee_link_sync_bug029_test.dart` شاملاً 6 اختبارات تغطي جميع سيناريوهات ربط الموظف الجديد والمزامنة.

## 3.2 نتائج تشغيل الاختبارات (`flutter test`)
```text
00:00 +0: loading G:/development/POS-Offline-Desktop-main/test/unit/biometric_employee_link_sync_bug029_test.dart
...
00:12 +42: All tests passed!
```
شملت الـ 42 اختباراً الناجحة:
- `test/unit/biometric_employee_link_sync_bug029_test.dart` (6 اختبارات جديدة لـ BUG-029)
- `test/unit/attendance_sync_cursor_test.dart` (6 اختبارات)
- `test/unit/attendance_device_engine_test.dart` (21 اختباراً)
- `test/unit/attendance_file_import_test.dart` (9 اختبارات)

