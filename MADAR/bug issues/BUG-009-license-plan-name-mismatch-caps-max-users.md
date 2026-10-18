# BUG-009 — قيم `plan` لا تطابق `LicenseType` فتُقصّ الرخصة إلى مستخدم واحد

> مبنية على `_template-bug.md`. المصدر: فحص قراءة فقط لـ`feat/online-license@d7c57cd` بتاريخ 2026-10-18.
> **الحالة: `review`** — مُصلَح ومُتحقَّق آلياً (**18/18**). متبقٍّ اختبار على جهاز + مراجعة المالك + الدمج.
> **⚠️ `fvm` غير مثبّت على هذا الجهاز** — الأوامر بـ`flutter test` / `flutter analyze` مباشرةً (SDK 3.44.9).

---

## ⭐ ملاحظة تنفيذ مهمة

> العلة الحقيقية كانت في `_parseLease()` داخل `feat/online-license` — وهو **غير موجود** على `integration/all-agents`، ولم أنفذ أي `checkout`.
> **الحل: وُضعت المعالجة في `lib/config/license_config.dart`** — ملف **مشترك بين الفرعين** ويدخل مع الدمج بلا تعديل إضافي.
> كما استُصلحت نفس الفئة من الخطأ في **3 مواضع موجودة على الفرع الحالي** (`License.fromJson` · `validateLicense` · `_readLegacyLicense`).

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **رقم البلاغ** | BUG-009 |
| **العنوان** | رخصة بخطة «سنوي» أو «مدى الحياة» تُقرأ كـ`basic` ⇒ حدّ المستخدمين يصبح 1 |
| **النوع** | A — عيب في صلاحية الترخيص (سلوك خاطئ صامت) |
| **الأولوية** | **P1** — المبرر: `SOP-01 §D` — «مسار أساسي معطّل بلا حل بديل» P2، لكن هنا الأمر يمنع **تسجيل دخول موظف ثانٍ** ويمنع إضافة مستخدمين ⇒ يعطّل مسار التشغيل اليومي لموظف ⇒ **P1**. إضافةً: صامت تماماً ولا يظهر في أي سجل |
| **الحالة** | `review` — مُصلَح ومُتحقَّق آلياً؛ متبقٍّ مراجعة المالك + الدمج |
| **الأبلغ** | وكيل التدقيق (اكتشاف أثناء التخطيط) |
| **تاريخ البلاغ** | 2026-10-18 |
| **تاريخ الاكتشاف** | أثناء فحص `feat/online-license` قبل الدمج |
| **نسخة التطبيق** | 2.3.0+1 |
| **الفرع المتأثر** | `feat/online-license` فقط — **غير موجود بعد في `integration/all-agents`** |

## 2. النطاق التقني

| الحقل | القيمة |
|---|---|
| **الملفات** | `lib/services/license_manager.dart` (`_parseLease` + `_getMaxUsersForType`) · `lib/services/user_session_service.dart` · `tools/simulator_db.json` · `admin_dashboard/src/config/modules.js` |
| **الـ Flavors المتأثرة** | base / vegetable / clothing — **الكل** |
| **منطقة حساسة** | ☑ **ترخيص** |
| **مستوى المخاطرة** | **عالٍ** — يمنع تشغيل موظفين |

## 3. إعادة الإنتاج

**تحليلي — من قراءة الكود، لم يُشغَّل:**

1. اصنع رخصة في اللوحة أو المُحاكي بخطة `yearly` أو `lifetime` أو `monthly`.
2. وقّعها واستوردها في MADAR.
3. افتح شاشة إدارة المستخدمين ← «إضافة مستخدم».

**النتيجة الفعلية (المشتقة):** الحقل يعرض `1 / 1`، وزر الإضافة معطَّل، وتسجيل دخول مستخدم ثانٍ مرفوض.

## 4. السبب الجذري

**الجذري:** `_parseLease()` يبحث عن `plan` داخل `LicenseType`، لكن مصدرا البيانات يستعملان مسمّيات مختلفة.

```dart
// lib/services/license_manager.dart — feat/online-license
final type = LicenseType.values.firstWhere(
  (t) => t.name == p['plan'],
  orElse: () => LicenseType.basic,   // ⚠️ سقوط صامت بلا تسجيل
);
```

**المتاح في `LicenseType`:**
`free · trial · basic · standard · professional · enterprise`

**القيم المستعملة فعلياً في مصدرين:**

