# BUG-023 — التفعيل يقع على Page Not Found وكود الجهاز المعروض لا يطابق كود الربط

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-023 |
| **العنوان** | بعد نجاح استيراد الرخصة تظهر `Page Not Found` لمسار `/activation-success`، وكود الجهاز المعروض على شاشة التفعيل لا يطابق القيمة التي يربط بها ملف الرخصة |
| **النوع** | Defect / Regression |
| **الأولوية** | P1 حرجة — يمنع تسليم العميل الأول بدون تدخل يدوي |
| **الحالة** | in-progress |
| **الأبلغ** | صاحب المشروع أثناء تجربة تفعيل 100 سنة |
| **تاريخ البلاغ** | 2026-10-20 |
| **تاريخ الاكتشاف** | أثناء تجربة ما قبل التسليم على جهاز المالك |
| **نسخة التطبيق** | 2.3.0+1 |
| **الفرع المتأثر** | `integration/all-agents` + الشجرة المحلية |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الشاشات / المسارات** | `/activation` · `/activation-success` · `/license-info` · `lib/core/router/go_router.dart` |
| **الـ Feature Flag** | لا |
| **الـ Flavors المتأثرة** | كل الـ flavors (مسار الترخيص مشترك) |
| **منطقة حساسة** | ☑ ترخيص |
| **مستوى المخاطرة** | عالٍ — يمس تسليم الترخيص للعميل |

## 3. إعادة الإنتاج (إجباري قبل أي إصلاح)

**الخطوات:**
1. شغّل نسخة release على Windows بدون رخصة مخزّنة.
2. من شاشة التفعيل اضغط «استيراد رخصة من ملف» واختر ملف `.madarlicense` صالحًا.
3. انتظر رسالة «تم تفعيل الترخيص بنجاح» ثم انتقال الراوتر.
4. أعد المحاولة برخصة صادرة بـ`--machine-guid` من `HKLM\SOFTWARE\Microsoft\SQMClient\MachineId`: يظهر «تعذر التحقق… مخصصًا لجهاز آخر» رغم أن الكود المعروض على الشاشة هو ما أُرسل للمُصدر.

**البيئة:** Windows 10/11 · Flutter 3.41.4 عبر FVM · release build · flavor base.

**النتيجة المتوقعة:** بعد الاستيراد ينتقل التطبيق إلى الشاشة الرئيسية بدون أي استثناء، والرخصة تُقبل عندما تكون مربوطة بالكود الظاهر على شاشة التفعيل.

**النتيجة الفعلية:**
```
GoException: no routes for location: /activation-success
```
وتظهر شاشة «Page Not Found» فوق شاشة النجاح. إعادة فتح التطبيق تعمل لأن الرخصة حُفظت بالفعل.

**قابل للتكرار؟** دائمًا.

**الأخطاء أو السجلات:**
> لا توجد بيانات عميل — التجربة على جهاز المالك بملف اختباري.

## 4. السبب الجذري (يُملأ بعد الفحص، قبل الإصلاح)

- **السطحي:** شاشة «Page Not Found» بعد نجاح التفعيل + رفض رخصة مربوطة بالكود الظاهر.
- **الجذري:**
  1. `lib/screens/license/activation_screen.dart:157-168` يعمل `invalidate` لـ`licenseStateProvider` ثم `context.go('/activation-success')`. عندما تُحلّ الحالة إلى `true`، يعيد `lib/app_bootstrap.dart:223-225` بناء `MaterialApp.router` بـ`routerProvider` (الراوتر الرئيسي) بينما موقع الراوتر الحالي ما زال `/activation-success`. هذا المسار موجود فقط في راوتر التفعيل (`app_bootstrap.dart:237-240`) وليس في `lib/core/router/go_router.dart`، فيرمي GoRouter `GoException`. إعادة الفتح تعمل لأن الرخصة أصبحت صالحة قبل بناء الراوتر.
  2. `lib/screens/license/activation_screen.dart:60` يعرض `LicenseManager.generateDeviceFingerprint()` = `HardwareIdService.getHardwareId()` (SHA-256 لاسم الجهاز + الأنوية + `deviceId`)، بينما `lib/services/license_manager.dart:746-754` يتحقق فقط من `machine_guid` (قيمة `deviceId` الخام) أو `install_uuid`. القيمتان مختلفتان، فالكود الذي يقرأه العميل من الشاشة لا يصلح للربط.
  3. زر «استيراد رخصة من ملف» (`activation_screen.dart:396-410`) لم يكن له لون صريح: التطبيق يعمل بـ`ThemeMode.dark` بينما الكارت أبيض، فورث الزر لونًا فاتحًا على خلفية بيضاء وظهر كأنه غير موجود (لقطة 2026-10-20 16:26 تؤكد اختفاء الزر).
