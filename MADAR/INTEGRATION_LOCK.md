# MADAR Integration Lock

- **Branch Locked:** `integration/all-agents`
- **Lock Owner:** Stabilizer Agent (Antigravity)
- **Lock Acquired At:** 2026-10-18 19:47:00 +03:00
- **Purpose:** تثبيت واستقرار فرع integration/all-agents قبل البناء والتسليم (تنفيذ خطة PLAN-integration-stabilization).
- **Rule:** 
  **ممنوع تماماً أي commit أو push مباشر على فرع `integration/all-agents` لأي وكيل آخر عدا المالك.**

## استثناء صريح لوكيل الترخيص (License Agent):
يجب على وكيل الترخيص العمل على فرع منفصل ومستقل (مثال: `fix/license-*` أو فرعه المخصص)، ولا يقوم بعمل push أو merge مباشر إلى `integration/all-agents`. سيتم مراجعة ودمج تعديلاته لاحقاً بواسطة الوكيل المالك فقط بعد انتهاء مراحل التثبيت والتأكد من عدم حدوث تضارب.
