# AGENTS.md — ERP_App / POS Offline Desktop

قواعد إلزامية لأي agent (Claude Code أو غيره) بيشتغل على الكود ده. اقرأها قبل أي تعديل.

---

## 1. نظرة عامة على المشروع

- **الاسم الداخلي:** `pos_offline_desktop` (package name، مايتغيرش)
- **النوع:** تطبيق ERP/POS، Flutter، شغال Desktop (Windows/macOS/Linux) + خطة توسع Mobile
- **الحالة:** تطبيق أساسي (base) شغال بالفعل، وبيتبني عليه build flavors مختلفة لقطاعات مختلفة (سوق خضار، محل ملابس، ...) — راجع `vegetable_market_flavor_plan.md` للخطة التفصيلية الحالية.

## 2. Tech Stack (لا تقترح بديل بدون طلب صريح)

| الطبقة | التقنية |
|---|---|
| State management | Riverpod (`riverpod`, `flutter_riverpod`, `hooks_riverpod`) |
| Database | Drift (SQLite ORM) |
| Routing | go_router |
| PDF/Printing | `pdf`, `printing` packages |
| Excel import/export | `excel: ^4.0.6` |
| Localization | `flutter_localizations` + عربي RTL (`bidi`, `NotoNaskhArabic`) |

**ممنوع:** تغيير state management (Bloc، GetX، إلخ) أو ORM بدون طلب صريح من المستخدم. اتقرر قبل كده إن التغيير ده مش مطلوب حاليًا.

## 3. بنية الطبقات (Layers)

```
lib/
  core/
    database/
      tables/     -- تعريف الجداول (Drift Table classes)
      dao/        -- Data Access Objects (@DriftAccessor)
    router/       -- go_router config
    theme/, config/, utils/
  services/       -- منطق عمل خارجي (backup, print, license...)
  ui/<feature>/   -- شاشة لكل feature (widgets داخلها في <feature>/widgets/)
  models/         -- نماذج بيانات مش مرتبطة مباشرة بالـDB
```

**الالتزام:** أي feature جديد بياخد نفس الشكل — `tables/`, `dao/`, `ui/<feature_name>/`. مفيش كود business logic جوه الـwidgets مباشرة، لازم يعدي بـDAO أو service.

## 4. قواعد الـDatabase (الأهم — أي غلط هنا بيكسر بيانات حقيقية)

### 4.1 تعريف Table
```dart
class TableName extends Table {
  IntColumn get id => integer().autoIncrement()();
  // أعمدة nullable لأي حاجة مش أساسية، عشان الـmigrations تبقى آمنة
}
```
- FK بصيغة `.references(OtherTable, #id)`
- أعمدة اختيارية دايمًا `.nullable()` أو `.withDefault(const Constant(...))` — عشان أي migration مايكسرش صفوف موجودة

### 4.2 تعريف DAO
```dart
part 'x_dao.g.dart';

@DriftAccessor(tables: [TableName])
class XDao extends DatabaseAccessor<AppDatabase> with _$XDaoMixin {
  XDao(super.db);
  // getAllX / watchAllX (Stream) / insertX / updateX / deleteX كحد أدنى
}
```
- كل DAO بيتبع نفس النمط الموجود في `product_dao.dart` بالظبط — منتلمسش النمط الموجود
- Soft delete هو الافتراضي (status = 'Deleted')، مش hard delete، إلا لو الجدول مالوش status عمود من الأساس

### 4.3 Migrations
- **ممنوع** تعديل migration step قديم اتنفذ بالفعل. أي تغيير جديد = step جديد فوق، مش تعديل تحت
- كل تعديل schema (عمود جديد/جدول جديد) لازم version bump + `onUpgrade` step واضح
- اختبار الـmigration على نسخة تجريبية من DB قبل ما تتقفل — منقبلش "هيشتغل غالبًا"

### 4.4 Reuse قبل ما تعمل جدول جديد
قبل ما تقترح جدول جديد، دور الأول في الجداول الموجودة: `Invoices`, `InvoiceItems`, `InvoicePayments`, `LedgerTransactions`, `expenses_table`, `day_table`, `cash_session_table` — أغلب احتياجات الدفع/الآجل/المصروفات متغطية أصلاً. الجدول الجديد يتعمل بس لو فعلاً مفيش حاجة قريبة تتوسع.

## 5. Flavor System

- كل flavor له `main_<flavor>.dart` منفصل، مش نسخة تطبيق كاملة منفصلة
- `AppFeatures` (`lib/core/config/app_features.dart`) هو مصدر الحقيقة الوحيد لتفعيل/إخفاء feature حسب flavor — ممنوع `if` مباشر على اسم الـflavor متفرق في أماكن كتير
- DB name بيتحدد حسب الـflavor وقت الـinit، الجداول المشتركة زي ما هي، الجداول الخاصة بـflavor بس بتتفعل بالـfeature flag
- **الأصل (base flavor) مايتلمسش** أثناء تطوير flavor جديد إلا لو فيه فيكس عام مطلوب لكل الـflavors

## 6. أسلوب الكود

- Naming: camelCase للمتغيرات/الدوال، PascalCase للـclasses، snake_case لأسماء الملفات — زي الموجود بالفعل
- تعليقات بالعربي أو الإنجليزي مقبولة (الكود الحالي فيه الاتنين)، بس منطق مهم (زي حساب العمولة أو FIFO) لازم يتشرح بتعليق قصير فوقه
- أي دالة بتلمس فلوس/مخزون (بيع، دفع، تحديث كمية) لازم تكون atomic (transaction واحدة)، مايتقبلش partial update لو جزء فشل

