---
name: erp-test
description: "تيست ومراجعة ERP/POS (أوفلاين، عربي RTL، عمولة، برنيكة، كاش) بفلاتر صارمة. استخدم قبل أي merge."
category: development
risk: safe
source: self
source_type: self
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: erp-test-chain
  project: pos_offline_desktop
---

# ERP Test — مجلد التيست

## ده بتاع إيه؟
بوابة التيست والجودة لمشروع الـ ERP ده. بتضمن إن أي فيكس أو فيتشر من `erp-fix` مايكسرش فلوس أو مخزون أو migration.

## Skills المستخدمة (موجودة فعلاً — مش منسوخة)
1. `../to add features/style-filter/SKILL.md` — بوابة الستايل ومنع التكرار (FILTER 3)
2. `../to add features/test-filter/SKILL.md` — تيست عدائي + edge cases (FILTER 4)
3. `../to add features/review-filter/SKILL.md` — مراجعة نهائية قبل الدمج (FILTER 5)
4. `../to add features/spec-filter/SKILL.md` — تثبيت المتطلبات بصيغة EARS قبل التيست
5. `../technical-change-tracker/SKILL.md` — تتبع التغييرات بين الجلسات (`planned -> tested -> deployed`)

## Workflow — امشي بالترتيب
### 1. style-filter (إجباري على كل diff)
- التسمية: camelCase / PascalCase / snake_case زي الموجود؟
- DAO ماشي على نمط `product_dao.dart`؟ لا business logic في widgets؟
- لا تكرار: لو دالة شبه helper موجود في `core/utils` أو DAO موجود → `STYLE REJECTED` مع اسم الملف البديل.
- لا `print/debugger/TODO` بدون issue، لا secrets، لا `SELECT *` جديد.

### 2. test-filter (عدائي — حاول تكسر الكود)
Happy path + إجباري ERP edge cases:
- فاضي/صفر: فاتورة بدون أصناف، عميل بدون رصيد، برنيكة `quantityReturned = 0`
- فلوس: خصم 100%، خصم أكبر من الإجمالي، `commission = 0`، أسعار `per_unit/lump_sum/commission`
- مخزون: بيع أكتر من المتاح، `barnikaRemainingCount` سالب، حركتين بيع متزامنتين
- أوفلاين: قطع نت أثناء الحفظ، إعادة فتح بعد crash، DB قديمة تحتاج migration
- عربي RTL: أسماء عربية + أرقام، PDF عربي (`NotoNaskhArabic`)، Excel استيراد/تصدير
- صلاحيات/RBAC: كاشير يحاول يقفل يومية، `test/rbac_*_test.dart` موجودة
- Platform: Windows الأساسي + RTL light/dark

Regression إجباري:
- `test/test_sales_invoices.dart`, `test_sales_invoices`, `test_purchase_supply`, `test_reports`, `test_day_shift`, `barneka_verify_test` لازم تفضل خضرا.
- شغل الموجود في `test/` قبل الدمج، مش بعده.

Manual steps إجبارية: `1... 2... 3...` + النتيجة المتوقعة لكل خطوة.

### 3. review-filter (البوابة الأخيرة)
- Reuse طالع؟ Duplication نازل؟ Diff صغير؟
- Docs اتحدثت؟ Rollback واضح (revert أو feature flag)؟
- Flavor سليم؟ `AppFeatures` هو المرجع الوحيد، مفيش `if (flavor == ...)` متبعتر.
- بس `REVIEW OK` يسمح بالدمج.

### 4. technical-change-tracker (للشغل الطويل)
- سجل كل تغيير: `planned -> in_progress -> implemented -> tested -> deployed`
- احفظ handoff للجلسة الجاية: ملفات ناقصة، blockers، خطوة جاية.

## Output format
```text
STYLE OK / STYLE REJECTED
TEST OK / TEST REJECTED
Cases: x/y pass
Break attempts: ...
Manual steps: 1... 2... 3...
Regression: test_sales_invoices ✓, barneka_verify ✓, rbac ✓
Merge: yes/no + why
```

## مثال استخدام
> "استخدم @erp-test على فيكس خصم الفواتير قبل الدمج"
> "استخدم @erp-test على migration البرنيكة — جرب DB قديمة + RTL + أوفلاين"
