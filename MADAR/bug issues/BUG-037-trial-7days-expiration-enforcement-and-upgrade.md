# BUG-037 — انتهاء التجربة لمدة 7 أيام لا يوقف التطبيق ويخفي العداد

> مبنية على `_template-bug.md`.
> المرجع في Notion Tasks: `BUG-TRIAL-7DAYS` (صفحة `41cac9ca-77d5-81b5-8ba8-eb9550821114`).
> **الحالة: `review`** — أُصلح ومُتحقَّق آلياً (`209/209` اختبار ناجح، و`flutter analyze` نظيف بدون أي ملاحظات). متبقٍّ اختبار يدوي على نسخة التجربة ورفعها بعد التثبت.

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-037 |
| **العنوان** | بعد انتهاء الفترة التجريبية (7 أيام)، يختفي عداد الأيام بالكامل ويظل التطبيق يعمل بدون تحويل للتفعيل |
| **النوع** | Security / Defect (تجاوز ترخيص + سلوك واجهة خاطئ) |
| **الأولوية** | **P1** (أولوية Notion: `P0` / ميثاق `SOP-01 §D`: تجاوز ترخيص) |
| **الحالة** | `review` |
| **الأبلغ** | صاحب المشروع (Notion Tasks: `BUG-TRIAL-7DAYS`) |
| **تاريخ البلاغ** | 2026-11-18 |
| **تاريخ الاكتشاف** | بعد تشغيل نسخة تجريبية لمدة 7 أيام على جهاز عميل |
| **نسخة التطبيق** | 2.3.0+1 (`pubspec.yaml:6`) |
| **الفرع المتأثر** | `integration/all-agents` |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الشاشات / المسارات** | `lib/config/license_config.dart` · `lib/services/license_manager.dart` · `lib/services/license_entitlement.dart` · `lib/core/provider/license_provider.dart` · `lib/core/router/go_router.dart` · `lib/screens/splash_screen.dart` · `lib/screens/license/activation_screen.dart` · `lib/screens/license/license_info_screen.dart` · `lib/widgets/license/feature_guard.dart` · `lib/ui/home/modern_home.dart` · `lib/ui/setting/settings.dart` · `lib/app_bootstrap.dart` · `build_release.ps1` |
| **الـ Feature Flag** | مستقل عن `AppFeatures`؛ يرتبط بمتغيرات البناء `FREE_VERSION` و `FREE_TRIAL_DAYS` |
| **الـ Flavors المتأثرة** | الكل (`base` / `all` / `vegetable` / `clothing`) وعلى منصتي Android و Windows |
| **منطقة حساسة** | ☑ **ترخيص** |
| **مستوى المخاطرة** | **عالٍ** |

> ⚠️ **قاعدة إيقاف:** منطقة حساسة (ترخيص) ⇒ لا تُمس بيانات العميل أو `secure_license.dat` بالتدمير · اختبار انحدار إجباري في `test/unit/services/` · بقاء الحالة على `review` حتى موافقة صاحب المشروع قبل الدمج/الإغلاق.

## 3. إعادة الإنتاج (قبل الإصلاح)

**البيئة:** بناء Android أو Windows مع `--dart-define=FREE_VERSION=true --dart-define=FREE_TRIAL_DAYS=7`.

**الخطوات:**
1. تشغيل النسخة التجريبية على جهاز جديد وتثبيت `firstRunDate`.
2. مرور 7 أيام (أو محاكاة الوقت إلى ما بعد `firstRunDate + 7 days`).
3. فتح التطبيق ومراقبة الشارة في الشاشة الرئيسية والوصول إلى الشاشات.

- **النتيجة المتوقعة:** عرض حالة انتهاء التجربة بوضوح (العداد لا يختفي)، ومنع الوصول مع التحويل الفوري إلى شاشة التفعيل `/activation` برسالة واضحة، مع إمكانية الترقية المباشرة إلى رخصة مدفوعة دون فقد البيانات.
- **النتيجة الفعلية (قبل الإصلاح):** يختفي عداد الترخيص تماماً (`SizedBox.shrink()`)، ويستمر التطبيق في العمل بكامل صلاحياته دون أي تحويل أو قفل.
- **قابل للتكرار؟** دائماً بعد مرور 7 أيام على `firstRunDate`.

## 4. السبب الجذري

