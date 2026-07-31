# خطة تنفيذ Flavor سوق الخضار — ERP_App

مرجع كامل لكل حاجة اتفقنا عليها. تنفيذ مرحلة مرحلة، كل مرحلة تتقفل قبل التانية.

---

## Phase 0 — Flavor Infra ✅ مكتمل

**الهدف:** فصل build سوق الخضار عن الأصل، بدون تكرار كود.

- [x] `lib/main_vegetable.dart` — entry point منفصل، بيمرر `Flavor.vegetable` للتطبيق
- [x] `lib/core/config/app_flavor.dart` — enum `Flavor { base, vegetable, clothing }`
- [x] `lib/core/config/app_features.dart` — feature flags:
  ```dart
  class AppFeatures {
    static bool get hasShipmentTracking => flavor == Flavor.vegetable;
    static bool get hasEmptyContainerTracking => flavor == Flavor.vegetable;
    static bool get hasCommissionPricing => flavor == Flavor.vegetable;
  }
  ```
- [x] DB name ديناميكي حسب flavor: `pos_vegetable` بدل الاسم الافتراضي
- [x] `--dart-define=FLAVOR=vegetable` في build command (Android/Windows)
- [x] تأكيد: نفس الجداول المشتركة (customers, suppliers, expenses, day, cash_session, ledger) شغالة بدون تعديل

**معيار القبول:** تطبيقين يشتغلوا من نفس الكود، DB منفصلة، الأصل مش اتأثر.

---

## Phase 1 — Database Schema

### 1.1 تسجيل الجداول والـDAOs في AppDatabase

**المشكلة الحالية:** الجداول `VegetableShipments` و `EmptyBarnikaTracking` والـDAOs بتاعتهم موجودين كملفات بس مش متسجلين في `@DriftDatabase`، يعني `build_runner` ما انتجش الكود بتاعهم.

- [x] إضافة `VegetableShipments` و `EmptyBarnikaTracking` لقائمة `tables:` في `lib/core/database/app_database.dart`
- [x] إضافة `VegetableShipmentDao` و `EmptyBarnikaTrackingDao` لقائمة `daos:` في `lib/core/database/app_database.dart`
- [x] تشغيل `dart run build_runner build --delete-conflicting-outputs` لإنتاج:
  - `vegetable_shipment_dao.g.dart` ✅
  - `empty_barnika_tracking_dao.g.dart` ✅
  - تحديث `app_database.g.dart` ✅ ($VegetableShipmentsTable + $EmptyBarnikaTrackingTable)

### 1.2 جداول موجودة (متوثقة):

**`vegetable_shipments`** (`lib/core/database/tables/vegetable_shipments_table.dart`):
```
id                      INTEGER PK (autoincrement)
supplierId              TEXT FK → Suppliers
shipmentNumber          TEXT (unique)
date                    DATETIME (default now)
pricingMode             TEXT — 'per_unit' | 'lump_sum' | 'commission'
totalBarnikaCount       INTEGER
costPricePerBarnika     REAL, nullable   — per_unit بس
lumpSumCost             REAL, nullable   — lump_sum بس
commissionPercentage    REAL, nullable   — commission بس
containerPrice          REAL, nullable   — سعر العبوة
totalCost               REAL
barnikaSoldCount        INTEGER (default 0)
barnikaRemainingCount   INTEGER
notes                   TEXT, nullable
```

**`empty_barnika_tracking`** (`lib/core/database/tables/empty_barnika_tracking_table.dart`):
```
id                  INTEGER PK (autoincrement)
customerId          TEXT FK → Customers
dateOut             DATETIME
quantityOut         INTEGER
dateReturned        DATETIME, nullable
quantityReturned    INTEGER (default 0)
status              TEXT (default 'outstanding') — 'outstanding' | 'partial' | 'returned'
```

### 1.3 تعديلات على جداول موجودة (مكتملة بالفعل):

