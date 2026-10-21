# BUG-019 — تشوهات تحديث التواريخ في DocumentDateService و DocumentDatePicker وسجل التدقيق

> بلاغ خطأ يوثق عيوب تحديث التواريخ المالية (C3, C4, C5, C6, C7, C9) في خدمة DocumentDateService والمنتقي DocumentDatePicker وسجل التدقيق audit_logs.

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-019 |
| **العنوان** | عدم دقة تحديث التواريخ في DocumentDateService وتأثيرها على الدفعات والمصروفات والعهد ومرتجعات المبيعات |
| **النوع** | Defect / Data Integrity / Audit |
| **الأولوية** | P1 حرجة |
| **الحالة** | resolved |
| **الأبلغ** | فريق التحليل والتطوير (MADAR Agentic Audit) |
| **تاريخ البلاغ** | 2026-10-19 |
| **تاريخ الاكتشاف** | أثناء الفحص المعزول لداتابيز العميل وتدقيق كود DocumentDateService |
| **نسخة التطبيق** | 2.3.0+1 |
| **الفرع المتأثر** | `integration/all-agents` |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الشاشات / المسارات** | `lib/core/services/document_date_service.dart`, `lib/ui/widgets/document_date_picker.dart` |
| **الـ Feature Flag** | عام للنظام |
| **الـ Flavors المتأثرة** | كافة النكهات (base, vegetable, clothing) |
| **منطقة حساسة** | ☑ دفتر حسابات ☑ فواتير ☑ نقد/إقفال يوم ☑ عهد مالية |
| **مستوى المخاطرة** | عالٍ (تغيير تواريخ قيود محاسبية ودفعات ومصروفات أخرى بالخطأ وفقدان الأثر الرقابي) |

## 3. إعادة الإنتاج

1. **الخلل C3 (انفصال استرداد المرتجع):**
   - تعديل تاريخ مرتجع مبيعات له استرداد نقدي مسجل في `return_refunds` عبر `updateSalesReturnDate`.
   - النتيجة: يتغير تاريخ المرتجع في `sales_returns` بينما يبقى تاريخ الاسترداد `refundDate` وقيده في الأستاذ كما هو، مما يفصل المرتجع عن حركة الصندوق المحاسبية.
2. **الخلل C4 (تعديل تاريخ تسوية العهدة اللاحقة):**
   - صرف عهدة نقدية في يوم T-10، وتسويتها ورد المتبقي في يوم T-2.
   - تعديل تاريخ صرف العهدة عبر `updateCustodyDate` إلى T-9.
   - النتيجة: الشرط `t.entityType.equals('Custody') & t.refId.equals(custodyId.toString())` يطابق قيد الصرف وقيد التسوية معاً، فيغير تاريخ قيد التسوية إلى T-9.
3. **الخلل C5 (تعديل دفعات متعددة متساوية القيمة):**
   - وجود دفعتين متساويتين (مثلاً 500 ج.م) لنفس الفاتورة بتواريخ مختلفة.
   - تعديل تاريخ إحدى الدفعتين عبر `updatePaymentDate`.
   - النتيجة: الشرط `t.invoiceId.equals(invoiceId) & t.amount.equals(amount)` يحدّث جميع الدفعات المتساوية معاً.
4. **الخلل C6 (تعديل قيود مصروفات أخرى بنفس المبلغ):**
   - تسجيل مصروفين مستقلين بنفس القيمة في نفس اليوم.
   - تعديل تاريخ المصروف الأول عبر `updateExpenseDate`.
   - النتيجة: الشرط الفضفاض `(t.origin.equals('expense') & t.credit.equals(expense.amount) & t.date.equals(oldDate))` ينقل قيد المصروف الآخر أيضاً.
5. **الخلل C7 (ضياع معرفات السجلات النصية في سجل التدقيق):**
   - تعديل تاريخ مستند يحمل معرفاً نصياً (UUID) أو مستخدم نصي.
   - النتيجة: `int.tryParse` يرجع `null` ويفقد سجل التدقيق الربط بالمعرف النصي لعدم تضمين `recordKey` نصياً داخل `oldValue` و `newValue`.
6. **الخلل C9 (السماح بتواريخ مستقبلية غير منطقية):**
   - فتح `DocumentDatePicker` لاختيار تاريخ مستند نقدي.
   - النتيجة: السماح باختيار تاريخ مستقبلي حتى سنة كاملة افتراضياً بدلاً من حظر التواريخ المستقبلية افتراضياً.

