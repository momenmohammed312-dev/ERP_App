# PLAN — تثبيت فرع integration/all-agents قبل البناء والتسليم

- **التاريخ:** 2026-10-18
- **المستلم:** وكيل تنفيذ (غير كاتب الخطة)
- **الفرع المستهدف:** `integration/all-agents` (آخر commit معروف: `0589d03`)
- **Tag احتياطي موجود:** `backup-integration-20261018-1915` → `0f75be5`
- **المرجع الإلزامي:** `AGENTS.md`، `MADAR/SOP/SOP-01`، `MADAR/SOP/SOP-02`

---

## 0. حدود ممنوع تجاوزها (اقرأها الأول)

### 0.1 منطقة الترخيص — مملوكة لوكيل آخر يعمل الآن
**ممنوع لمس/تعديل/restore/checkout لأي من:**
- `lib/services/license_manager.dart`
- `lib/services/secure_license_storage.dart`
- `lib/services/online_license_service.dart`
- `lib/services/hardware_id_service.dart`
- `lib/config/license_config.dart`
- `lib/core/provider/license_provider.dart`، `lib/core/services/periodic_license_validator.dart`
- `lib/screens/license/**`، `lib/widgets/license/**`، `lib/screens/splash_screen.dart`
- `test/services/license_*`، `test/unit/services/license_*`، `test/unit/services/legacy_license_bridge_test.dart`، `test/unit/services/installer_license_persistence_test.dart`
- `installer/**`، `reset_license_and_run.bat`، `tools/gen_year_license.dart`، `tools/license_simulator.js`
- `*_test_license.json` (basic/standard/professional)
- التذاكر: BUG-007، BUG-009، BUG-015، FEAT-011..016

لو أي خطوة هنا احتاجت تلمس ملف من دول → **وقف واسأل المستخدم.** اختبارات الترخيص الفاشلة **تتسجّل فقط** في التقرير ولا تُصلَح.

### 0.2 قواعد عامة
- كل أوامر flutter/dart **واحد واحد** عبر:
  `powershell -ExecutionPolicy Bypass -File G:\development\flutter_lock.ps1 -Cmd "<الأمر>"`
  (ملحوظة: `fvm` غير متاح داخل الـ lock → استخدم `flutter` مباشرة.)
- ممنوع: `git stash`، `reset --hard`، `push --force`، حذف فروع، تعديل `main` مباشرة، تعديل migration step قديم.
- ممنوع DB حقيقية. نسخ فقط داخل `scratch/`، وممنوع commit لأي `.sqlite`.
- ممنوع نسخ بيانات عملاء (أسماء/هواتف/باركود/مفاتيح) لأي ملف تذكرة أو اختبار.
- أي تعديل في `lib/` يحتاج تذكرة في `MADAR/bug issues/` أولاً + اختبار انحدار.
- بعد إنشاء/تحديث أي تذكرة: شغّل سكريبت المزامنة (بعد إصلاحه — المرحلة D).
- **لا تقفل مرحلة من نفسك:** اعرض النتيجة واستنى تأكيد المستخدم قبل المرحلة التالية.

---

## المرحلة A — الفرع والعملية

### A1. قفل الكتابة على integration (وكيل واحد)
**المشكلة:** commit `f29983a` (وكيل الترخيص) دخل بين `24ebd72` و`0589d03` أثناء شغل وكيل آخر.
**الخطوات:**
1. أنشئ ملف `MADAR/INTEGRATION_LOCK.md` فيه: اسم الوكيل المالك، الوقت، الغرض، "ممنوع commit على integration لغير المالك".
2. **استثناء صريح:** وكيل الترخيص يشتغل على **فرع خاص** (مثلاً `fix/license-*`) ويُدمج لاحقاً بواسطة المالك فقط. أبلغ المستخدم بالنص ده عشان يوصّله لوكيل الترخيص.
3. قبل كل commit/push: `git fetch origin && git log --oneline HEAD..origin/integration/all-agents` — لو فيه جديد → وقف واسأل.
**معيار القبول:** الملف موجود ومُعتمد من المستخدم، ولا commit غريب يظهر بعدها.

### A2. مراجعة الـ push اللي حصل قبل التحقق البصري
**المشكلة:** `integration/all-agents` اتعمله push لـ origin قبل خطوة التشغيل البصري.
**الخطوات:**
1. `git log --oneline -6 origin/integration/all-agents` وسجّل الـ SHAs.
2. لا revert ولا force. فقط سجّل في التقرير أن الـ remote "غير متحقق بصرياً" لحد ما المرحلة C6 تنجح.
3. أنشئ tag جديد قبل أي تعديل: `git tag backup-integration-<YYYYMMDD-HHMM>` على HEAD الحالي.

