---
name: erp-fix
description: "تصليح أعطال ERP/POS (فواتير، مخزون، دريفت، كاش) بمنهجية ثابتة. استخدم عند أي بج في المشروع ده."
category: development
risk: safe
source: self
source_type: self
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: erp-fix-chain
  project: pos_offline_desktop
---

# ERP Fix — مجلد التصليح

## ده بتاع إيه؟
نقطة دخول واحدة لأي تصليح في مشروع الـ ERP ده. بدل ما تحتار بين 32 skill، امشي بالترتيب ده.

## Skills المستخدمة (موجودة فعلاً — مش منسوخة)
1. `../bug-hunter/SKILL.md` — التشخيص المنهجي (reproduce → evidence → root cause)
2. `../logic-lens/SKILL.md` — مراجعة منطقية عميقة (9 فئات: null، race، injection، حدود)
3. `../brooks-lint/SKILL.md` — روائح معمارية (DRY، coupling، god files)
4. `../performance-optimizer/SKILL.md` — بطء DB/API (N+1، index، pagination)
5. `../codebase-audit-pre-push/SKILL.md` — فحص أمان + junk قبل الحفظ (الأقسام 4 و 5 فقط)

## Workflow — امشي بالترتيب
### 1. bug-hunter أولاً (إجباري)
- هات خطوات إعادة الإنتاج + رسالة الخطأ + stack trace
- حدد: فاتورة؟ مخزون؟ كاش سيشن؟ يومية؟ تقرير PDF/Excel؟ flavor vegetable ولا base؟
- ممنوع تخمين — اتبع الدليل.

### 2. logic-lens ثانياً (إجباري لكود فلوس/مخزون)
- راجع: null checks على `customerId/supplierId/shipmentId`، type safety على `REAL` للفلوس، race على تحديث الكمية المتزامن، state بعد فشل جزئي.
- أي دالة بتلمس فلوس/مخزون لازم تكون atomic transaction واحدة (حسب `AGENTS.md:6`). لو فيها partial update → REJECT.

### 3. brooks-lint ثالثاً (لو الكود "شغال بس ريحته وحشة")
- هل الكود الجديد كرر DAO موجود؟ هل حط business logic جوه widget بدل DAO/service؟ (ممنوع حسب `AGENTS.md:3`)
- هل كسر flavor system؟ أي `if` مباشر على اسم flavor بدل `AppFeatures` → REJECT.

### 4. performance-optimizer (لو شكوى بطء)
- قيس قبل وبعد. دور على N+1 في `InvoiceItems/LedgerTransactions`، missing index على `WHERE/ORDER BY`، `SELECT *`، غياب pagination في كشوفات كبيرة.

### 5. codebase-audit (فحص أخير)
- secrets؟ SQL concatenation؟ `exec()` بمدخلات يوزر؟ كلمات سر plain؟

## قيود ERP الصارمة (من AGENTS.md — لا تتجاوزها)
- ممنوع تعديل migration step قديم. أي schema جديد = version bump + `onUpgrade` step جديد.
- Soft delete هو الافتراضي (`status = 'Deleted'`)، مش hard delete.
- قبل جدول جديد: دور في `Invoices`, `InvoiceItems`, `InvoicePayments`, `LedgerTransactions`, `expenses_table`, `day_table`, `cash_session_table`. التوسعة أولاً.
- DAO الجديد يمشي على نمط `product_dao.dart` بالظبط: `getAll/watchAll/insert/update/delete`.
- الأصل (base flavor) مايتلمسش إلا بطلب صريح.
- مرحلة واحدة في المرة، واقفل بتأكيد المستخدم.

## Output format
```text
FIX OK / FIX REJECTED
Root cause: ... (ملف:سطر)
Changed: ...
Atomic: yes/no
Migration safe: yes/no
Regression: ...
```

## مثال استخدام
> "استخدم @erp-fix عندي خصم الفاتورة بيتحسب غلط في flavor الخضار"
