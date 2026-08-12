# Build & Verification Scripts

سكريبتات بناء/تحقق إجبارية لنسخة Windows Release — الغرض منها منع تسليم نسخة ناقصة من الـ DLLs للعميل بصمت.

## التشغيل الرسمي (البديل عن أي بناء يدوي)

من **جذر المشروع** شغّل:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -LicenseSecretKey <KEY>
```

أو باستخدام متغيّرات البيئة:

```powershell
$env:LICENSE_SECRET_KEY = "<KEY>"
$env:TRIAL_LICENSE_KEY = "<KEY>"
powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1
```

> `-LicenseSecretKey` لازم يكون نفس المفتاح المستخدم في توليد اللايسنس (شغّل من غير مفتاح = إيقاف فوري برسالة واضحة). للتجربة المحلية فقط من غير مفتاح استخدم `-SkipLicenseCheck` — ممنوع لنسخة العملاء.

### البارامترات

| البارامتر | الوظيفة |
|---|---|
| `-LicenseSecretKey <key>` | مفتاح توقيع اللايسنس (يُمرَّر بـ `--dart-define` للبناء). |
| `-TrialLicenseKey <key>` | مفتاح التريال المدمج. |
| `-InstallerScript <path>` | سكريبت Inno Setup (الافتراضي: `installer.iss`). |
| `-SkipPackaging` | بناء + تحقق فقط من غير Inno Setup. |
| `-SkipLicenseCheck` | تجاوز فحص المفتاح (تطوير محلي فقط). |

## بيشتغل إيه بالظبط

`build_release.ps1` ينفّذ بالترتيب:

1. `flutter clean`
2. `flutter pub get`
3. `flutter build windows --release`
4. `scripts\verify_windows_build.ps1` ← **بوابة تحقق إجبارية**
5. لو التحقق نجح → `iscc <installer script>` (التغليف)

لو أي خطوة فشلت (خاصة التحقق) → **يوقف فورًا ولا يعمل installer**، ويعيد Exit Code = 1.

## إيه اللي بيفحصه `verify_windows_build.ps1`

- يقرأ قائمة الـ plugins **تلقائيًا** من `windows/flutter/generated_plugins.cmake` (مش hardcoded، فيظل متزامن مع أي تغيير في `pubspec.yaml`).
- لكل plugin يتحقق أن ملف DLL مطابق موجود في `build\windows\x64\runner\Release\` (مثل `connectivity_plus_plugin.dll`).
- يتحقق أن `pos_offline_desktop.exe` موجود.
- يتحقق أن مجلد `data\` موجود وغير فارغ.
- **Exit Code 0** = سليم → يُكمّل التغليف. **Exit Code 1** = ناقص → يُوقف التغليف.

## إزاي تتحقق بنفسك

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify_windows_build.ps1
```

## لو السكريبت فشل وقال فيه DLL ناقص

1. **اعمل build نظيف من الصفر**: `flutter clean` ثم `flutter pub get` ثم أعد شغّل `build_release.ps1`. (أغلب حالات الملفات الناقصة سببها build قديم/incremental.)
2. **شغّل من الـ Release مش الـ Debug**: اتأكد إنك مش شغال بالغلط من `build\windows\x64\runner\Debug` — الـ installer بياخد من `Release`.
3. **Windows Defender / Antivirus**: افتح Windows Security → Virus & threat protection → Protection history، ولاحظ هل أي DLL (مثل `connectivity_plus_plugin.dll`) اتحجر/اتحذف وقت البناء. لو حصل، أضِف استثناء (exclusion) لمجلد المشروع (مثل `G:\development\POS-Offline-Desktop-main`) في Windows Defender، ثم أعد البناء. الملفات دي مش موقّعة رقميًا وغالبًا بتحصل عليها برامج الحماية.
4. لو لسه ناقص بعد ده: سجّل أسماء الملفات الناقصة بالظبط (السكريبت بيطبعها) وبلّغ المطوّر قبل أي تسليم للعميل.

## Inno Setup مش موجود؟

`build_release.ps1` بيشوف `ISCC.exe` في PATH + المسارات المعتادة، ولو مش موجود بيطبع تعليمات التثبيت (من https://jrsoftware.org/isdl.php أو `choco install innosetup -y`) ويوقف.

## حماية إضافية على جهاز العميل (Self-Check)

غير فحص ما قبل التغليف، فيه **فحص ذاتي وقت التشغيل** على جهاز العميل:

1. **`windows/runner/main.cpp`** — قبل ما التطبيق يحمّل أي plugin DLL، بيتأكد إن كل الملفات المطلوبة موجودة بجانب الـ exe. لو أي ملف ناقص (زي `connectivity_plus_plugin.dll`) بيظهر MessageBox واضح بالعربي: "ملف مفقود من مجلد البرنامج، يرجى إعادة تثبيت البرنامج بشكل كامل" بدل ما Windows يفشل بصمت أو برسالة محيّرة.
2. **`installer/factory_setup.iss`** و **`installer.iss`** — بعد التثبيت بـ `ssPostInstall`، بـ `VerifyInstalledFiles()` بيتأكد إن كل الـ DLLs الضرورية اتحطت فعلًا في `{app}`، ولو أي واحد ناقص بيحذّر المستخدم إنه يعيد التثبيت ويتأكد من مضاد الفيروسات.

> **مهم:** لو `connectivity_plus_plugin.dll` (أو أي plugin DLL) ناقص فعلًا، Windows بيمنع إقلاع التطبيق من الأساس (مذكور في import table بتاعة الـ exe) — فـ الفحص الذاتي في `main.cpp` بيمسك الحالات اللي التطبيق قدر يبدأ فيها لكن فيه ملف مذكور في القائمة ناقص من الـ folder. الدفاع الرئيسي هو `verify_windows_build.ps1` قبل التغليف (يمنع بناء installer ناقص) + فحص `ssPostInstall` في الـ installer.