## 7. نظام ودورة عمل MADAR (Workflow & SOPs)

مجلد `MADAR/` هو المركز الإلزامي لإدارة العمليات وتوثيق التذاكر وإجراءات التشغيل.

### 7.1 هيكل مجلد `MADAR/` والمهام
- `MADAR/bug issues/`: تذاكر الأخطاء والميزات الجديدة طبقاً للقوالب المعتمدة (`_template-bug.md` و `_template-feature.md`).
- `MADAR/SOP/`: إجراءات التشغيل القياسية ([SOP-01](file:///g:/development/POS-Offline-Desktop-main/MADAR/SOP/SOP-01-task-intake-triage.md) للفرز و [SOP-02](file:///g:/development/POS-Offline-Desktop-main/MADAR/SOP/SOP-02-bug-investigation.md) للتحقيق الجذري).
- `MADAR/Manefacturing Module/`: وثائق ومخططات موديول التصنيع.
- المهارة المؤتمتة: `.agents/skills/madar-bug-hunt/` للتعامل المنضبط مع الأخطاء وتثبيت الانحدار.

### 7.2 قواعد دورة العمل (SOP Rules)
1. **لا تعديل بدون تذكرة:** لا يبدأ أي تعديل على `lib/` قبل تسجيل أو وجود ملف قضية داخل `MADAR/bug issues/` بالحالة `open` أو `in-progress` مستوفٍ للبيانات، باستثناء حوادث الإنتاج P1 الحرجة مع إشعار فوري واحتواء مسبق.
2. **تحليل السبب الجذري أولاً (Root Cause First):** ممنوع ترقيع الأعراض أو إخفاء الأخطاء (Symptom masking)؛ يجب تحديد السطر والسبب بدقة (`file:line`) وتثبيته باختبار فاشل قبل الإصلاح.
3. **سرية بيانات العملاء:** ممنوع نهائياً نسخ بيانات عملاء حقيقية (أسماء، أرقام، هواتف، باركود، مفاتيح ترخيص) إلى ملفات التذاكر أو الاختبارات — الاعتماد دائماً على `test/fixtures/` والبيانات الوهمية.
4. **المناطق الحساسة (Sensitive Zones - High Risk):**
    - الترخيص (Licensing)
    - الرواتب والبصمة والحضور (Payroll & Attendance / ZKTeco)
    - موديول التصنيع (Manufacturing: BOM, MOs, Scrap, Material Receipts)
    - دفتر الحسابات العام والأستاذ (Ledger & Accounts)
    - الفواتير والمشتريات والمردودات (Invoices, Purchases & Returns)
    - الوردية وإقفال النقدية اليومي (Cash Sessions & Day Close)
    - النسخ الاحتياطي والاستعادة (Backup & Restore)
    - المزامنة السحابية (Supabase Sync)
    *أي تعديل في هذه المناطق يستوجب transaction ذرية كاملة، ونسخ احتياطي مسبق، واختبارات انحدار مؤكدة.*
5. **إلزام المزامنة:** بعد إنشاء أو تحديث أو إغلاق أي ملف `MADAR/bug issues/BUG-<رقم>-<slug>.md`، شغّل تلقائيًا (بدون توكنات/مفاتيح في المستودع؛ السكريبت يقرأها من إعدادات الجهاز):
   ```powershell
   # تذكرة واحدة:
powershell -ExecutionPolicy Bypass -File "C:\Users\Momen\.gemini\config\scripts\sync_bug_to_github_and_notion.ps1" -File "MADAR/bug issues/BUG-<number>-<slug>.md"

# كل التذاكر دفعة واحدة:
powershell -ExecutionPolicy Bypass -File "C:\Users\Momen\.gemini\config\scripts\sync_bug_to_github_and_notion.ps1" -All
   ```

### 7.3 منع الانتكاس وفرع الدمج (Regression Prevention & Merge Target)
- **منع الانتكاس إجباري:** كل عيب يتم إصلاحه يجب أن يرافقه اختبار Dart في المكان المناسب (`test/unit/` أو `test/unit/dao/` أو `test/unit/services/`).
- **أوامر التحقق الإلزامية:**
  ```bash
  fvm flutter analyze
  fvm flutter test test/unit/<test_file>.dart
  dart run build_runner build --delete-conflicting-outputs  # في حال تعديل جداول أو DAOs
  ```
- **فرع الدمج المعتمد:** فرع العمل والدمج المستهدف لجميع الـ agents دائماً هو `integration/all-agents`.

## 8. قبل ما تبدأ أي مرحلة تنفيذ

1. اقرأ ملف الخطة الحالي (`vegetable_market_flavor_plan.md` أو المكافئ للـflavor اللي بتشتغل عليه) وملف التذكرة المعني في `MADAR/bug issues/`
2. نفذ مرحلة واحدة بس في المرة، منقفلهاش من نفسك — اعرض النتيجة واستنى تأكيد
3. أي افتراض مش متأكد منه (اسم عمود، سلوك حافة/edge case) — اسأل، منتخيلش

## 9. ممنوعات صريحة

- لا تعدل migration step قديم
- لا تغير state management framework
- لا تلمس الأصل (base flavor) بدون طلب صريح
- لا تعمل جدول جديد قبل ما تتأكد مفيش جدول موجود يتوسع بدله
- لا تبدأ تعديل كود بدون تذكرة في `MADAR/bug issues/` أو توجيه صريح
- لا تلصق بيانات عملاء حقيقية في الكود أو ملفات المشاكل
- لا تقفل مرحلة من الخطة بدون تأكيد من المستخدم


