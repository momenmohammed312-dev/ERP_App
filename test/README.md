# POS System Test Files

هذا المجلد يحتوي على ملفات الاختبار لنظام POS.

## الملفات المتاحة

### 1. `quick_test_license.dart`
منشئ تراخيص اختبار سريع
```bash
dart run test/quick_test_license.dart
```
ينشئ 3 تراخيص اختبار:
- `basic_test_license.json` - ترخيص أساسي (30 يوم)
- `standard_test_license.json` - ترخيص قياسي (90 يوم) 
- `professional_test_license.json` - ترخيص احترافي (365 يوم)

### 2. `test_data_generator.dart`
منشئ بيانات اختبار شامل
```bash
dart run test/test_data_generator.dart
```
ينشئ ملفات JSON للبيانات:
- `test/fixtures/test_products.json` - 50 منتج اختبار
- `test/fixtures/test_customers.json` - 30 عميل اختبار
- `test/fixtures/test_suppliers.json` - 20 مورد اختبار
- `test/fixtures/test_sales_invoices.json` - 25 فاتورة مبيعات
- `test/fixtures/test_purchase_invoices.json` - 15 فاتورة مشتريات

### 3. `quick_test_runner.dart`
مشغل اختبارات سريع
```bash
dart run test/quick_test_runner.dart
```
يقوم بتشغيل اختبارات أساسية والتأكد من وجود ملفات الاختبار

## خطوات الاستخدام

1. **إنشاء تراخيص الاختبار:**
   ```bash
   dart run tools/licensing/quick_test_license.dart
   ```

2. **إنشاء بيانات الاختبار:**
   ```bash
   dart run test/test_data_generator.dart
   ```

3. **تشغيل الاختبارات السريعة:**
   ```bash
   dart run test/quick_test_runner.dart
   ```

## البيانات التي تم إنشاؤها

### المنتجات
- أسماء عربية وإنجليزية
- باركود فريد
- أسعار وتكاليف
- إدارة المخزون
- تصنيفات المنتجات

### العملاء
- أسماء عربية وإنجليزية
- معلومات الاتصال
- أرصدة أولية
- حدود ائتمانية

### الموردين
- معلومات المورد
- بيانات الاتصال
- تصنيفات الموردين

### الفواتير
- فواتير مبيعات (نقدية وآجلة)
- فواتير المشتريات
- تفاصيل المنتجات
- الخصومات والضرائب

## الاختبار اليدوي

بعد إنشاء الملفات، يمكنك:
1. تشغيل تطبيق POS
2. استيراد بيانات الاختبار
3. اتباع `TESTING_SOP.md` للاختبارات الشاملة
4. التحقق من جميع الوظائف

## التحقق من النتائج

- `test_report.json` - تقرير الاختبار التلقائي
- التحقق من صحة البيانات في التطبيق
- التأكد من عمل جميع الميزات

## ملاحظات

- جميع البيانات تم إنشاؤها للاختبار فقط
- يمكن تعديل السكريبتات حسب الحاجة
- تأكد من نسخ البيانات الاحتياطية قبل الاختبار
