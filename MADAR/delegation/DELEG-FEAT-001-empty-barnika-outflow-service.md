# DELEG-FEAT-001 — ربط خروج فوارغ البرانيك وقت البيع وتغطية اختبارات سحب الشحنات (FIFO)

> توثيق الميزة المنفذة بنظام التفويض متعدد الوكلاء (Multi-Model Delegation).

---

## 1. البيانات الأساسية

| الحقل | القيمة |
|---|---|
| **الرقم المرجعي** | DELEG-FEAT-001 |
| **عنوان الميزة** | ربط خروج فوارغ البرانيك وقت البيع وتغطية اختبارات سحب الشحنات (FIFO) |
| **النوع** | ميزة جديدة معمارية · اختبارات انحدار (Unit Tests) |
| **الأولوية** | P1 |
| **الحالة** | done |
| **الـ Flavor المتأثر** | vegetable |
| **الفرع** | `integration/all-agents` |
| **التاريخ** | 2026-10-26 |

---

## 2. طاقم الوكلاء المفوّض (Model Delegation Fleet)

| الدور | الموديل المعتمد | هل حدث Failover؟ | الموديل البديل المستخدم (إن وجد) |
|---|---|---|---|
| **التفكير والتخطيط المعماري** | Gemini 4 Argon / Pro Caliber (Antigravity Orchestrator) | ☐ لا ☐ نعم | — |
| **التنفيذ البرمجي والكتابة** | OpenCode Zen (`opencode/big-pickle` - Free Model) | ☐ لا ☐ نعم | تم التوجيه للموديل المجاني بدون استهلاك أي API مدفوع |
| **المراجعة والتدقيق النهائي** | كبير المعماريين + المطوّر | — | — |

---

## 3. محور التفكير والتخطيط المعماري (Thinking & Architecture Phase)

### 3.1 مين اللي فكّر؟ (The Thinking Model)
* **اسم الموديل:** Gemini 4 Argon / Deep Reasoning Architect (عبر جلسة Antigravity)
* **سبب اختياره لهذه المهمة:** فحص القيود المحاسبية لنظام الـ FIFO، وضمان سلامة حركات الفوارغ العهدية (`EmptyBarnikaTracking`) وتأصيل اختبارات دقيقة تمنع أي تراجع في العمليات الحسابية لمخزون الشحنات.

