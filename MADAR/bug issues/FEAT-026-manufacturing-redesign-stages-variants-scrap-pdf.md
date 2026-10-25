# FEAT-026 — تحديث موديول التصنيع الشامل: واجهات مودرن، مراحل التصنيع، إنتاج المقاسات، الهالك القابل للبيع، وطباعة التقارير PDF

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **الرقم** | FEAT-026 |
| **العنوان** | تحديث وتطوير موديول التصنيع (Modern Redesign, Multi-stage Routing, Multi-variant Outputs, Sellable Scrap, and PDF Reporting) |
| **النوع** | ميزة جديدة / إعادة تصميم وتطوير موديول |
| **الأولوية** | P1 |
| **الحالة** | resolved |
| **الطلب** | صاحب المشروع |
| **التاريخ** | 2026-10-25 |
| **الفرع** | `integration/all-agents` |

---

## 2. القيمة والسبب التجاري

- **المشكلة التي تم حلها:**
  1. شاشات موديول التصنيع تحتاج إلى مظهر عصري موحد ومتناسق مع شاشات التقارير والصفحة الرئيسية المحدثة في `FEAT-024` مع شريط تنقل سريع وكروت KPI.
  2. في إنشاء أمر التصنيع الداخلي لا يوجد زر سريع لإضافة وصفة جديدة مباشرة (Inline Recipe Creation) إلا في أوامر التشغيل للغير.
  3. غياب تتبع مراحل التصنيع المتعددة (مثل: قص، خياطة/تقفيل، كي وتغليف) داخل أمر التصنيع الواحد والتنقل بينها أو الاستكمال عليها.
  4. عدم دعم خروج عدة مقاسات/ألوان (`ProductVariants`) من نفس الخامة في أمر التصنيع (مثل خروج مقاسات S, M, L, XL لتيشرت من رول قماش) وزيادة أرصدتها المخزنية ذرياً عند إتمام الإنتاج.
  5. عدم التمييز بين الهالك التالف غير القابل للبيع والهالك القابل للبيع (فرز ثاني / بواقي خامات) الذي يمكن تسعيره وبيعه في الكاشير وحسم قيمته من تكلفة الإنتاج.
  6. الحاجة لطباعة تقارير التصنيع (تكاليف، مراحل ومقاسات، خامات، هالك) والوصفات وأذونات الاستلام بصيغة PDF قابلة للمعاينة والطباعة المباشرة.
- **النتيجة المحققة:** موديول تصنيع متكامل، مرن وعصري يدعم المراحل والمقاسات والهالك القابل للبيع واستخراج التقارير الرسمية PDF.

---

## 3. المتطلبات والتحقق (Requirements Verification)

| المتطلب | الحالة | الملاحظات |
|---|---|---|
| ترقية Schema قاعدة البيانات إلى v81 مع جداول المراحل والمخرجات | ✅ مكتمل | تم إنشاء `manufacturing_stages` و `manufacturing_stage_outputs` وترقية `app_database.dart` بنجاح |
| إنشاء `ManufacturingStageDao` لإدارة المراحل والمقاسات | ✅ مكتمل | يدعم `addStage`, `upsertStageOutput`, `createVariantAndAddToStage`, `completeStage` |
| زر "+ إضافة وصفة جديدة" ونظام التسعير والمرحلة الأولى في نافذة الأمر | ✅ مكتمل | متاح للداخلي وللغير، مع خيارات تسعير موسعة ونسبة هامش الربح |
| إدارة المراحل واستكمالها وإضافة مراحل جديدة في تفاصيل الأمر | ✅ مكتمل | شريط مراحل زمني ومسارات لكل مرحلة مع حصر المخرجات والهالك |
| خروج مقاسات متعددة من الخامة وزيادة رصيدها ذرياً في المخزن | ✅ مكتمل | يدعم إضافة مقاسات جديدة أو ربط مقاسات سابقة مع تحديث تلقائي للمخزون |
| دعم الهالك القابل للبيع (`isSellable`) وتحديد سعر البيع التقديري | ✅ مكتمل | تمايز كامل بين التالف والفرز الثاني القابل للبيع مع استرداد التكلفة |
| طباعة التقارير والوصفات وأذونات الاستلام PDF | ✅ مكتمل | عبر `UnifiedPrintService` مع دعم المعاينة A4 وتصدير PDF |
| إعادة تصميم شاشات التصنيع بمظهر Modern UI وكروت KPI وفلاتر سريعة | ✅ مكتمل | لجميع شاشات الأوامر، الوصفات، أذونات الاستلام، والتقارير |
| اختبارات وحدة شاملة لمنع الانحدار | ✅ مكتمل | 4 اختبارات وحدة في `manufacturing_stages_variants_scrap_test.dart` بنسبة نجاح 100% |

---

## 4. الملفات المنفذة والمعدلة

1. **قاعدة البيانات والترحيل (Drift Migrations & DAOs):**
   - `lib/core/database/tables/manufacturing_stages_table.dart`
   - `lib/core/database/tables/manufacturing_orders_table.dart`
   - `lib/core/database/tables/manufacturing_scrap_table.dart`
   - `lib/core/database/dao/manufacturing_stage_dao.dart`
   - `lib/core/database/dao/manufacturing_order_dao.dart`
   - `lib/core/database/dao/manufacturing_scrap_dao.dart`
   - `lib/core/database/app_database.dart` (Schema v81)
   - `lib/core/services/backup_service.dart`

2. **الطباعة وتوليد مستندات PDF:**
   - `lib/core/services/unified_print_service.dart` (BOM card, Receipt note, Manufacturing detailed report)

3. **واجهات المستخدم (Modern Redesign UI):**
   - `lib/ui/manufacturing/widgets/mo_form_dialog.dart`
   - `lib/ui/manufacturing/mo_detail_screen.dart`
   - `lib/ui/manufacturing/mo_list_screen.dart`
   - `lib/ui/manufacturing/bom_list_screen.dart`
   - `lib/ui/manufacturing/customer_material_receipt_list_screen.dart`
   - `lib/ui/manufacturing/reports/manufacturing_reports_screen.dart`

4. **اختبارات الوحدة (Regression Prevention):**
   - `test/unit/dao/manufacturing_stages_variants_scrap_test.dart`

---

## 5. نتائج الاختبار والتحقق (Test Results)

- **اختبارات الوحدة:**
  ```text
  flutter test test/unit/dao/manufacturing_stages_variants_scrap_test.dart
  00:00 +0: Manufacturing Stages, Variants, and Sellable Scrap Tests createOrder with initialStageName inserts initial stage row and sets currentStageName
  00:00 +1: Manufacturing Stages, Variants, and Sellable Scrap Tests addStage appends subsequent stage and updates currentStageName on order
  00:00 +2: Manufacturing Stages, Variants, and Sellable Scrap Tests createVariantAndAddToStage and upsertStageOutput track outputs and update stage totals
  00:00 +3: Manufacturing Stages, Variants, and Sellable Scrap Tests recordScrap supports stage, variant, and sellable scrap (second-choice) recording
  00:01 +4: All tests passed!
  ```
- **التحليل الساكن للكود (Flutter Analyze):**
  - تم فحص جميع ملفات ومجلدات موديول التصنيع وخدمات الطباعة واختبارات الوحدة، والنتيجة: `0 errors, 0 warnings`.

---

## 6. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-25 | Antigravity | فتح التذكرة وبدء التنفيذ (in-progress) |
| 2026-10-25 | Antigravity | اكتمال التنفيذ ونجاح اختبارات الوحدة والتحليل البرمجي (resolved) |
