# BUG-030 — تفعيل رخصة الإصدار وتلف تسلسل المفتاح العام في أسرار البناء

> مبني على `_template-bug.md` وتوجيهات ميثاق MADAR ونظام التفويض متعدد الوكلاء (`/madar-delegation` و `/madar-bug-hunt`).

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **الرقم** | BUG-030 |
| **العنوان** | ظهور شاشة التفعيل للعميل عند تشغيل نسخة Release وتلف تسلسل `LICENSE_PUBLIC_KEY` في `build_secrets.local.json` |
| **النوع** | عيب برمجي (Bug) + تحسين موثوقية البناء (Release Pipeline) |
| **الأولوية** | **P1 - عالي** (العميل عطلان ومغلق أمامه البرنامج بعد استلام الـ Release) |
| **الحالة** | `resolved` |
| **المكتشف** | تجربة العميل لنسخة Release v2.3.0 |
| **التاريخ** | 2026-10-27 |
| **الفرع المستهدف** | `integration/all-agents` |
| **الموديلات المشاركة** | Gemini 3.8 Flash (التحقيق والمنطق) + OpenCode Free Fleet (الفحص والاختبارات) |

---

## 2. ملخص المشكلة وسياق العميل

عند قيام المطور بتشغيل سكريبت `build_release.ps1` وتسليم مجلد الـ Release للعميل، قام العميل بفتح البرنامج فظهرت له شاشة «تفعيل الرخصة» تطالبه بإدخال مفتاح الترخيص أو استيراد ملف ترخيص. ظن المطور أنه قام بإضافة مفتاح التفعيل مسبقاً في ملف الأسرار ولن يطلب من العميل شيئاً.

---

## 3. التحليل الجذري (Root Cause Analysis - RCA)

بعد استدعاء وكيل الفحص الفني (Gemini 3.8 Flash) وفحص الكود وسجلات البناء تبين سببان جذريان:

### السبب الأول: مفهوم منظومة الترخيص في MADAR (Architecture Mismatch)
* ملف `build_secrets.local.json` يحتوي على المفتاح العام للتحقق (`LICENSE_PUBLIC_KEY`) ومفتاح التشفير السري (`LICENSE_SECRET_KEY`)، ولا يحتوي على «مفتاح تفعيل خاص بالعميل».
* شاشة البداية (`SplashScreen` في `lib/screens/splash_screen.dart:117-124`):
  ```dart
  final isLicenseValid = LicenseConfig.isFreeVersion
      ? true
      : await licenseManager.isLicenseValid();

  if (!isLicenseValid) {
    if (mounted) context.go('/activation');
    return;
  }
  ```
* جهاز العميل يعمل لأول مرة، ومجلد `%APPDATA%/pos_offline_desktop/secure_license.dat` فارغ تماماً على جهازه، ولم يتم بناء النسخة مع `--dart-define=FREE_VERSION=true`.
* لذلك من الطبيعي والمتوقع هندسياً أن يطلب النظام تفعيل الترخيص عند أول تشغيل على أي جهاز جديد ما لم تكن النسخة مبنية بوضع النسخة المجانية (`FREE_VERSION=true`).

### السبب الثاني: تلف تسلسل `LICENSE_PUBLIC_KEY` (Critical Bug)
* في `build_secrets.local.json`، تم حفظ خاصية `LICENSE_PUBLIC_KEY` ككائن PowerShell (`PSCustomObject`) بدلاً من نص `string` صريح، مما ضخم الملف إلى 4.4 ميجابايت (16,984 سطراً) محتوياً على شجرة مراجع `.NET DLL`.
* داخل سكريبت `build_release.ps1` سطر 73:
  ```powershell
  $publicKeyPem = ($secrets.LICENSE_PUBLIC_KEY -replace "`r`n", '\n' -replace "`n", '\n')
  ```
  أدى هذا التحويل التلقائي في PowerShell إلى تحويل الكائن إلى نص مشوه:
  `@{value=-----BEGIN PUBLIC KEY-----\n...; PSPath=C:\Users\...}`
* تم تمرير هذا النص المشوه عبر `--dart-define=LICENSE_PUBLIC_KEY=$publicKeyPem`.
* عند استيراد أي ملف `.madarlicense` للعميل (سواء تجريبي أو سنوي)، تفشل دالة `RSAPublicKey` في قراءة المفتاح العام التالف وترفض تفعيل البرنامج!

---

## 4. خطة الإصلاح (Fix & Prevention Plan)

1. **تصحيح `build_secrets.local.json`:**
   تنظيف المفتاح العام ليصبح نصاً صافياً (Clean String PEM) دون أي كائنات PowerShell أو بيانات وصفية.
2. **تحصين `build_release.ps1` (Defensive Handling):**
   - استخراج النص بأمان: التحقق مما إذا كان الكائن يحتوي على `.value` أو نص مباشر، والتحقق الصارم من أن النص يبدأ بـ `-----BEGIN PUBLIC KEY-----` قبل بدء البناء.
   - إضافة بارامتر جديد `-FreeVersion`:
     إذا تم تشغيله (`.\build_release.ps1 -FreeVersion`)، يمرر تلقائياً `--dart-define=FREE_VERSION=true`، مما يتيح إصدار نسخة تعمل مباشرة للعميل بدون أي طلب تفعيل.
     أما في الوضع العادي (بدون `-FreeVersion`)، يظل الترخيص محمياً ويتطلب تفعيل العميل برخصة موقَّعة `.madarlicense`.
3. **توثيق مسار تفعيل العميل المرخص (License Issuance Workflow):**
   شرح واضح لكيفية أخذ «معرف الجهاز» الظاهر على شاشة العميل وتوليد ملف `.madarlicense` باستخدام `node tools/license_issuer.js` وتمريره للعميل للضغط على «استيراد رخصة من ملف».

---

## 5. شروط القبول (Acceptance Criteria)

- [x] **AC1:** ملف `build_secrets.local.json` يحتوي على `LICENSE_PUBLIC_KEY` كنص صافٍ (`string`)، وحجم الملف أقل من 1KB.
- [x] **AC2:** سكريبت `build_release.ps1` يتحقق من صحة المفتاح العام دفاعياً ويرفض البناء إذا كان تالفاً أو مشوهاً.
- [x] **AC3:** سكريبت `build_release.ps1` يدعم سويتش `-FreeVersion` لتخطي التفعيل بالكامل عند الرغبة في تسليم نسخة مفتوحة للعميل فوراً.
- [x] **AC4:** اختبارات الـ Unit Tests الخاصة بالترخيص وقراءة المفاتيح تعمل بنجاح (100% Passed).