## 4. السبب الجذري

- **السطحي:** تشوه تواريخ الحركات المرتبطة وتعديل قيود لم تكن مستهدفة.
- **الجذري:**
  1. `lib/core/services/document_date_service.dart:474`: عدم شمول `return_refunds` وحركات الأستاذ المرتبطة بها في `updateSalesReturnDate`.
  2. `lib/core/services/document_date_service.dart:431`: عدم التمييز بين قيد صرف العهدة (`debit > 0`) وقيد التسوية/الرد (`credit > 0`) في `updateCustodyDate`.
  3. `lib/core/services/document_date_service.dart:370`: استخدام `update(invoicePayments)` بشرط المبلغ ورقم الفاتورة فقط دون استهداف الدفعة المحددة بـ `id`.
  4. `lib/core/services/document_date_service.dart:298`: شرط فضفاض في استعلام `ledgerTransactions` عند تحديث المصروفات.
  5. `lib/core/services/document_date_service.dart`: الاعتماد الحصري على `int.tryParse` لـ `recordId` في `AuditService.log` دون حفظ المعرف النصي `recordKey` في الخرائط.
  6. `lib/ui/widgets/document_date_picker.dart:61`: قيمة `lastDate` الافتراضية تضيف 365 يوماً للمستقبل.

## 5. خطة الإصلاح المنفذة

1. تحديث `updateSalesReturnDate` لتحديث `return_refunds.refundDate` وقيود الأستاذ التابعة لها (`RREF$id` و `%_retref_$id`) وحركات المخزون في المعاملة نفسها مع الحفاظ على `createdAt` دون مساس.
2. تقييد `updateCustodyDate` ليحدّث قيد الصرف فقط (`debit > 0` و `credit == 0.0`) والحفاظ الكامل على قيد تسوية/رد العهدة.
3. تخصيص `updatePaymentDate` لاستهداف الدفعة المطابقة لـ `oldDate` وتحديثها بمعرفها الفردي `id` بدلاً من تحديث كل الدفعات المتساوية.
4. تدقيق `updateExpenseDate` للربط بالمعرف أولاً ثم اختيار قيد يتيم واحد فقط بحذر لتجنب المساس بمصروفات أخرى متزامنة.
5. إضافة `recordKey` و `userId` في `oldValue` و `newValue` في كافة استدعاءات `AuditService.log` (فواتير، مشتريات، مصروفات، دفعات، عهد، مرتجعات).
6. إضافة `allowFutureDates: false` افتراضياً في `DocumentDatePicker` وجعل الحد الأقصى نهاية اليوم الحالي مع حماية الحدود لمنع أي استثناء Flutter.
7. كتابة اختبارات انحدار شاملة في `test/unit/services/document_date_precision_bug019_test.dart`.

## 6. التحقق والاختبارات

تم التحقق بنجاح من كافة الإصلاحات عبر:
1. `test/unit/services/document_date_precision_bug019_test.dart` (6 اختبارات نجحت 100%):
   - C3: updateSalesReturnDate updates return_refunds, ledger transactions, and inventory movements without altering createdAt.
   - C4: updateCustodyDate updates custody issue entry but preserves settlement entry at later date.
   - C5: updatePaymentDate updates ONLY the single matching payment, leaving identical payments untouched.
   - C6: updateExpenseDate updates target expense ledger entry accurately and does not touch other expenses on the same date with same amount.
   - C7: Audit log captures recordKey in oldValue and newValue for UUID and string IDs.
   - C9: pickDocumentDate respects allowFutureDates and caps at end-of-day safely.
2. `test/verification/suite_04_document_dates_test.dart` (5/5 اختبارات نجحت بالكامل).
3. `test/unit/services/business_date_cash_drawer_bug017_test.dart` (3/3 اختبارات نجحت بالكامل).
4. `flutter analyze` أظهر `No issues found!`.

## 7. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-19 | MADAR Agent | فتح البلاغ بحالة in-progress وبدء تنفيذ الإصلاحات |
| 2026-10-19 | MADAR Agent | حل البلاغ بالكامل (resolved) واجتياز كافة اختبارات الانحدار والتحليل بنجاح |