- **السطحي:** اختفاء شارة الترخيص واستمرار عمل التطبيق بعد انتهاء الـ 7 أيام.
- **الجذري (4 أسباب مترابطة):**
  1. `lib/services/license_manager.dart:579` (قبل التعديل): في فرع `LicenseConfig.isFreeVersion`، عند تجاوز `expiry` كانت الدالة ترجع `null` بدل إرجاع كائن `License` منتهي الصلاحية، ما يجعل `_LicenseBadge` في `lib/ui/home/modern_home.dart:1510` يدخل شرط `if (license == null) return const SizedBox.shrink();` ويُخفي العداد تماماً.
  2. `lib/config/license_config.dart:50-51` و `lib/services/license_manager.dart:308,693,705` و `lib/screens/splash_screen.dart:118` و `lib/services/license_entitlement.dart:103` و `lib/core/provider/license_provider.dart:27` و `lib/widgets/license/feature_guard.dart:44`: كلها كانت تعامل `FREE_VERSION=true` كتجاوز أعمى (`return true`) ولا تفرّق بين النسخة المجانية الدائمة (`36500` يوم) والنسخة التجريبية محدودة المدة (`FREE_TRIAL_DAYS=7`).
  3. `lib/services/license_manager.dart:470-658`: `_readCurrentLicense()` كان يدخل فرع `if (LicenseConfig.isFreeVersion)` قبل فحص وجود `lease_token` مدفوع مخزّن على الجهاز، ما يمنع ترقية نسخة تجريبية برخصة مدفوعة في نفس التثبيت.
  4. غياب حارس التوجيه/الاستئناف أثناء التشغيل في `lib/core/router/go_router.dart` و `lib/app_bootstrap.dart` عند انتهاء المدة والتطبيق مفتوح أو عائد من الخلفية، مع غياب حماية تغير الساعة غير المتعمّد دون قفل خاطئ للمستخدم.
- **لماذا لم يمسكه الاختبار الموجود:** `license_expiration_consistency_test.dart` اختبر خصائص كائن `License` مباشرة دون تشغيل مسار `FREE_VERSION=true` + `FREE_TRIAL_DAYS=7` في `LicenseManager` أو بوابة الراوتر.
- **هل هو Regression؟** نعم — سلوك أضيف في commit `454b64d` (`feat(licensing): support configurable FREE_TRIAL_DAYS via dart-define`) دون فصل وضع التجربة عن النسخة المجانية الدائمة.

## 5. الحل

- **ما تم تغييره:**
  1. التمييز الصريح في `lib/config/license_config.dart` عبر `isPermanentFreeVersion` و `isTimeLimitedTrial` و `freeTrialDays` مع الحفاظ على `isFreeVersion`.
  2. إعادة هيكلة `_readCurrentLicense()` في `lib/services/license_manager.dart` للتحقق من الرخصة الموقّعة (`lease_token`) ثم جسر AES القديم أولاً قبل السقوط إلى فرع التجربة/المجانية (لإتاحة الترقية المباشرة في نفس التثبيت بدون حذف البيانات)، مع إرجاع كائن `License` منتهٍ عند انتهاء التجربة بدل `null`.
  3. معالجة آمنة للساعة بدون قفل خاطئ: تقييد `daysRemaining` بالحد الأقصى لمدة الرخصة حتى لا يظهر رقم ضخم عند رجوع الساعة بالخطأ، وجعل `_updateSessionTracking` يُصلح `lastCheckTime` ذاتياً عند تصحيح الساعة دون تضخيم `sessionElapsedMs`، مع فحص تراكم الاستخدام الفعلي `sessionElapsedMs >= trialDays`.
  4. قصر التجاوز التلقائي على `isPermanentFreeVersion` فقط عبر `LicenseManager.isLicenseActive/hasFeature/canAddUser` و `LicenseEntitlement` و `FeatureGuard` و `isFeatureEnabledProvider` و `SplashScreen`.
  5. إضافة `licenseGateRedirect` و `refreshListenable` في `lib/core/router/go_router.dart` ومراقبة الاستئناف (`WidgetsBindingObserver`) ومؤقت فحص كل 10 دقائق في `PosApp` (`lib/app_bootstrap.dart`).
  6. تحديث `_LicenseBadge` في `lib/ui/home/modern_home.dart` لإظهار حالة «منتهي» / «أقل من يوم» / «تجربة: X يوم» مع زر الترقية، وإضافة رسالة انتهاء التجربة ومنع الرجوع في `ActivationScreen` عند القفل، وإضافة بطاقة «الترخيص والترقية» في `SettingsScreen` (`lib/ui/setting/settings.dart`) وزر الترقية في `LicenseInfoScreen`، ودعم `-TrialDays` في `build_release.ps1` للويندوز بجانب `scripts/build_android_apk.ps1` للأندرويد، بالإضافة إلى دعم `--dart-define=FREE_TRIAL_MINUTES=<n>` ومؤقت تحقق خفيف كل 5 ثوانٍ لتمكين اختبارات QA السريعة (مثل تجربة دقيقة واحدة).
- **لماذا هذا هو الجذري وليس العَرَضي:** توحيد قرار الصلاحية والبوابات ومسار الترقية عبر كل نقاط الدخول والتشغيل من مصدر واحد (`LicenseConfig` + `LicenseManager`) دون مساس بحسابات النسخة المجانية الدائمة.
- **ملفات معدّلة / مضافة:**
  - `lib/config/license_config.dart`
  - `lib/services/license_manager.dart`
  - `lib/services/license_entitlement.dart`
  - `lib/core/provider/license_provider.dart`
  - `lib/core/router/go_router.dart`
  - `lib/screens/splash_screen.dart`
  - `lib/screens/license/activation_screen.dart`
  - `lib/screens/license/license_info_screen.dart`
  - `lib/widgets/license/feature_guard.dart`
  - `lib/ui/home/modern_home.dart`
  - `lib/ui/setting/settings.dart`
  - `lib/app_bootstrap.dart`
  - `build_release.ps1`
  - `test/unit/services/trial_expiration_enforcement_test.dart` (جديد)
