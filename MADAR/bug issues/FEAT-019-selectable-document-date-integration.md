# FEAT-019 — دمج ميزة اختيار تاريخ الفاتورة (التلقائي افتراضياً + اليدوي) من فرع `feat/invoice-date`

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **الرقم** | FEAT-019 |
| **العنوان** | Integration of selectable document and invoice date (automatic by default + manual picker) |
| **النوع** | ميزة جديدة / دمج فرع ميزة |
| **الأولوية** | P2 |
| **الحالة** | resolved |
| **الطلب** | صاحب المشروع |
| **التاريخ** | 2026-10-18 |
| **الفرع** | `integration/all-agents` |

## 2. القيمة والسبب التجاري

- **المشكلة التي يحلها:** كانت الفواتير وسندات الصرف/القبض وحركات الموردين تسجل بتاريخ اليومية المفتوحة أو الوقت الحالي دون إمكانية اختيار أو تعديل التاريخ يدوياً عند إدخال فواتير سابقة بأثر رجعي، ومزامنة التاريخ مع قيود الدفتر `ledger_transactions` وسجلات المراجعة `audit_logs`.
- **النتيجة المتوقعة:** إتاحة اختيار وتعديل تاريخ الفاتورة/المستند بحرية وسهولة مع بقاء التاريخ التلقائي الافتراضي (`BusinessDateService`) مستمراً دون إجبار المستخدم على التعديل، مع عكس التعديلات ذرياً على حركات الأستاذ والدفتر.
- **لو اتأجل، ما الضرر:** عجز المحاسبين والعملاء عن تسجيل فواتير أو مشتريات تاريخية سابقة بدقة في كشوف الحسابات.

## 3. المتطلبات (Requirements)

**يجب أن يفعل (Must):**
1. عمل Cherry-Pick للـ Commit `a118d2c` من فرع `feat/invoice-date`.
2. الحفاظ على الميزات المضافة في المراحل السابقة (أزرار حذف الفواتير الذرية `FEAT-018` في `purchase_detail_dialog.dart` وجداول العهد `BUG-013` في `backup_service.dart`).
3. التأكد من أن التاريخ الافتراضي في إنشاء الفواتير (`enhanced_new_invoice_page.dart` و `enhanced_purchase_invoice_page.dart`) يبدأ تلقائياً دون إجبار على التعديل، مع تمكين زر الاختيار اليدوي.
4. التأكد من ذرية المعاملات المالية في `DocumentDateService` ومزامنة تواريخ القيود.
5. التحقق عبر `flutter analyze` واختبارات الوحدة `document_date_service_test.dart` و `client_verification_test.dart` و `custody_drawer_cash_test.dart`.

**لا يجب أن يفعل (Out of scope):**
- تعديل أو كسر جداول العهد أو التصنيع أو الترخيص.
- فرض قيود قسرية تمنع تسجيل الفاتورة في يوم مغلق (إظهار تحذير فقط دون منع المستخدم).

## 4. معايير القبول (Acceptance Criteria)

- [x] AC1: دمج `a118d2c` بنجاح دون فقدان أي من أزرار حذف الفواتير والمشتريات `FEAT-018` أو إعدادات النسخ الاحتياطي للعهد.
- [x] AC2: زر اختيار التاريخ متاح ويعمل بسلاسة في شاشات فواتير البيع، فواتير الشراء، سندات الموردين، والمصروفات.
- [x] AC3: التاريخ الافتراضي للفاتورة الجديدة يظل تلقائياً مستنداً لـ `BusinessDateService`.
- [x] AC4: نجاح كافة اختبارات الوحدة (خاصة `document_date_service_test.dart` و `client_verification_test.dart` و `custody_drawer_cash_test.dart`).
- [x] AC5: لا توجد أخطاء في `flutter analyze`.

## 5. الأثر التقني

| البُعد | التقييم |
|---|---|
| **الطبقات المتأثرة** | `lib/core/services/`, `lib/ui/widgets/`, `lib/ui/invoice/`, `lib/ui/purchase/`, `lib/ui/supplier/`, `lib/ui/expense/` |
| **جدول جديد؟** | لا |
| **Migration؟** | لا |
| **المناطق الحساسة** | فواتير، مشتريات، دفتر الحسابات العام `Ledger` (محمية بـ `DocumentDateService`) |
| **Flavors** | الكل (مشترك) |
| **Atomicity** | تحديث التاريخ ذري في `DocumentDateService.updateInvoiceDate` و `updatePurchaseDate` |
| **التراجع** | `git checkout backup-before-invoice-date` |

## 6. خطة التنفيذ والاختبار

**خطوات التنفيذ:**
1. توثيق التذكرة FEAT-019 (هذا الملف).
2. إنشاء Git Tag احتياطي `backup-before-invoice-date`.
3. تنفيذ `git cherry-pick --no-commit a118d2c`.
4. فحص وحل أي تعارضات في الملفات المشتركة.
5. تشغيل `flutter analyze` واختبارات الوحدة.
6. تحديث التذكرة ومزامنتها إلى GitHub و Notion.
7. رفع التغييرات إلى `integration/all-agents`.

## 7. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-18 | Antigravity | فتح التذكرة وبدء التنفيذ (in-progress) |
| 2026-10-18 | Antigravity | دمج التغييرات بنجاح وتمرير كافة الفحوصات والاختبارات (resolved) |
