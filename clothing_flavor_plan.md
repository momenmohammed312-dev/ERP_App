# خطة تنفيذ Flavor ملابس (Clothing Distribution) — ERP_App

مرجع كامل لتنفيذ الـ Flavor الجديد الخاص بمركز توزيع الملابس. التنفيذ يجب أن يتم مرحلة بمرحلة (اقرأ `AGENTS.md` قبل التنفيذ).

---

## Phase 0 — Flavor Infra ✅ مكتمل

- [x] إنشاء `lib/main_clothing.dart` — entry point يمرر `Flavor.clothing`.
- [x] تعديل `lib/core/config/app_features.dart`:
  - `isClothingDistribution` → true فقط للـ clothing.
  - `hasManufacturing` → false للـ clothing.
  - `hasStaffManagement` → false للـ clothing.
  - `hasDamagedItems` → false للـ clothing.
  - `hasInlinePurchaseProductCreation` → true للـ clothing.
- [x] تعديل `lib/ui/home/modern_home.dart`:
  - Tab count ديناميكي (6 للملابس بدلاً من 7).
  - تبويب الموظفين مخفي في الملابس.
  - زرار الهالك مخفي في الملابس.
  - فهرس تبويب الكاشير ديناميكي (4 بدل 5 للملابس).
- [x] التأكد أن DB name = `pos_clothing` (موجود مسبقاً).
- [x] التأكد أن عنوان التطبيق = `'POS - ملابس'` (موجود مسبقاً).

---

## Phase 1 — مسار الموردين والمشتريات ✅ مكتمل

### 1.1 تحديث أسعار المنتج عند الشراء
- [x] تعديل `enhanced_purchase_invoice_page.dart` → `_savePurchaseInvoice()`:
  - تحديث `costPrice` بسعر الشراء الفعلي عند كل عملية شراء.
  - تحديث `price` (سعر البيع) إذا حدد المستخدم سعر بيع جديد.
  - الكل داخل transaction ذرية واحدة.

### 1.2 إنشاء منتج جديد أثناء الشراء
- [x] `ProductQuickAddDialog` كان موجوداً بالفعل ✅ (يسمح بإنشاء منتج جديد مباشرة من شاشة الشراء).
- [x] إضافة حقل "سعر البيع" + حقل "نسبة الربح %" + زرار حساب تلقائي.
- [x] تحديث `_saveProduct()` ليحفظ `costPrice` (سعر الشراء) و `price` (سعر البيع) بشكل منفصل.

---

## Phase 2 — مسار العملاء والمبيعات ✅ مراجعة مكتملة

### 2.1 الخصومات
- [x] حقل Discount موجود في `OrderLineItem` ✅ — يعمل على مستوى كل صنف.
- [x] الحسابات صحيحة: `lineTotal = (unitPrice × quantity) - discount + tax` ✅.
- [x] الإجمالي يخصم: `grandTotal = subtotal - totalDiscount + totalTax` ✅.

### 2.2 دورة الدفع الآجل
- [x] اختيار `InvoiceType.credit` يتطلب `customerId` ✅.
- [x] `InvoiceService.createInvoice()` يسجل في `LedgerTransactions` تلقائياً ✅.
- [x] دفعات جزئية مدعومة (`paidAmount` + `creditAmount`) ✅.

---

## Phase 3 — Testing & Rollout

- [ ] بناء التطبيق: `flutter run -t lib/main_clothing.dart --dart-define=FLAVOR=clothing`
- [ ] التأكد أن القائمة الجانبية تعرض فقط (Dashboard, Products, Customers, Suppliers, Cash, Reports).
- [ ] تجربة إنشاء منتج جديد من شاشة المشتريات + التأكد من ظهوره بالكمية والسعر الصحيحين.
- [ ] تجربة التسعير بالنسبة المئوية (نسبة الربح %).
- [ ] تجربة فاتورة بيع آجل بخصم والتأكد من حساب المديونية.
- [ ] التأكد أن الـ base flavor لم يتأثر.