### A3. تنظيف الشجرة
الحالة الحالية (`git status`):
| الملف | القرار |
|---|---|
| `assets/logo/app_logo_vegetable.png` (محذوف) | **حذف مقصود من المستخدم** → `git rm assets/logo/app_logo_vegetable.png` ثم commit. قبلها: `git grep -n "app_logo_vegetable"` — لو في مرجع في `pubspec.yaml` أو `lib/` → اعرضه على المستخدم قبل الـ commit (المرجع لازم يتشال أو يتغيّر، وده يخص flavor الخضار → ممنوع لمس base بدون إذن). |
| `AGENTS.md` (معدّل) | اعرض `git diff AGENTS.md` على المستخدم. **لا restore ولا commit بدون رده.** |
| `*_test_license.json` | **منطقة الترخيص → لا تلمسها.** سجّلها في التقرير فقط. |
| `test/fixtures/test_purchase_invoices.json`، `test_sales_invoices.json` | `git diff` — لو التغيير timestamps/ناتج تشغيل اختبار → `git restore`. لو تغيير بيانات فعلي → اسأل. |
| `*_test_results.json` (untracked في الجذر) | نواتج اختبارات → أضفها لـ `.gitignore` في commit مستقل `chore(repo): ignore generated test result files` (نفس نمط `f84a52d`). |
| `scratch/`، `.agents/` | لا تلمسها. تأكد إن `scratch/` في `.gitignore`؛ لو لأ → أضفه. |

**معيار القبول:** `git status` يظهر فقط ملفات منطقة الترخيص + `AGENTS.md` (لحين قرار المستخدم).

---

## المرحلة B — الكاش والفلوس [MONEY] (منطقة حساسة)

### B1. نقل إصلاح BUG-013 (عهدة الدرج) من release/v1
**المشكلة:** الإصلاح موجود فقط في `release/v1` commit `bf3d486` (`fix(cash): include custody movements in expected drawer cash`)، والفرع ده متفرع قبل دمج التصنيع والترخيص.
**الخطوات:**
1. اقرأ `MADAR/bug issues/BUG-013-day-close-ignores-custody-cash.md` و`BUG-012-day-close-ignores-cash-refunds.md` و`scratch/bug4_design.md` (لو موجود).
2. `git show --stat bf3d486` — سجّل الملفات. لو فيه أي ملف من منطقة الترخيص → وقف.
3. Tag احتياطي ثم: `git cherry-pick -x bf3d486`.
4. **لو تعارض** (متوقع في `lib/core/services/business_date_service.dart` أو ما يعادله):
   - لا تختار جانب أعمى. الصيغة الصحيحة النهائية:
     `expected = opening + نقد الفواتير + تحصيلات − مصروفات − استردادات نقدية − صرف العهد + رد/تسوية العهد`
   - لازم إصلاح الاسترداد النقدي (BUG-012) يفضل موجود.
   - لا تحسب مصروف العهدة مرتين لو بيتكتب كمان في `expenses`.
   - لو مش متأكد → `git cherry-pick --abort` واسأل.
5. شغّل واحد واحد:
   - `flutter test test/unit/<custody_drawer_cash_test>.dart` (حدد المسار بـ `git show --stat bf3d486`)
   - `flutter test test/unit/<return_refund_test>.dart`
   - كل اختبارات الدرج/الإغلاق الموجودة (`git ls-files test | Select-String "day_close|cash_session|drawer|business_date"`).
6. حدّث BUG-013 بالـ commit الجديد + مزامنة.
**معيار القبول:** cherry-pick مدموج، كل الاختبارات المذكورة خضراء، الصيغة متطابقة مع التصميم.

### B2. تحقق رقمي على نسخة DB العميل
1. انسخ `scratch/client_test.sqlite` → `scratch/client_verify_<date>.sqlite` (لا تستخدم الأصل).
2. احسب `getExpectedCash` لآخر يوم قبل/بعد B1 (عبر اختبار مؤقت في `test/` يفتح النسخة read-only، لا يُعمل له commit لو فيه مسار DB حقيقي).
3. المتوقع: الفرق = صافي حركات العهدة (العهدة المفتوحة CUST-000003 بـ 300 حسب تقرير سابق — تحقق بنفسك).
4. سجّل الأرقام فقط (بدون أسماء عملاء) في التقرير.

### B3. مراجعة [MONEY] لكود التصنيع المدموج
**النطاق:** commits `dd91c42..85068fb` (دمج `24ebd72`).
**ركّز على:**
- `lib/core/database/dao/manufacturing_order_dao.dart` — BUG-008: الاستهلاك التلقائي لعهدة نفس المنتج عند الإكمال. تأكد:
  - كل حركة رصيد + ledger داخل `transaction` واحدة.
  - لا خصم مزدوج (issued_to_order + delivered).
  - لا رصيد سالب؛ نقص الرصيد يلغي العملية كلها (zero writes).
  - إلغاء/عكس أمر مكتمل يرجّع الرصيد.