- **بدائل مرفوضة ولماذا:**
  - إرجاع `null` عند الانتهاء وإبقاء تجاوز `isFreeVersion` ← يبقي الثغرة مفتوحة ويخفي العداد.
  - قفل التطبيق عند أي تراجع في ساعة النظام ← يسبب إغلاقاً خاطئاً للمستخدمين عند تغيير الساعة أو بطارية CMOS.

## 6. الاختبارات والتحقق

| البند | القيمة |
|---|---|
| **اختبار انحدار أُضيف** | `test/unit/services/trial_expiration_enforcement_test.dart` (23 حالة اختبار) |
| **الحالة التي يغطيها** | تصنيف أوضاع البناء · التجربة النشطة والمنتهية · النسخة المجانية الدائمة · الترقية المباشرة لرخصة مدفوعة · سلامة التعامل مع الساعة · دالة توجيه الراوتر · تجربة الدقائق (`FREE_TRIAL_MINUTES=1`) |
| **النتيجة قبل الإصلاح** | `flutter test test/unit/services/trial_expiration_enforcement_test.dart` ⇒ `00:03 +4 -11: Some tests failed.` |
| **الأمر المُنفَّذ بعد آخر تعديل** | `flutter test --no-pub test/unit/services/trial_expiration_enforcement_test.dart test/unit/services/license_expiration_consistency_test.dart test/services/license_lease_test.dart test/unit/services/license_entitlement_test.dart test/unit/services/license_update_safety_test.dart test/unit/services/license_build_config_test.dart test/unit/services/license_import_test.dart test/unit/services/legacy_license_bridge_test.dart test/unit/services/license_plan_resolution_test.dart test/unit/router/activation_route_redirect_test.dart test/verification/suite_01_license_and_gates_test.dart test/widget/modern_home_dashboard_widget_test.dart test/unit/app_theme_responsive_test.dart test/unit/theme/light_mode_theme_test.dart` |
| **النتيجة الفعلية** | `00:30 +209: All tests passed!` |
| **تحليل ثابت** | `flutter analyze --no-pub lib/config/license_config.dart lib/services/license_manager.dart lib/services/license_entitlement.dart lib/core/provider/license_provider.dart lib/core/router/go_router.dart lib/screens/splash_screen.dart lib/screens/license/activation_screen.dart lib/screens/license/license_info_screen.dart lib/widgets/license/feature_guard.dart lib/ui/home/modern_home.dart lib/ui/setting/settings.dart lib/app_bootstrap.dart test/unit/services/trial_expiration_enforcement_test.dart` ⇒ `No issues found! (ran in 8.6s)` |
| **بناء Drift** | لا يلزم — لا تعديل على جداول أو DAOs |
| **اختبار يدوي مطلوب** | ⏸️ على جهاز فعلي: (1) بناء Android APK (`scripts\build_android_apk.ps1 -TrialDays 7`) والانتظار/تقديم الساعة للتحقق من شارة الانتهاء والتحويل التلقائي لـ `/activation` ثم الترقية من الإعدادات بملف `.madarlicense` (2) بناء Windows (`.\build_release.ps1 -TrialDays 7`) والتحقق من نفس المسار والنسخة المجانية الدائمة (`-FreeVersion`). |

## 7. الأثر الخلفي

- هل يتغير حساب مالي قائم؟ ☑ لا
- هل يلزم Migration؟ ☑ لا
- هل يلزم تحديث النسخ الاحتياطي (قوائم الجداول)؟ ☑ لا
- **من المتأثر؟** نسخ التجربة الـ 7 أيام فقط تتوقف فعلياً بعد انتهاء المدة ويمكن ترقيتها فوراً على نفس البيانات؛ النسخة المجانية الدائمة (`-FreeVersion` بدون `FREE_TRIAL_DAYS`) والعملاء المدفوعون غير متأثرين.
- خطة الرجوع (Rollback): `git revert <commit>` على `integration/all-agents`.

## 8. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-11-18 | وكيل التنفيذ | إنشاء التذكرة BUG-037 قبل أي تعديل كود، وبدء التنفيذ بناءً على موافقة صاحب المشروع |
| 2026-11-18 | وكيل التنفيذ | تثبيت الاختبار الفاشل (`+4 -11`)، إتمام الإصلاح عبر البوابات والواجهة والسكريبتات، تحقق 209/209 اختبار (بما فيها `FREE_TRIAL_MINUTES=1`) و `flutter analyze` نظيف (`No issues found!`)، ودعم بناء Debug لمدة دقيقة للتحقق اليدوي |
