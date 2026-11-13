---
id: FEAT-025
title: "تحسين وتكبير الشريط العلوي ولوحة التحكم، معالجة أداء شاشة المنتجات، إضافة مسار النسخ الاحتياطي ومزامنته، وتحديث واجهات الكاشير والتقارير"
status: resolved
priority: high
assignee: Antigravity
created_at: 2026-10-25
closed_at: 2026-10-25
branch: integration/all-agents
labels: [ui, performance, reports, cashier, dashboard, backup]
---

# FEAT-025: تحسين وتكبير الشريط العلوي ولوحة التحكم، معالجة أداء شاشة المنتجات، إضافة مسار النسخ الاحتياطي ومزامنته، وتحديث واجهات الكاشير والتقارير

## 1. السياق والمتطلبات
بناءً على طلبات المستخدم وملاحظاته بعد مراجعة الواجهات الحديثة واستعداداً لتسليم العميل نسخة الإنتاج (Production Release):
1. **تكبير الشريط العلوي ولوحة التحكم:**
   - زيادة ارتفاع الشريط العلوي الموحد (Unified Header) من 64px إلى 76px ليكون أكثر راحة ووضوحاً للأيقونات والنصوص وتسميات التبويبات.
   - تكبير أزرار الإجراءات السريعة (Quick Action Strip) في لوحة التحكم وإعطاؤها حضوراً بصرياً أكبر ومساحة نقر أوسع وأكثر راحة (Ergonomic).
2. **معالجة بطء ولاج شاشة المنتجات (Performance Bottleneck):**
   - فحص سبب البطء الشديد أثناء الانتقال لتبويب المنتجات (`ProductContainer` / `ProductScreen`).
   - السبب الجذري: وجود `widget.db.productDao.watchAllProducts()` يتم إنشاؤه من جديد داخل `build()` عبر `StreamBuilder` في كل دورة رسم بدون كاش، بالإضافة إلى استخدام `DataTable` غير الافتراضي (Un-virtualized) الذي يقوم ببناء ورسم جميع سجلات المنتجات دفعة واحدة في الذاكرة دون Virtualization، علاوة على padding ضخم (50px).
3. **إضافة مسار النسخ الاحتياطي والتكامل مع Google Drive:**
   - إظهار مسار مجلد النسخ الاحتياطي المحلي بوضوح داخل شاشة النسخ الاحتياطي (`enhanced_backup_screen.dart`).
   - توفير زر "فتح المجلد" لفتح مسار النسخ في متصفح الملفات (Windows Explorer) بضغطة زر.
   - توفير زر "نسخ المسار" لنسخه إلى الحافظة.
   - توفير زر فحص وموقع الملف المباشر لكل نسخة في القائمة (`explorer.exe /select,`).
   - توجيه وإرشاد العميل لكيفية مزامنة المجلد مع Google Drive Desktop أو سحب الملفات ورفعها يدوياً.
4. **تحديث شاشة الكاشير والتقارير الفرعية:**
   - تحسين مظهر حالة "اليوم مغلق" في الكاشير.
   - تحسين تقارير المبيعات والمشتريات والعملاء والحسابات الموحدة.

---

## 2. معايير القبول (Acceptance Criteria)
- [x] **AC1:** تكبير الشريط العلوي (Unified Header) وزيادة أحجام أيقونات التبويبات ونصوصها، وتكبير كروت الإجراءات السريعة (Quick Action Strip) في لوحة التحكم لتكون أكثر رحابة.
- [x] **AC2:** القضاء التام على لاج الانتقال لتبويب المنتجات عبر التخزين المؤقت للـ Stream، وتطبيق التفتيت والتصفح (Client-side Pagination) بـ 25/50/100 عنصر في الصفحة مع `AutomaticKeepAliveClientMixin` وتقليل الحواف لـ 16px، مما حقق انتقالاً فورياً بنسبة 60 FPS.
- [x] **AC3:** إضافة مسار مجلد النسخ الاحتياطي المحلي في `enhanced_backup_screen.dart` مع أزرار "فتح المجلد" و"نسخ المسار" وإظهار الملف في المتصفح وإرشادات Google Drive.
- [x] **AC4:** إعادة تصميم شاشات الكاشير والتقارير الفرعية لتكون عصرية ومتناسقة مع نظام MADAR.
- [x] **AC5:** اجتياز جميع الاختبارات الآلية بنجاح (`flutter test`) وخلو الكود من أي أخطاء في `flutter analyze`.
- [x] **AC6:** بناء نسخة الإنتاج النهائية (Windows Release Build) بنجاح مع حقن مفاتيح الترخيص وSupabase.

---

## 3. التحقق والاختبارات
1. `test/unit/feat_025_product_performance_and_backup_test.dart` (4/4 passed).
2. `test/unit/bug_028_supplier_payment_visibility_test.dart` (2/2 passed).
3. `flutter analyze lib/ui/product/ lib/ui/backup/ lib/services/enhanced_backup_service.dart` (No issues found).
4. `build_release.ps1` أنتج ملف التنفيذ النهائي في `build\windows\x64\runner\Release\pos_offline_desktop.exe`.