| المصدر | قيم `plan` | النتيجة |
|---|---|---|
| `tools/simulator_db.json` | `standard` · `basic` · `professional` · **`custom`** | ❌ `custom` ← `basic` |
| `admin_dashboard/src/config/modules.js` → `LICENSE_PLANS` | `trial` · **`monthly`** · **`yearly`** · **`lifetime`** | ❌ **الثلاثة ← `basic`** |

**الأثر المتسلسل (كل حلقة مُتحقَّقة):**

```
plan:"yearly"
  → orElse: LicenseType.basic
  → _getMaxUsersForType(basic) = 1            (license_manager.dart)
  → License.maxUsers = 1
  → user_session_service.getMaxUsers()  → 1
  → user_session_service.canAddUser()  → activeSessions.length < 1   ❌
  → user_session_service.canUserLogin()→ يفحص نفس الحد               ❌
  → getSessionStats() → "1/1 users"
```

**لماذا لم يمسكه الاختبار الموجود:** `test/services/modular_features_test.dart` يمرّر `plan: 'standard'` و`'basic'` فقط. و`test/services/license_lease_test.dart` يمرّر `plan: 'standard'` و`'professional'`. **⇒ لا يوجد أي اختبار يمرّر `yearly` أو `lifetime` أو `custom`.**

**هل هو Regression؟** لا — علة تصميم أصلية في كود لم يُدمج بعد.

## 5. الحل — ✅ **مُنفَّذ**

**الخيار المُنفَّذ: إصلاح السقوط الصامت + توحيد المصدر — لا تعديل على أسماء الخطط في اللوحة.**

### 🔧 التغييرات

**`lib/config/license_config.dart` (+68) — الملف المشترك بين الفرعين:**

```dart
class LicensePlans {
  static const Map<String, String> toLicenseTypeName = {
    'free': 'free',  'trial': 'trial',
    'basic': 'basic', 'standard': 'standard',
    'professional': 'professional', 'enterprise': 'enterprise',
    'monthly': 'standard',  'yearly': 'professional',
    'lifetime': 'professional', 'annual': 'professional',
    'custom': 'professional',
  };
  static const String fallbackName = 'standard';
  static String? resolve(String? plan);          // null إذا غير معروف
  static String resolveOrFallback(String? plan); // لا يرمي أبداً
  static bool isUnknown(String? plan);
}
```
⚠️ يُرجع **اسم `LicenseType` كنص** لا النوع نفسه — لأن `license_config.dart` يُستورد من `license_manager.dart` ⇒ لو참-Object لـ`LicenseType` لدخلنا في **استيراد دائري**.

**`lib/services/license_manager.dart` (+178 التراكمي):** استُصلحت **3 مواضع**:
| الموضع | قبل | بعد |
|---|---|---|
| `License.fromJson` `:109` | `firstWhere` **بلا `orElse`** ⇒ يرمي `StateError` | `LicensePlans.resolveOrFallback` + `orElse: standard` + `AppLogger.w` |
| `validateLicense` `:260` | `firstWhere` **بلا `orElse`** ⇒ يرمي | نفس المعالجة |
| `_readLegacyLicense` `:364` | `orElse: basic` ⇒ **1 مستخدم بصمت** | نفس المعالجة + تسجيل تحذير |

**لماذا هذا الجذري:** لأن العَرَضي (عدد المستخدمين) سببه عدم تطابق مسمّى، لا حساب.

| البدائل المرفوضة | السبب |
|---|---|
| ❌ تمرير `max_users` كـclaim مستقل | 🔴 يُعيد تصميم الـlease ويُكسر التوافق مع الـEdge Function |
| ❌ تعديل `user_session_service` | ⛔ layering خاطئ — المصدر هو الرخصة لا طبقة الجلسات |
| ❌ تعديل أسماء الخطط في اللوحة الآن | ⛔ قرار تجاري مؤجَّل — **ولن يتكرر الخلل بعد هذا الإصلاح** |

### ✅ التحقق المُنفَّذ

**الأمر:** `flutter test test/unit/services/license_plan_resolution_test.dart`
**النتيجة:** `00:00 +18: All tests passed!`

