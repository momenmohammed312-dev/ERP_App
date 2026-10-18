# BUG-001 — manufacturing product picker overflows + no search

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-001 |
| **العنوان** | Product dropdown overflows the dialog/page and has no search |
| **النوع** | Defect |
| **الأولوية** | P2 (مسار أساسي: إنشاء أمر تشغيل للغير بلا حل بديل مريح) |
| **الحالة** | resolved |
| **الأبلغ** | صاحب المشروع |
| **تاريخ البلاغ** | 2026-10-14 |
| **تاريخ الاكتشاف** | أثناء الاختبار (ليس عند عميل) |
| **نسخة التطبيق** | 2.3.0+1 |
| **الفرع المتأثر** | `integration/all-agents` → fix branch `feat/manufacturing-fixes` |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الشاشات / المسارات** | `lib/ui/manufacturing/widgets/mo_form_dialog.dart` · `bom_form_dialog.dart` · `customer_material_receipt_list_screen.dart` |
| **الـ Feature Flag** | لا يوجد |
| **الـ Flavors المتأثرة** | base (الأصل) |
| **منطقة حساسة** | ☑ تصنيع/manufacturing |
| **مستوى المخاطرة** | متوسط (اختيار منتج خاطئ = أمر تشغيل خاطئ، بلا أثر مالي مباشر قبل التنفيذ) |

## 3. إعادة الإنتاج

**الخطوات:**
1. افتح أوامر التصنيع → أمر جديد → نوع الأمر = تشغيل للغير.
2. افتح dropdown المنتج النهائي الموجه للعميل مع منتجات ذات أسماء طويلة.
3. لاحظ خروج النص خارج حدود الحقل/الصفحة، وعدم وجود بحث.

**البيئة:** Windows / Flutter 3.41.4 عبر FVM · base flavor

**النتيجة المتوقعة:** منتقي منتجات محدود العرض + بحث بالاسم/الباركود.
**النتيجة الفعلية:** `DropdownMenuItem(value: p.id, child: Text(p.name))` بلا `isExpanded` ولا ellipsis ولا بحث.
**قابل للتكرار؟** دائمًا

## 4. السبب الجذري

- **السطحي:** نص المنتج يتجاوز عرض الـ dropdown.
- **الجذري:** `mo_form_dialog.dart:387-394` (وأشباهه في `bom_form_dialog.dart:318-337` و`customer_material_receipt_list_screen.dart:563-576`) يعرض كل المنتجات في `DropdownButtonFormField` بلا `isExpanded` ولا `TextOverflow.ellipsis` ولا فلترة. بالمقابل `bom_form_dialog.dart:497-517` يستخدم النمط الآمن (`isExpanded: true` + ellipsis).
- **لماذا لم يمسكه الاختبار الموجود:** لا توجد widget tests لشاشات التصنيع.
- **هل هو Regression؟** لا — علة قديمة في نفس الملف.

## 5. الحل

- **ما تم تغييره:** widget جديد reusable `searchable_product_picker.dart` (بحث + قائمة محدودة الارتفاع + ellipsis) + استبدال الـ dropdown غير المحدود في `mo_form_dialog` و`customer_material_receipt_list_screen`.
- **لماذا هذا هو الجذري وليس العَرَضي:** يعالج مصدر التجاوز (عرض غير محدود + غياب فلترة) لا شكله فقط.
- **ملفات معدّلة:** (`path:line` تُملأ بعد التنفيذ)
- **بدائل مرفوضة ولماذا:** حزمة `dropdown_search` خارجية — ممنوعة ضمنيًا (لا إضافات بلا طلب)؛ `isExpanded` وحده يحل التجاوز لكن لا يضيف البحث المطلوب.

## 6. الاختبارات والتحقق

| 항목 | القيمة |
|---|---|
| **اختبار انحدار أُضيف** | فحص يدوي + `flutter analyze` (لا unit test منطقي هنا؛ الـ picker سلوك UI) |
| **الأمر المُنفَّذ** | عبر `flutter_lock.ps1` |
| **النتيجة الفعلية** | تُسجل بعد التنفيذ |
| **تحليل ثابت** | `flutter analyze` |
| **اختبار يدوي** | اختيار منتج باسم طويل في الوضعين الفاتح/الداكن |

## 7. الأثر الخلفي

- هل يتغير حساب مالي قائم؟ ☑ لا
- هل يلزم Migration؟ ☑ لا
- هل يلزم تحديث النسخ الاحتياطي؟ ☑ لا
- خطة الرجوع (Rollback): revert الـ commit الخاص بالـ issue.

## 8. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-14 | agent | إنشاء البلاغ |
| 2026-10-17 | agent | تم الإصلاح في `618a467` (`feat/manufacturing-fixes`) — widget `searchable_product_picker.dart` جديد + استبدال 3 dropdown؛ analyze نظيف |
