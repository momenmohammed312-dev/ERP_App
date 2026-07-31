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

## 7. قبل ما تبدأ أي مرحلة تنفيذ

1. اقرأ ملف الخطة الحالي (`vegetable_market_flavor_plan.md` أو المكافئ للـflavor اللي بتشتغل عليه)
2. نفذ مرحلة واحدة بس في المرة، منقفلهاش من نفسك — اعرض النتيجة واستنى تأكيد
3. أي افتراض مش متأكد منه (اسم عمود، سلوك حافة/edge case) — اسأل، منتخيلش

## 8. ممنوعات صريحة

- لا تعدل migration step قديم
- لا تغير state management framework
- لا تلمس الأصل (base flavor) بدون طلب صريح
- لا تعمل جدول جديد قبل ما تتأكد مفيش جدول موجود يتوسع بدله
- لا تقفل مرحلة من الخطة بدون تأكيد من المستخدم
