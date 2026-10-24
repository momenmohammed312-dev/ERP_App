# FEAT-017 — تثبيت وحفظ لينك صفحة المحل (QR Code) وإعدادات ملصق الباركود تلقائياً

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **الرقم** | FEAT-017 |
| **العنوان** | Persist and save shop page URL (QR Code) and barcode label settings automatically |
| **النوع** | تعديل سلوك قائم / تحسين تجربة المستخدم |
| **الأولوية** | P2 |
| **الحالة** | resolved |
| **الطلب** | صاحب المشروع |
| **التاريخ** | 2026-10-18 |
| **الفرع** | `integration/all-agents` |

## 2. القيمة والسبب التجاري

- **المشكلة التي يحلها:** عند كتابة أو تعديل لينك صفحة المحل أو خيارات طباعة الباركود (إظهار QR، إظهار السعر، اسم المحل) في شاشة `LabelPrintPage`، لا يتم حفظها في `SettingsService` مما يؤدي لفقدان اللينك والإعدادات عند إعادة فتح الصفحة، ويضطر المستخدم لإعادة كتابته في كل مرة.
- **النتيجة المتوقعة:** حفظ لينك صفحة المحل فور كتابته أو عند الطباعة، وتذكر خيارات إظهار QR وإظهار السعر واسم المحل باستمرار عبر `SettingsService` و `SharedPreferences`.
- **لو اتأجل، ما الضرر:** تجربة مستخدم سيئة وتكرار إدخال الروابط يدوياً وإهدار الوقت عند طباعة الباركود في كل جلسة.

## 3. المتطلبات (Requirements)

**يجب أن يفعل (Must):**
1. إضافة مفاتيح ودوال `getLabelShowQr()`, `setLabelShowQr(bool)`, `getLabelShowPrice()`, `setLabelShowPrice(bool)` إلى `SettingsService`.
2. استرجاع وحفظ إعدادات الباركود (`_showPrice`, `_showQr`, `_pageUrlCtrl`, `_companyCtrl`) في `LabelPrintPage` تلقائياً عند التعديل وعند بدء الطباعة.
3. تفعيل الـ QR تلقائياً عند وجود لينك محفوظ لأول مرة، مع تمكين المستخدم من حفظ وتغيير اللينك بسلاسة.
4. تحسين حقل `_pageUrlController` في شاشة الإعدادات `lib/ui/setting/settings.dart` وإضافة نص توضيحي وتفعيل خيار الـ QR تلقائياً عند حفظ اللينك من الإعدادات.
5. تغطية السلوك باختبار وحدة آلي شامل `test/unit/label_qr_settings_test.dart`.

**لا يجب أن يفعل (Out of scope):**
- تعديل بنية الجداول أو Drift schema (تعتمد الميزة كلياً على `SettingsService` و `SharedPreferences`).
- تعديل مكتبات توليد الباركود أو PDF.

## 4. معايير القبول (Acceptance Criteria)

- [x] AC1: استدعاء `SettingsService.setLabelShowQr` و `SettingsService.getLabelShowQr` يحفظ ويسترجع حالة إظهار الـ QR.
- [x] AC2: استدعاء `SettingsService.setLabelShowPrice` و `SettingsService.getLabelShowPrice` يحفظ ويسترجع حالة إظهار السعر (افتراضي true).
- [x] AC3: شاشة `LabelPrintPage` تسترجع `pageUrl` و `_showPrice` و `_showQr` تلقائياً من الإعدادات في `_init()`.
- [x] AC4: تعديل `_companyCtrl` أو `_showPrice` أو `_showQr` أو `_pageUrlCtrl` في `LabelPrintPage` يحفظ التغييرات فوراً وفي دالة `_print()`.
- [x] AC5: حفظ لينك الصفحة في شاشة الإعدادات العامة يفعل `setLabelShowQr(true)` تلقائياً مع توضيح الهدف للمستخدم.
- [x] AC6: اختبار الوحدة `test/unit/label_qr_settings_test.dart` يمر بنجاح ويثبت ثبات البيانات عبر استدعاءات متعددة.

## 5. الأثر التقني

| البُعد | التقييم |
|---|---|
| **الطبقات المتأثرة** | `lib/core/services/settings_service.dart`, `lib/ui/product/labels/label_print_page.dart`, `lib/ui/setting/settings.dart` |
| **جدول جديد؟** | لا (استخدام SharedPreferences عبر SettingsService) |
| **Migration؟** | لا |
| **المناطق الحساسة** | لا |
| **Flavors** | الكل (مشترك) |
| **Atomicity** | غير متعلق بالمعاملات المالية/المخزنية |
| **التراجع** | revert git commit |

## 6. خطة التنفيذ والاختبار

**خطوات التنفيذ:**
1. توثيق التذكرة FEAT-017 (هذا الملف).
2. إضافة دوال `getLabelShowQr`, `setLabelShowQr`, `getLabelShowPrice`, `setLabelShowPrice` في `SettingsService`.
3. تعديل `LabelPrintPage` لتحميل وحفظ الإعدادات تلقائياً.
4. تعديل شاشة الإعدادات `SettingsScreen` لدعم حفظ واستقرار رابط الصفحة وتفعيل QR ملصق الباركود تلقائياً.
5. كتابة اختبار الوحدة `test/unit/label_qr_settings_test.dart` وتشغيل التحليل والاختبار عبر `G:\development\flutter_lock.ps1`.
6. مزامنة التذكرة وإجراء commit و push إلى `integration/all-agents`.

## 7. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-18 | Antigravity | فتح التذكرة وبدء التنفيذ (in-progress) |
| 2026-10-18 | Antigravity | اكتمال التنفيذ ونجاح كافة الاختبارات وإغلاق التذكرة (resolved) |