- **لماذا لم يمسكه الاختبار الموجود:** لا توجد اختبارات للراوتر (`test/` لا تحتوي أي إشارة إلى `routerProvider`)، واختبارات الترخيص تصدر `machine_guid` مباشرة عبر seam الاختبار ولا تمر بمسار «الكود المعروض».
- **هل هو Regression؟** لا — عيب تصميم منذ إدخال راوتر التفعيل + ترخيص JWT.

## 5. الحل

- **ما تم تغييره:**
  1. في `lib/core/router/go_router.dart` أُضيف حارس في أول `redirect`: أي موقع من راوتر التفعيل (`/activation-success`، `/license-info`) يُعاد توجيهه إلى `/splash` قبل فحص المصادقة/أول تشغيل.
  2. في `lib/services/license_manager.dart` أصبح التحقق يقبل `hardware_id` (البصمة المعروضة) كمعرّف ثالث بجانب `machine_guid` و`install_uuid`، ويُعاد استخدام نفس البصمة في كائن `License` بدل حسابها مرتين.
  3. في `tools/license_issuer.js` أُضيف `--bind hardware|all` و`--hardware-id` لإصدار رخصة موقّعة على الكود الظاهر.
  4. في `lib/screens/license/activation_screen.dart` أُعطي زر الاستيراد لونًا صريحًا (`foregroundColor`/`side` = `blue.shade900`) ليكون مرئيًا على الكارت الأبيض في الثيم الداكن.
- **لماذا هذا هو الجذري وليس العَرَضي:** الحارس يمنع وصول موقع خاص براوتر التفعيل إلى الراوتر الرئيسي بعد التبديل، والربط بالبصمة المعروضة يجعل العقد بين الشاشة والمُصدر واحدًا؛ لم يُخفَ أي استثناء ولم يُضف `try/catch`.
- **ملفات معدّلة:** `lib/core/router/go_router.dart` · `lib/services/license_manager.dart` · `lib/screens/license/activation_screen.dart` · `tools/license_issuer.js` · اختبارات `test/unit/`.
- **بدائل مرفوضة ولماذا:** إضافة `/activation-success` كراوت في الراوتر الرئيسي (يبقي شاشة نجاح مكررة بعد التبديل) · تغيير الشاشة لعرض `machine_guid` الخام (يكسر عقد «بصمة الجهاز» المستخدم في التراخيص القديمة) · ربط `install_uuid` فقط (لا ينجو من إعادة التثبيت).

## 6. الاختبارات والتحقق (إجباري)

| البند | القيمة |
|---|---|
| **اختبار انحدار أُضيف** | `test/unit/router/activation_route_redirect_test.dart` + حالات `hardware_id` في `test/unit/services/license_import_test.dart` |
| **الحالة التي يغطيها** | تحويل `/activation-success` و`/license-info` إلى `/splash` · قبول رخصة مربوطة بالبصمة المعروضة · رفض بصمة مختلفة |
| **الأمر المُنفَّذ** | `flutter test test/unit/router/activation_route_redirect_test.dart test/unit/services/license_import_test.dart test/unit/services/license_issuer_roundtrip_test.dart` |
| **النتيجة الفعلية** | 20/20 نجحت (import + router) · 6/6 نجحت (issuer roundtrip) · CLI `--bind hardware` أصدر ملفًا صالحًا |
| **تحليل ثابت** | `flutter analyze` للملفات المعدّلة: لا أخطاء (3 ملاحظات info قديمة في نفس الملفات) |
| **بناء Drift** | لا يلزم — لا تغيير في الجداول |
| **اختبار يدوي** | بناء release v2.3.0+1 نجح · شاشة التفعيل تعرض الكود `2af9e3eb…62a` = قيمة الرخصة · زر الاستيراد أصبح مرئيًا · استيراد رخصة مربوطة بـ`--bind hardware` والوصول للشاشة الرئيسية بدون `Page Not Found` |

## 7. الأثر الخلفي

- هل يتغير حساب مالي قائم؟ ☑ لا
- هل يلزم Migration؟ ☑ لا — لا تغيير في `schemaVersion` (80)
- هل يلزم تحديث النسخ الاحتياطي؟ ☑ لا
- خطة الرجوع: إعادة `go_router.dart` و`license_manager.dart` إلى الحالة السابقة؛ الرخص القديمة (`machine_guid`/`install_uuid`) تظل مقبولة (التحقق الجديد إضافي فقط).

## 8. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-20 | agent | إنشاء البلاغ وتشخيص السبب الجذري |
| 2026-10-20 | agent | بدء الإصلاح |

---

**إغلاق البلاغ يُشترط:** السبب الجذري موثّق · اختبار انحدار نجح · `flutter analyze` نظيف · الحالة = done · الدمج في `integration/all-agents` تم · المناطق الحساسة تحتاج موافقة صاحب المشروع.