- `bom_dao.dart` — تخفيف قاعدة OQ6 (raw_material كمنتج نهائي): هل بيفتح باب تقييم مخزون غلط في الأوامر الداخلية (`internal`)؟
- `customer_material_receipt_list_screen.dart` — إنشاء منتج عهدة on-the-fly (FEAT-006): هل بيتعمل له حركة مخزون مصنع بالغلط؟
- `unified_print_service.dart` — طباعة فقط، تأكد إنه read-only.
**المخرج:** `scratch/money_review_manufacturing.md`: لكل نقطة `file:line` + آمن/خطر + اختبار يثبت. أي خطر → تذكرة BUG جديدة (لا إصلاح بدون موافقة).

---

## المرحلة C — الجودة والتحقق

### C1. أخطاء compile في الاختبارات
- `test/unit/clothing_phase1_test.dart` فيه 9 errors (`isClothing`، `Product.size/color` غير موجودين على integration — الميزة غير مدموجة).
- **القرار المقترح (يحتاج موافقة):** لا تحذف الملف. علّمه بـ `@Skip('clothing flavor not merged into integration')` في أعلاه، **أو** استبعده من التشغيل الشامل. لا تعديل في `lib/` لإرضائه.

### C2. تحليل زيادة analyze من 78 إلى 106
1. `git checkout` ممنوع على الشجرة الرئيسية → استخدم worktree مؤقت:
   `git worktree add G:\development\wt_analyze_base 0f75be5` ثم analyze هناك وفي integration.
2. احفظ الناتجين في `scratch/analyze_before.txt` و`scratch/analyze_after.txt` وقارن (sort + diff).
3. صنّف كل issue جديدة: error / warning / info، ومصدرها (ملفات التصنيع غالباً).
4. **المسموح:** infos فقط. أي error/warning جديد في `lib/` → تذكرة.
5. احذف الـ worktree المؤقت بعدها (`git worktree remove`).

### C3. Baseline موثوق — كل ملف لوحده
1. من `G:\development\POS-Offline-Desktop-main` (المسار الصحيح) فقط.
2. `git ls-files "test/**/*_test.dart"` → قائمة.
3. لكل ملف: `flutter test <file>` عبر الـ lock، سجّل: pass/fail/skip، العدد، أول سطر خطأ.
4. اكتب سكريبت PowerShell في `scratch/run_all_tests.ps1` يلف على القائمة ويكتب `scratch/baseline_<date>.md` (جدول).
5. صنّف الفاشل:
   - (أ) منطقة الترخيص → "يخص وكيل الترخيص" فقط.
   - (ب) clothing / flavor غير مدموج.
   - (ج) RBAC قديم.
   - (د) regression حقيقي من الدمج → تذكرة.
6. **ممنوع الاعتماد على أي أرقام سابقة** (من الوكلاء أو التقارير القديمة) — أرقام هذه الخطوة فقط.

### C4. Schema و migrations
1. `Select-String -Path lib/core/database/app_database.dart -Pattern "schemaVersion"` — سجّل الرقم.
2. قارن مع `0f75be5` و`a064053`: `git show <sha>:lib/core/database/app_database.dart | Select-String schemaVersion`.
3. `git diff a064053..HEAD -- lib/core/database/app_database.dart lib/core/database/tables/` — هل التصنيع أو الترخيص زوّد جداول/أعمدة/steps؟
4. **لو الرقم زاد:**
   - انسخ نسخة DB العميل (v78) → `scratch/client_migrate_<date>.sqlite`.
   - اختبار في `test/unit/` يفتح النسخة بـ `AppDatabase` ويشغّل الترقية.
   - قارن `SELECT COUNT(*)` لكل جدول قبل/بعد → لازم تتطابق (أو تزيد فقط في جداول جديدة).
   - `PRAGMA foreign_key_check` و`PRAGMA integrity_check` = ok.
5. **لو الرقم ما زادش:** تأكد إن مفيش عمود جديد في `tables/` بدون migration (`.g.dart` محدّث؟ شغّل `dart run build_runner build --delete-conflicting-outputs` في worktree مؤقت وقارن الـ diff — لو فيه فرق → تذكرة).

### C5. Build
1. `flutter analyze` (يُقبل فقط ما تم تصنيفه في C2).
2. `flutter build windows --release` من `integration/all-agents` — **مش** من `release/v1`.
3. سجّل: نجح/فشل + السبب + مسار الـ exe + حجمه.
4. **شرط مسبق:** وكيل الترخيص يكون خلّص ودمج (أو المستخدم وافق صراحة على البناء بدونه).

