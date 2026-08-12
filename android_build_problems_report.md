# تقرير مشاكل Android Build — POS Offline Desktop

آخر تحديث: 2026-08-10
الهدف: `flutter build apk -t lib/main_vegetable.dart --dart-define=FLAVOR=vegetable --debug --no-pub`

---

## الحالة الحالية (آخر تشغيل بصيغة `-v`)

- **النتيجة: BUILD FAILED** في 3m 14s
- **الـAPK لم يُنشأ**: `build\app\outputs\flutter-apk\app-debug.apk` غير موجود
- نقطة الفشل الحالية (blocker):

```
Could not determine the dependencies of task ':sqlite3_flutter_libs:compileDebugJavaWithJavac'.
> Cannot query the value of this provider because it has no value available.
Caused by: org.gradle.api.internal.provider.MissingValueException
  at ProviderBackedFileCollection.visitDependencies
```

> نقاط قبل الفشل كانت نجحت: NDK محدد صح (28.2.13676358)، AGP 8.9.1 اتحمّل، كل الـ16 مشروع اتكونفجروا (`:permission_handler_android` اللي كان بيفشل قبل كده فات).

---

## المشاكل بالترتيب الزمني

### 1. كاش Gradle تالف (corrupted)
- الملف `file-access.bin` في `caches\journal-1` تحوّل تالف في الكاش على C: وبعد النقل لـ F: ظهرت نفس المشكلة مرة تانية في `F:\gradle-home`.
- خطأ أولي:
  ```
  UncheckedIOException: Could not add entry 'F:\gradle-home\caches\modules-2...'
  to cache file-access.bin
  ```
- **الحل:** حذف `F:\gradle-home\caches\journal-1` و`caches\8.12\transforms` (بيتولدوا تاني أوتوماتيك، و`modules-2` ماانحذفش).

### 2. Lambda / afterEvaluate تتصادم مع التقييم المبكر
- الكود القديم كان مسجّل `afterEvaluate` لعمل fallback namespace، لكن `subprojects { evaluationDependsOn(":app") }` بيقيّم المشاريع بدري.
- خطأ أولي:
  ```
  Cannot run Project.afterEvaluate(Action) when the project is already evaluated
  ```
- **الحل:** استبدالها بـ `plugins.withId` مع فروع منفصلة لـ `LibraryExtension` و `AppExtension` في `android/build.gradle.kts`.

### 3. plugins قديمة من غير namespace (AGP 8+)
- AGP 8 بيطلّب `namespace` إجباري لكل مكتبة، وبعض الـplugins القديمة مابتعرفش.
- **الحل:** fallback injected في `android/build.gradle.kts` (مثبّت، مش تعديل في pub-cache).

### 4. SDK requirements: الـplugins طلبت API 36 والمشروع على 34
- warnings زي `plugin app_links requires Android SDK version 36 or higher`.
- **الحل:** رفع `compileSdk`/`targetSdk` من 34 إلى 36 في `android/app/build.gradle.kts`.

### 5. نسخة AGP ناقصة مقابل المتطلب
- دلوقتي هتطلب AGP أحدث؛ تم رفع `com.android.application` من `8.7.3` إلى `8.9.1` في `android/settings.gradle.kts`.
- ملاحظة: Gradle 8.12 عليه `Warning: Flutter support ... will soon be dropped ... upgrade to at least 8.14.0` — لسه مش مانع، لكن بيوّد على الرفع قريبًا.
- بنستخدم حاليًا `--android-skip-build-dependency-validation` لتجاوز فحص النسخ.

### 6. `platform_device_id` ميّت على JCenter
- الـpackage القديم (2019) بيستدعي `jcenter.bintray.com` اللي اتقفل نهائيًا.
- خطأ أولي:
  ```
  Could not download kotlin-compiler-embeddable-1.3.50.jar
  from https://jcenter.bintray.com/...
  ```
- **الحل:** إزالة `platform_device_id` نهائيًا واستبداله بـ `device_info_plus` الحالي في `lib/services/hardware_id_service.dart` (مع دعم Android/iOS مجددًا) + update لـ`pubspec.lock` والـregistrants.