- [x] `Invoices` → `shipmentId` INTEGER FK → vegetable_shipments, nullable
- [x] `InvoiceItems` → `shipmentId` INTEGER FK → vegetable_shipments, nullable
- [x] `InvoiceItems` → `commission` REAL DEFAULT 0 (موجود من v40)

### 1.4 Migration

- [x] Drift schema version bump: `50` → `51`
- [x] `onUpgrade` step جديد (`_runV51Migrations`) — يخلّي الجداول الجديدة تتخلق عند الترقية + يضيف `shipment_id` على Invoices و InvoiceItems لو مش موجود
- [ ] اختبار الترقية على نسخة تجريبية من DB قبل أي بيانات حقيقية

**معيار الق_acceptance:** DAO tests أساسية (insert/read) على الجداول الجديدة شغالة.

---

## Phase 2 — Business Logic

### 2.1 خدمة FIFO للسحب من الشحنات

**ملف جديد:** `lib/core/services/shipment_allocation_service.dart`

- [x] `allocate({required int requestedQuantity, int? overrideShipmentId})` → ترجع `List<ShipmentAllocation>` (كل entry فيها shipmentId + quantity to deduct)
- [x]逻辑: ترتيب الشحنات بـ`date` تصاعدي، السحب من الأقدم اللي `barnikaRemainingCount > 0`
- [x] توزيع تلقائي على أكتر من شحنة لو الكمية المطلوبة أكبر من شحنة واحدة
- [x] override يدوي: لو المستخدم اختار `overrideShipmentId`، يسحب من الشحنة دي بس (لو فيها كمية كافية)
- [x] Validation: لو الكمية المطلوبة أكبر من إجمالي المتاح، يرجع error واضح
- [x] `totalRemaining()` — إجمالي المتاح من كل الشحنات المفتوحة

### 2.2 حساب السعر حسب `pricingMode`

**ملف جديد:** `lib/core/services/shipment_pricing_service.dart`

- [x] `calculateCost(VegetableShipment shipment, int quantity)` → `double`
  - `per_unit`: return `costPricePerBarnika × quantity`
  - `lump_sum`: return `lumpSumCost / totalBarnikaCount × quantity` (تقريبية للتقارير)
  - `commission`: return `0` (المحل مش مالك البضاعة)
- [x] `calculateCommission(double sellAmount, double commissionPercentage)` → `double`
  - return `sellAmount × commissionPercentage / 100`
- [x] `calculateSupplierDue(double sellAmount, double commissionPercentage)` → `double`
  - return `sellAmount - commission`

### 2.3 تعديل InvoiceService

**ملف:** `lib/core/services/invoice_service.dart` — تعديل

- [x] إضافة parameter `primaryShipmentId` اختياري في `createInvoice()`
- [x] `InvoiceItemParams` بقى فيه `shipmentId` اختياري لكل سطر
- [x] لو الشحنة `commission`:
  - `InvoiceItems.commission` = `sellAmount × commissionPercentage / 100` (تلقائي) ✅
  - `supplierDue = sellAmount - commission` ✅
  - إنشاء `LedgerTransactions` entry: `entityType: 'Supplier', origin: 'sale', debit: supplierDue` ✅
- [x] تحديث `barnikaSoldCount += quantity` و `barnikaRemainingCount -= quantity` في transaction واحدة مع الفاتورة ✅
- [x] لو فشل أي جزء → rollback كامل (بتاعت Drift transactions) ✅
- [x] Backward compatible — كل البارامترات الجديدة optional

### 2.4 Empty barnika logic

- [ ] `EmptyBarnikaTrackingDao.recordReturn()` موجود بالفعل ✅
- [ ] إضافة method في `ShipmentAllocationService` أو مكان مناسب لتسجيل خروج اختياري وقت البيع
- [ ] `status` يتغير تلقائي: `outstanding` → `partial` → `returned` (موجود في DAO) ✅

**معيار القبول:** unit tests على منطق FIFO + حساب العمولة + تحديث الكميات.

---

## Phase 3 — UI Screens

### 3.1 Dashboard — تعديل موجود

**ملف:** `lib/ui/home/modern_home.dart` — تبويس Dashboard (index 0)