### C6. اختبار على جهاز حقيقي (أهم خطوة)
**قبل أي تثبيت:** احتفظ بنسخة من الـ exe القديم + نسخة من DB العميل + نسخة من `secure_license.dat` في مكان خارج مجلد التطبيق.
| السيناريو | المتوقع |
|---|---|
| تثبيت فوق جهاز مرخّص | يفتح بدون طلب تفعيل (**يعتمد على إصلاح وكيل الترخيص**) |
| ترخيص صالح | يعمل |
| ترخيص منتهي | يقفل (انتهاء صارم — قرار المستخدم مطلوب) |
| بدون نت | يعمل بالـ lease/المحلي |
| إقفال يوم فيه عهدة + استرداد | الدرج المتوقع = الصيغة في B1 |
| backup ثم restore على نسخة DB | عدد الصفوف متطابق، الأمر MO وإذن الاستلام سليمين |
| شاشة MO + إذن استلام + PDF كارت التصنيع | تفتح وتطبع بالعربي RTL |
**المخرج:** `scratch/device_test_<date>.md` مع لقطات شاشة.

---

## المرحلة D — خارج الريبو

### D1. إصلاح سكريبت المزامنة
**المشكلة:** وكيل سابق عدّل `C:\Users\Momen\.gemini\config\scripts\sync_bug_to_github_and_notion.ps1` (منطق قراءة `Status`) بدون إذن. النتيجة: BUG-001، BUG-004، BUG-005، FEAT-002، FEAT-003 **اتفتحوا تاني** على GitHub (#2، #3، #4، #5، #6) لأن حالتهم مكتوبة في جدول `| done |`، والمنطق الجديد بيقرا سطر `Status:` الأول ويتجاهل الجدول.
**الخطوات:**
1. اعرض على المستخدم الـ diff الحالي للسكريبت (السطور ~128-140).
2. الإصلاح المقترح: يدعم الصيغتين بأولوية واضحة:
   - لو فيه سطر `- Status:` / `- **Status:**` → استخدمه.
   - وإلا جدول القسم 1 (`| done |`، `| resolved |`، ...).
   - كلمات الإغلاق: `done|resolved|fixed|closed`.
3. **بعد موافقة المستخدم فقط** نفّذ، ثم شغّل `-File` على تذكرة واحدة (BUG-001) وتأكد إن #2 رجع `closed`، ثم `-All`.
4. تحقق نهائي: #2..#15 حالتهم مطابقة لملفاتهم.

---

## المرحلة E — تنظيف (بعد نجاح C6 فقط)

### E1. نسخ DB العميل
1. حصر: `Get-ChildItem G:\development -Recurse -Include client_copy*,client_test*,*.sqlite -ErrorAction SilentlyContinue` داخل كل worktree.
2. اعرض القائمة على المستخدم. **الحذف لا يُسترجع → موافقة صريحة.**
3. احتفظ بنسخة واحدة مشفّرة/خارج الريبو لو المستخدم طلب.
4. تأكد إن مفيش `.sqlite` متتبَّع: `git ls-files "*.sqlite"` = فاضي.

### E2. دمج fix/backup-custody في main
1. `git log --oneline main..fix/backup-custody` + `git diff --stat`.
2. في worktree منفصل على main: `git merge --no-ff fix/backup-custody` → اختبارات backup/restore واحد واحد.
3. **لا push لـ main بدون موافقة المستخدم.**

### E3. Worktrees قديمة
- `git worktree list` → اعرض القائمة (wt_demo، wt_tests، wt_verify، wt_release، wt_manufacturing_fixes...). لا حذف بدون موافقة.

---

## خارج النطاق (لاحقاً — لا تبدأها)
- كل ما يخص الترخيص (وكيل آخر).
- `feat/invoice-date`، إصلاحات الـ demo (BUG-1/2/5 + compile errors)، المحاسبة والموظفين، قرار RBAC.
- تفعيل بوابة الترخيص (BUG-015) قبل الطيار.

## الترتيب المطلوب
`A1 → A2 → A3 → B1 → B2 → C1 → C2 → C3 → C4 → B3 → D1 → [انتظار وكيل الترخيص] → C5 → C6 → E1 → E2 → E3`

## التقرير النهائي المطلوب (`scratch/stabilization_report.md`)
1. SHAs لكل commit اتعمل + الـ tags.
2. نتيجة cherry-pick وحل التعارض (لو حصل).
3. جدول الـ baseline الكامل + التصنيف.
4. schemaVersion قبل/بعد + نتيجة الترقية.
5. analyze قبل/بعد + تصنيف الفرق.
6. نتائج مراجعة [MONEY] + التذاكر الجديدة.
7. نتيجة البناء والاختبار على الجهاز.
8. ما لم يُنفّذ وسببه.