| # | الاختبار | يغطي |
|---|---|---|
| 1-4 | كل قيم `LICENSE_PLANS` (داشبورد) لا ترمي | `trial·monthly·yearly·lifetime` |
| 5 | ⭐ **`yearly` ≠ `basic`** و `maxUsers > 1` | **العلة الأصلية** |
| 6 | `lifetime` ≠ `basic` | العلة الأصلية |
| 7 | `monthly` → `standard` (3 مستخدمين) | |
| 8-11 | كل قيم `simulator_db.json` لا ترمي | `standard·basic·professional·custom` |
| 12 | ⭐ `custom` ≠ `basic` | العلة الأصلية |
| 13 | الأسماء الأساسية تُطابق نفسها | انحدار |
| 14 | ⭐ خطة مجهولة **لا ترمي ولا تصمت عند 1** | الأمان |
| 15 | `null` degrades بأمان | |
| 16 | ⭐ **تحمّل حالة الأحرف والمسافات** | `YEARLY` · `  Yearly  ` |
| 17 | `isUnknown` يعلّم غير الصالح فقط | أداة إصدار قادمة |
| 18 | ⭐ **الـfeatures لا تتأثر بحلّ الـplan** | تحقّق صريح |

### 🔐 تحقّق شامل

| فحص | النتيجة |
|---|---|
| `flutter analyze` على 6 ملفات | `No issues found!` |
| **كل اختبارات الترخيص** | **`00:07 +78: All tests passed!`** (29 `BUG-007` + 11 `FEAT-014` + 18 `BUG-009` + 14 hardware + `backup_tables` + `staff_excel_import`) |
| **انحدار أوسع** (flavor · sync · widget) | **`00:11 +15: All tests passed!`** |
| `build_runner` | ⛔ **لا يلزم** — لا `tables/` ولا `dao/` |
| Migration / schemaVersion | ☐ لا — **صفر** |

### حالة الفرع

| | |
|---|---|
| `feat/online-license` | **غير مدمج** — و`LicensePlans` جاهز للدخول معه |
| عند الدمج | ⭐ يكفي استبدال `orElse: basic` في `_parseLease` بـ`LicensePlans.resolveOrFallback(p['plan'])` |
| HEAD | `a064053` على `integration/all-agents` — **لم يتغير** |

### 🖐️ اختبار يدوي مطلوب قبل الإغلاق

- [ ] رخصة `plan: "yearly"` على جهاز ⇒ شاشة إدارة المستخدمين تعرض عدداً **> 1**
- [ ] تسجيل دخول **موظف ثانٍ** ينجح

## 7. الأثر الخلفي

| السؤال | الإجابة |
|---|---|
| هل يتغير حساب مالي قائم؟ | ☐ لا |
| هل يمس بيانات عميل؟ | ☐ لا — لكنه **يمنع إضافة مستخدمين** وهو أثر تشغيلي مباشر |
| هل يلزم Migration؟ | ☐ لا |
| هل يلزم تحديث النسخ الاحتياطي؟ | ☐ لا |
| **هل يلزم إعادة إصدار رخص قائمة؟** | ☐ **لا** — `features` تأتي من claim مستقل ولا تتأثر، و`maxUsers` كان **ناقصاً أصلاً** ويصبح صحيحاً تلقائياً عند أول قراءة بعد التحديث |
| **خطة التراجع** | `git revert <commit>` |

## 8. سجل الحالة

| التاريخ | من | التغيير |
|---|---|---|
| 2026-10-18 | وكيل التدقيق | إنشاء البلاغ من فحص قراءة فقط |
| 2026-10-18 | وكيل التدقيق | Gate 2 ممرّ — تنفيذ في `license_config.dart` (ملف مشترك بين الفرعين) + 3 مواضع في `license_manager.dart` |
| 2026-10-18 | وكيل التدقيق | اختبار جديد (18 حالة) ⇒ **`+18 All tests passed`** |
| 2026-10-18 | وكيل التدقيق | تحقّق شامل ⇒ **`+78` ترخيص · `+15` انحدار أوسع · `analyze` نظيف** |
| 2026-10-18 | وكيل التدقيق | **الحالة → `review`** |

---

**الحالة: `review`** ⏸️ متبقٍّ قبل `done`:

1. ⛔ **اختبار يدوي** — رخصة `plan: "yearly"` ⇒ عدد المستخدمين **> 1** وت نجاح دخول موظف ثانٍ
2. ⏳ **عند دمج `feat/online-license`** — استبدال `orElse: () => LicenseType.basic` في `_parseLease` بـ`LicensePlans.resolveOrFallback(p['plan'])` (**سطر واحد**)
3. مراجعة صاحب المشروع · الدمج في `integration/all-agents`

> **تبعية تشغيلية:** ⛔ `BUG-015` (إزالة التجاوزات) يُمنع قبل `FEAT-013` (سلامة التحديث) — تشديد `isExpired` مع installers التي تحذف `secure_license.dat` قد يمسح الرخصة عند التحديث.