- [ ] كارت: برانيك متبقية بالمخزن (إجمالي كل الشحنات المفتوحة) — query من `VegetableShipments` حيث `barnikaRemainingCount > 0`
- [ ] كارت: مديونيات آجل مستحقة اليوم — query من `LedgerTransactions`
- [ ] كارت: صافي كاش متوقع لسه ما اتقفلش — من `BusinessDateService`
- [ ] كارت: مستحق للموردين (شحنات commission) — من `LedgerTransactions` حيث `origin = 'sale'` و `entityType = 'Supplier'`
- [ ] زرار "شحنة جديدة" + "بيع جديد" (موجود: "فاتورة جديدة" ✅)

**ملاحظة:** الـdashboard الحالي فيه 4 كروت مبيعات/مشتريات/مصروفات/صافي. نضيف الكروت الجديدة في vegetable flavor بس.

### 3.2 شاشة الشحنات — جديدة بالكامل

**ملف جديد:** `lib/ui/shipments/shipments_screen.dart`
**ملف جديد:** `lib/ui/shipments/widgets/shipment_form_dialog.dart`
**ملف جديد:** `lib/ui/shipments/widgets/shipment_detail_screen.dart`

- [ ] List screen: مورد / تاريخ / نمط تسعير / عدد برانيك (كلي/متبقي) / تكلفة
- [ ] فورم "شحنة جديدة": أول اختيار (3 أزرار) نمط التسعير → الفورم يتغير حسب الاختيار:
  - per_unit → سعر البرنيكة + عدد
  - lump_sum → مبلغ مقطوع + عدد
  - commission → نسبة % + عدد
- [ ] فتح شحنة → كل الفواتير اللي سحبت منها (traceability كامل)
- [ ] شرط ظهور: `AppFeatures.hasShipmentTracking` (vegetable flavor بس)

### 3.3 شاشة البيع (POS) — تعديل موجود

**ملف:** `lib/ui/invoice/widgets/enhanced_new_invoice_page.dart` — تعديل

- [ ] اختيار عميل / عميل سريع جديد (موجود ✅)
- [ ] عدد برانيك → FIFO تلقائي مع override يدوي (إضافة widget للـPOS)
- [ ] لو الشحنة commission → خانة نسبة العمولة تتعرض تلقائي + "مستحق للمورد: X ج" قبل التأكيد
- [ ] سعر البيع قابل للتعديل لحظة البيع (موجود ✅)
- [ ] طريقة الدفع: كاش / آجل / جزئي (موجود ✅)
- [ ] خانة اختيارية: تسجيل خروج برانيك فاضية لنفس العميل

### 3.4 شاشة العملاء والآجل — تعديل موجود

**ملف:** `lib/ui/customer/` — تعديل الشاشات الموجودة

- [ ] List بالمديونية الحالية لكل عميل (موجود جزئي)
- [ ] فتح عميل → تاريخ فواتير + دفعات جزئية (`InvoicePayments`) + زرار "تسجيل دفعة" (مع خيار خصم)
- [ ] فلتر "مستحق اليوم" / "متأخر"

### 3.5 شاشة البرانيك الفاضية — جديدة

**ملف جديد:** `lib/ui/empty_barnika/empty_barnika_screen.dart`

- [ ] List بكل عميل عليه كمية برا لسه (query من `EmptyBarnikaTracking` حيث `status != 'returned'`)
- [ ] تسجيل رجوع بضغطة → `EmptyBarnikaTrackingDao.recordReturn()`
- [ ] إقفال تلقائي عند التساوي (status → 'returned')

### 3.6 شاشة المصروفات — موجودة ✅

**ملف:** `lib/ui/expense/` — موجود بالفعل، تصنيف سريع (نقل / أكل عمال / أخرى)

### 3.7 شاشة تسليم/تحصيل آخر اليوم — جديدة بالكامل (أهم شاشة)

**ملف جديد:** `lib/ui/day_settlement/day_settlement_screen.dart`

