# BUG-021 — حوكمة ميزة الأصناف المتعددة (Variants) بالـ Flavors وتصفير أخطاء التحليل الساكن

> بلاغ خطأ ومواءمة يوثق حصر ظهور وإدارة الأصناف المتعددة (الألوان/المقاسات) في النكهات المناسبة (نكهة الملابس `clothing`) عبر `AppFeatures` (البند D2)، وتصفير أخطاء التحليل الساكن `flutter analyze` واختبارات نموذج الملابس الأولي `clothing_phase1_test.dart` (البند E1).

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-021 |
| **العنوان** | حوكمة ظهور الـ Variants عبر AppFeatures وتصفير أخطاء التحليل الساكن واختبارات الملابس |
| **النوع** | Defect / Architecture / Code Quality |
| **الأولوية** | P2 متوسطة إلى عالية |
| **الحالة** | resolved |
| **الأبلغ** | فريق التدقيق والتطوير (MADAR Agentic Audit) |
| **تاريخ البلاغ** | 2026-10-20 |
| **الفرع المتأثر** | `integration/all-agents` |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الشاشات / المسارات** | `lib/core/config/app_features.dart`, `lib/ui/product/widgets/product_form.dart`, `test/unit/clothing_phase1_test.dart` |
| **الـ Feature Flag** | `AppFeatures.hasProductVariants` |
| **الـ Flavors المتأثرة** | كافة النكهات (base, vegetable, clothing) |
| **مستوى المخاطرة** | منخفض إلى متوسط (عزل بصري ووظيفي للـ Variants + ضبط اختبارات الوحدة القديمة) |

## 3. وصف المشكلة والأسباب الجذرية

1. **البند D2 (ظهور قسم الأصناف المتعددة في كافة النكهات دون تمييز):**
   - في `lib/ui/product/widgets/product_form.dart`، يتم بناء قسم الأصناف/المقاسات/الألوان `_buildVariantsSection()` في كل الحالات حتى لنكهة سوق الخضار `vegetable` والمحلات الأساسية `base` التي لا تتطلب خيارات ألوان ومقاسات.
   - غياب Feature Flag مركزي في `AppFeatures` باسم `hasProductVariants` يحكم تفعيل القسم حسب النشاط التجاري المحدد للـ Flavor.

2. **البند E1 (أخطاء التحليل الساكن في اختبار الملابس القديم وتراكم التحذيرات):**
   - الملف `test/unit/clothing_phase1_test.dart` كُتب كنموذج أولي قبل اعتماد معمارية `ProductVariants` المنفصلة (الجدول والـ DAO المستقل)، وكان يعتمد على أعمدة قديمة ملغاة في جدول `Products` مثل `isClothing`, `size`, `color`، مما أنتج 9 أخطاء تحليل (`The getter 'size' isn't defined`, `The named parameter 'isClothing' isn't defined`).
   - وجود تحذيرات استيرادات وحقول غير مستخدمة تحتاج إلى تنظيف شامل للوصول إلى `Zero Issues` في المشروع.

## 4. خطة الإصلاح

1. في `lib/core/config/app_features.dart`:
   - إضافة خاصية `hasProductVariants` مفعلة لنكهة `clothing` ومعطلة لسوق الخضار.
   - تأمين قراءة `flavor` في `AppFeatures` بحيث تعود لـ `AppFlavor.fromEnvironment()` إذا لم تكن مهيأة بعد لمنع انهيار الاختبارات.
2. في `lib/ui/product/widgets/product_form.dart`:
   - حجب بناء قسم `_buildVariantsSection()` إذا كانت `AppFeatures.hasProductVariants == false`.
   - ضبط حقل الكمية ليكون متاحاً ومحرراً دائماً في النكهات التي لا تدعم الـ Variants.
3. في `test/unit/clothing_phase1_test.dart`:
   - تحديث الاختبارات لتستخدم بنية `ProductVariants` الحالية و `productVariantDao`، والتأكد من مطابقة جميع الحقول المعتمدة.
4. تنظيف كافة التحذيرات في الكود وصولاً إلى `0 issues found` في التحليل الساكن الشامل.

## 5. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-20 | MADAR Agent | فتح التذكرة بحالة in-progress وبدء تنفيذ الإصلاحات |
| 2026-10-20 | MADAR Agent | إنجاز حوكمة AppFeatures.hasProductVariants وعزل قسم الأصناف بنموذج المنتجات، وتصفير جميع التحذيرات والأخطاء في lib/ واجتياز suite_05 واختبارات الملابس وتحديث الحالة إلى resolved |

## 6. نتائج التحقق والاختبارات

1. **التحليل الثابت (`flutter analyze`):**
   - خلو مجلد `lib/` تماماً من أي أخطاء أو تحذيرات (`0 errors, 0 warnings`).
   - تنظيف كافة الاستيرادات المكررة والحقول غير المستخدمة في `lib/` و `test/`.

2. **حوكمة الأصناف المتعددة بالـ Flavors (البند D2):**
   - قسم `_buildVariantsSection()` يظهر فقط عندما تكون `AppFeatures.hasProductVariants == true` (نكهة الملابس `clothing`).
   - في نكهة سوق الخضار `vegetable` والمحلات الأساسية، يتم حجب قسم الأصناف تلقائياً ويظل حقل الكمية نشطاً ومحرراً وقابلاً للإدخال المباشر.

3. **اجتياز الاختبارات الشاملة:**
   - اجتياز `test/unit/clothing_phase1_test.dart` بنسبة 100%.
   - اجتياز `test/verification/suite_05_product_variants_e2e_test.dart` (6/6) بنسبة 100%.
   - اجتياز `test/unit/attendance_late_minutes_bug020_test.dart` بنسبة 100%.
