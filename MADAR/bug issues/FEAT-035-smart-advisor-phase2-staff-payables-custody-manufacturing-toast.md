---
id: FEAT-035
title: "Smart Advisor Phase 2: Staff Discipline, Credit Accumulation, Supplier Payables, Custody & Manufacturing Audit with Non-Intrusive Toast"
status: done
type: feature
priority: high
area: erp
created_at: 2026-11-07T21:48:00+02:00
updated_at: 2026-11-07T22:07:00+02:00
tags: [smart-advisor, ai, analytics, hr, suppliers, custody, manufacturing, ui]
---

# FEAT-035: Smart Advisor Phase 2 — Staff, Payables, Operations Audit & Floating Toast

## Business Value
توسيع قدرات المستشار الذكي الهجين (Smart Advisor) ليشمل كافة الأبعاد الحيوية للمنشأة:
1. انضباط الموظفين (تكرار الغياب بدون عذر والتأخيرات المتكررة).
2. متابعة الائتمان وسحب البضاعة للعملاء دون سداد متراكم.
3. مستحقات الموردين المتأخرة لتجنب تعطل الإمداد.
4. الرقابة على العمليات والعهد المفتوحة (عهد مالية معلقة، مراحل تصنيع متأخرة، ورديات نقدية منسية).
5. إشعار عائم راقٍ وغير مزعج (Sleek Non-Intrusive Floating Toast) يظهر تلقائياً دون مقاطعة الكاشير.

## Technical Scope
1. `lib/core/services/smart_analytics/staff_discipline_service.dart`: فحص سجل الحضور والغياب والانضباط للموظفين.
2. `lib/core/services/smart_analytics/supplier_payables_service.dart`: فحص أرصدة الموردين المستحقة وفترة آخر سداد.
3. `lib/core/services/smart_analytics/operations_audit_service.dart`: فحص العهد المفتوحة ومراحل التصنيع العالقة والورديات المفتوحة.
4. تحديث `CustomerRetentionService` لإضافة فحص السحب المستمر بدون سداد `credit_stagnation`.
5. تحديث `SmartAdvisorService` لتنسيق الخدمات الجديدة وإرجاع التنبيهات المحدثة.
6. `lib/ui/notifications/widgets/smart_floating_toast.dart`: تصميم التوست العائم الأنيق بدون أيقونات مزعجة.
7. تحديث `modern_home.dart`، `smart_notifications_screen.dart`، و `smart_analytics_report_page.dart`.
8. كتابة اختبارات وحدات شاملة في `test/unit/services/smart_analytics_realistic_test.dart` (10/10 اختبارات ناجحة 100%).

## Acceptance Criteria
- [x] رصد غياب الموظف (يومين متتاليين أو 3 أيام متفرقة بدون عذر) وتكرار التأخير (≥3 مرات).
- [x] رصد العميل الساحب لبضاعة بدون سداد منذ ≥ 14 يوماً.
- [x] رصد مستحقات الموردين المتأخرة منذ ≥ 15 يوماً.
- [x] رصد العهد المالية المفتوحة منذ أكثر من 3 أيام ومراحل التصنيع المعلقة.
- [x] ظهور التوست العائم بهدوء في الشاشة الرئيسية واختفاؤه تلقائياً.
- [x] تجاوب الشاشات وتوافقها التام مع الثيم الفاتح والداكن (Light & Dark).
- [x] اجتياز كافة الاختبارات الآلية بنسبة 100%.