**العرض التلقائي (computed، بدون تدخل يدوي):**
| البند | المصدر |
|---|---|
| إجمالي مبيعات كاش النهاردة | `Invoices` حيث `date = today` و `cashAmount > 0` |
| إجمالي تحصيل آجل النهاردة | `InvoicePayments` حيث `paidAt = today` و `paymentMethod = cash` |
| إجمالي مصروفات النهاردة | `expenses` حيث `date = today` |
| **صافي الكاش المتوقع** | `= مبيعات كاش + تحصيل آجل − مصروفات` |
| مستحق للموردين (commission) | من `LedgerTransactions` — عرض فقط |

**إدخال يدوي:**
- [ ] خانة "الكاش الفعلي المعدود" (input رقم)
- [ ] الفرق `= الفعلي − المتوقع` يتعرض تلقائي (لون أخضر لو صفر، أحمر لو فيه فرق)
- [ ] خانة ملاحظة حرة + مبلغ اختياري لـ"تسوية/فاتورة كبيرة" — `settlement entry` منفصل
- [ ] زرار "قفل اليوم" → بيحفظ في `day_table` + `cash_session_table` + `audit_log_table`
- [ ] بعد القفل: لا تعديل على فواتير/مصروفات بتاريخ اليوم (immutability)
- [ ] خيار طباعة/تصدير ملخص القفل

**ملاحظة:** شاشة Day Closing الحالية في `BusinessDateService.closeSession()` والشاشة الموجودة في `ui/day/` ممكن نوسّعها بدل ما نعمل شاشة جديدة من الصفر.

### 3.8 شاشة استيراد إكسل — جديدة

**ملف جديد:** `lib/ui/import/excel_import_screen.dart`

- [ ] زرار "استيراد من إكسل" — يقبل شيت موردين/زباين/مصروفات/شحنات
- [ ] Idempotent import: matching بـ`shipmentNumber` (شحنات) و composite key للمبيعات
- [ ] Preview قبل التأكيد: عرض الصفوف الجديدة اللي هتتضاف بس
- [ ] الدفعات الجزئية بعد الاستيراد من التطبيق نفسه

**معيار القبول:** رفع نفس الملف مرتين → صف واحد بس لكل شحنة/عميل، مفيش تكرار.

---

## Phase 4 — Testing & Rollout

- [ ] اختبار الترقية (migration) على نسخة حقيقية من بيانات الأصل — تأكيد الأصل (base flavor) لسه شغال 100%
- [ ] اختبار سيناريو كامل: شحنة per_unit → بيع كاش وآجل → دفعة جزئية → إرجاع برنيكة فاضية → قفل يوم
- [ ] اختبار سيناريو commission: شحنة commission → بيع → تأكد `LedgerTransactions` صح
- [ ] اختبار import الإكسل بالملف الحقيقي، مقارنة يدوية بالنتيجة
- [ ] اختبار FIFO: شحتين مختلفتين، بيع كمية أكبر من الأولى → يتوزع على الاتنين
- [ ] اختبار atomicity: لو حدث خطأ وقت تحديث كمية الشحنة → rollback كامل للفاتورة

---

## تنفيذ مقترح (أولوية مرحلة بمرحلة):

### المرحلة الأولى (الأقرب):
1. تسجيل الجداول + DAOs في `AppDatabase` + `build_runner`
2. خدمة `ShipmentAllocationService` (FIFO)
3. خدمة `ShipmentPricingService` (حساب السعر)

### المرحلة التانية:
4. تعديل `InvoiceService` للدعم الفاتورة بالشحنات + العمولة
5. شاشة الشحنات (CRUD كامل)
6. تعديل POS لدعم الشحنات

### المرحلة التالتة:
7. شاشة البرانيك الفاضية
8. شاشة التسوية آخر اليوم
9. تعديل Dashboard بالكروت الجديدة
10. شاشة استيراد الإكسل

### المرحلة الرابعة:
11. تعديل شاشة العملاء للآجل
12. اختبارات شاملة
13. اختبار الترقية + rollouptml