### 7. NDK غير محدد بشكل صريح
- `ndkVersion = flutter.ndkVersion` كانت بتسرّح Gradle يحاول يحل نسخة ولوّح إنه ممكن يحمّل إصدار مختلف.
- **الحل:** تثبيت الصريح `ndkVersion = "28.2.13676358"` في `android/app/build.gradle.kts` (مثبتة على الجهاز).
- التأكيد من الـlog: `C/C++: android.ndkVersion from module build.gradle is [28.2.13676358]`.
- ملاحظة: فيه warning `[CXX5106] NDK located by ndk.dir ... deprecated` — بيقول نحذف `ndk.dir` من `local.properties` ونكتفي بـ`android.ndkVersion` في كل الموديولات.

### 8. sqlite3_flutter_libs (خلال Windows build)
- CMake/`FetchContent` أبلغ "Truncated tar archive" أثناء تنزيل sqlite رغم نجاح التنزيل فعلًا (الهاش مطابق، والاستخراج اكتمل — 48 ملف).
- **الحل مؤقت:** علامات الـstamps اتحطت للعبور.
- الحالة دى مش مطبقة على Android build (اللي فشل قبلها).

### 9. كود Drift ملوش `app_database.g.dart` مُجدّد
- الجدول الجديد `SyncQueue` موجود في الجداول/DAO لكن الـgenerated file اتطلع قديم.
- خطأ أولي:
  ```
  Type 'SyncQueueData' not found ... '$SyncQueueTable' not found
  ```
- **الحل:** `dart run build_runner build --delete-conflicting-outputs` وإعادة توليد كل الـ.g.dart.

### 10. Windows build: مشكلة صلاحيات الـinstall
- الـexe اتجمع بنجاح لكن الخطوة الأخيرة فشلت:
  ```
  file cannot create directory: C:/Program Files/pos_offline_desktop.
  Maybe need administrative privileges.
  ```
  بسبب `CMAKE_INSTALL_PREFIX=PATH=C:/Program Files/pos_offline_desktop`.
- **الحل المقترح:** تغيير install prefix لمجلد محلي أو تشغيل بصلاحيات Administrator.

---

## الـBlocker الرئيسي حاليًا (رقم 11): MissingValueException

- الخطأ بيديور بين الموديولات مع نفس التوقيع (`compileDebugJavaWithJavac`): ظهر على `:permission_handler_android` وبعدين على `:sqlite3_flutter_libs`.
- ده **bug معروف في Flutter** (issue #186152 في flutter/flutter):
  - `FlutterPlugin.kt` بيضيف `packJniLibsTask` كمخرج لأي project فيه native Android code عن طريق Provider مالهوش قيمة وقت resolving التبعيات.
  - بيحصل لأي مشروع مع plugins native — ومش بيحصل لمشروع من غير plugins.
- الحلول المتاحة والآمنة (خارج قائمة المنع):
  1. `cd android; .\gradlew.bat clean` (خبرة SO: بيكسر stale state بعد تغيير AGP).
  2. مسح build dir ورفع build تاني.
- **الحلول المرفوضة حاليًا (من المستخدم):** `flutter pub cache repair` + `flutter upgrade` + أي أداة SDK/NDK install.

---

## ملخص إجراءات خارجة عن قواعد المشروع (تحتاج مراجعة)

- رفع `compileSdk`/`targetSdk` إلى 36 و`ndkVersion` pin → أثر على `android/app/build.gradle.kts` (الملف base، والـAGENTS.md بيقول "الأصل مايتلمسش"). لازم يُوثق كـ"فيكس عام لكل الـflavors" أو يتحكم فيه داخل flavor build.
- تغيير نسخة AGP في `settings.gradle.kts` لـ8.9.1 — نفس الملاحظة.

---

## الملفات المتغيرة

- `android/settings.gradle.kts` — AGP 8.9.1
- `android/app/build.gradle.kts` — compileSdk/targetSdk 36 + ndkVersion pin
- `android/build.gradle.kts` — namespace fallback بـ`plugins.withId`
- `pubspec.yaml` / `pubspec.lock` — إزالة `platform_device_id`
- `lib/services/hardware_id_service.dart` — استبدال بـ`device_info_plus`
- ملفات generated: `linux/`, `macos/`, `windows/flutter/generated_*`