### 3.2 فكّر إزاي؟ (How the Thinker Analyzed the Problem)
* **تحليل المشكلة من الجذور (Root Problem Analysis):**
  البرانيك المباعة في سوق الخضار لها شقان:
  1. شق القيمة المالية لمحتوى الشحنة (يُسحب بنظام FIFO التنازلي حسب التاريخ).
  2. شق العبوة الفيزيائية (البرنيكة كعهدة يجب أن تعود من المشتري).
  الربط بينهما في خدمة موحدة ([`ShipmentAllocationService`](file:///g:/development/POS-Offline-Desktop-main/lib/core/services/shipment_allocation_service.dart)) يضمن تسجيل خروج الفوارغ للعميل وقت البيع (`recordBarnikaOut`) برقم تتبع مستقل وحالة `outstanding`.
* **القيود وثوابت النطاق (Domain Invariants):**
  1. السحب بنظام FIFO يرتب الشحنات تصاعدياً حسب التاريخ ويسحب فقط من الشحنات التي رصيدها `barnikaRemainingCount > 0`.
  2. دعم التجاوز اليدوي (`overrideShipmentId`) للسحب من شحنة محددة إن توفر فيها رصيد كافٍ.
  3. تسجيل خروج الفوارغ يبدأ بحالة `status = 'outstanding'` و `quantityReturned = 0`.
  4. أي كمية غير صالحة ($\le 0$) أو معرّف عميل فارغ يُرمى له فوراً استثناء `ArgumentError`.

### 3.3 عقد التسليم للمنفذ (Hand-off Contract)
* **الملف المستهدف:** `test/unit/services/shipment_allocation_service_test.dart`
* **المطلوب تنفيذه:**
  - إنشاء بيئة اختبار معزولة بالذاكرة (`AppDatabase(NativeDatabase.memory())`).
  - تغطية 16 حالة اختبار دقيقة لكافة دوال الخدمة:
    - السحب الآلي بنظام FIFO لشحنة واحدة ولشحنات متعددة.
    - السحب اليدوي (`overrideShipmentId`).
    - اعتراض الأخطاء (كميات صفرية، سالبة، أو غير كافية).
    - حساب الإجمالي المتبقي `totalRemaining()`.
    - تسجيل خروج الفوارغ `recordBarnikaOut()` والتأكد من إدراجها في Drift بالحالة الصحيحة.

---

## 4. محور التنفيذ البرمجي (Implementation Phase)

### 4.1 مين اللي نفّذ؟ (The Implementing Model)
* **اسم الموديل:** `opencode/big-pickle` (OpenCode Zen Free Model) عبر أداة الترحيل `opencode-delegate` (`relay.mjs`).
* **التكلفة المالية:** **\$0.00** (مجاني بالكامل عبر باقة Zen بدون استهلاك أي API مدفوع).

### 4.2 تنفّذ إزاي؟ (How the Implementer Coded the Solution)
* قام موديل `big-pickle` باستلام موجز المهمة (`brief-feat-001.txt`)، وقام ذاتياً بالآتي:
  1. قراءة كود الخدمة [`shipment_allocation_service.dart`](file:///g:/development/POS-Offline-Desktop-main/lib/core/services/shipment_allocation_service.dart).
  2. استعراض ملفات الاختبار القائمة في المشروع لمعرفة طريقة تهيئة `AppDatabase` بالذاكرة.
  3. قراءة `vegetable_shipment_dao.dart` لفهم نمط إدخال الشحنات التجريبية.
  4. كتابة ملف الاختبار الكامل:
     [`test/unit/services/shipment_allocation_service_test.dart`](file:///g:/development/POS-Offline-Desktop-main/test/unit/services/shipment_allocation_service_test.dart) بـ 283 سطراً من الكود المنضبط.
  5. تشغيل الاختبارات للتأكد من نجاحها قبل إنهاء الجلسة.

---

## 5. محور المراجعة والتحقق (Review & Quality Gates)

### 5.1 مراجعة الكود والـ Diff (Architectural Review)
* **نتيجة المراجعة:** الكود المكتوب من قبل `opencode/big-pickle` مطابق بنسبة 100% لمعايير المشروع:
  - استخدام `NativeDatabase.memory()`.
  - معالجة قنوات Flutter التجريبية (`MethodChannel('plugins.flutter.io/path_provider')`).
  - عزل البيانات التجريبية بـ `tearDown(() => db.close())`.
  - تغطية كافة الحالات الحدية (Zero, Negative, Insufficient, Empty CustomerId).

### 5.2 نتائج أوامر الفحص والتحقق الفعلية
| الأمر المُنفَّذ | النتيجة الحرفية | الحالة |
|---|---|---|
| `flutter test test/unit/services/shipment_allocation_service_test.dart` | **00:02 +16: All tests passed!** | ✅ ناجح (16/16) |
| `flutter analyze test/unit/services/shipment_allocation_service_test.dart` | **No issues found! (ran in 13.0s)** | ✅ ناجح |

---

## 6. خطة التراجع وسجل الحالة (Rollback & Audit)

* **خطة التراجع (Rollback Plan):** حذف الملف `test/unit/services/shipment_allocation_service_test.dart`.
* **سجل حركة الميزة:**

| التاريخ | الفاعل (الموديل / المطوّر) | الإجراء المتخذ |
|---|---|---|
| 2026-10-26 | Gemini Architect | صياغة العقد والمعمارية والموجز |
| 2026-10-26 | `opencode/big-pickle` | تنفيذ الكود والاختبارات بنجاح تام (\$0.00) |
| 2026-10-26 | Antigravity Orchestrator | التحقق بالأوامر والاعتماد النهائي |
