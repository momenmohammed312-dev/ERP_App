# FEAT-039 — MADAR Universal Manufacturing Engine — الخطة الجذرية

> القرارات الأساسية (D-01 … D-11) — نقشتها في محادثة الاكتشاف وتم اعتمادها 2026-11-22.
> طالما هناك وكيل يتوكل، هذا الملف هو المصدر الوحيد للحقيقة: المعادلات المصالحة، نموذج الـRouting، سياسة الموافقة، المراحل، التكلفة، الفوترة، وترتيب تنفيذ المراحل.

## 1. القرارات الجذرية المثبّتة

### D-01 — النطاق الأولي: `for_others` فقط
`mixed` فرع منه (FEAT-004: "mixed IS a form of for-others"). `internal` لا يُلمس (no base-flavor touch without explicit ask). `service_only` — غير قابل للوصول من الواجهة (exists in enum, unreachable) — يُستبعد.

### D-02 — الخامات الزائدة ترجع لعهدة العميل
`Issued = Consumed + ReturnedExcess + CustodyRemaining` (صيغة مصالحة الخامات المخصصة، أنظر §3).

### D-03 — الصرف بالتقدير ثم مطابقة بعد التنفيذ
تسجيل `ConsumptionRecord` فعلي بعد الإنتاج (التسجيل = تقرير تحليلي مرتبط للحركة المخزنية، وليس تعديل إجمالي).

### D-04 — خامات إضافية يوفرها المصنع → تُضاف للفاتورة
`generateServiceInvoice` بيسجل `extra_material` lines مع `authorizationRef` — **فقط لو حصل اعتماد عميل**.

### D-05 — تعديل D2 (استثناء مسموح)
المصاريف الإضافية مسموحة في `pricingMode = inclusive` — **بشرط موافقة عميل مرتبطة بأمر التشغيل** — وتظهر صراحة في الفاتورة.

### D-06 — Routing: متوازي + Rework + عمل خارجي + مخرجات متعددة — كلها مطلوبة

### D-07 — معيار القبول = تقدير المشرف/العامل (لا عينة معتمدة/رسم ملزم)
تسجيل حدث فحص + شخص قراره + نتيجة + سبب rework — بدون قياس التفاوتات.

### D-08 — قيمة المصروف الإضافي = تكلفة فعلية (`costPrice` snapshot) + هامش **default = 0**
(أ) الزيادة `costPrice` × الكمية من `Products.costPrice` — عدم الاعتماد على `price` الحالي (فجوة: `manufacturing_delivery_dao.dart:324`).
(ب) أو سعر بيع متفق عليه مسبقاً (سعر ثابت معلوم للعميل).
(ج) أو مبلغ يكتبه العميل في إذن الموافقة.
→ مختار (أ) — تكلفة فعلية + هامش optional zero-default.

### D-09 — كل المستندات مربوطة بعملاء فعليين (Customers table) — وحقائق.

### D-10 — العميل يحصل: إذن استلام (CMR) + DN + فاتورة بالسعر النهائي فقط
التفاصيل (التقارير/التكلفة/المراحل/الصور) — داخلي للإدارة (لا تصدر للعميل أبداً).

### D-11 — MVP Internal Costing: (1) تكلفة فعلية إجمالية · (2) مخطط vs فعلي · (3) هامش فعلي · (4) كفاءة لكل مرحلة (Stage Yield)

---

## 2. المعادلات المصالحة (Corrected — per user review)

### 2.1 خامات العميل (Custody-held products)

```text
Issued (accepted into custody + subsequent) = Consumed + ReturnedExcess + Remaining(custody)
```

> **توضيح التنفيذ (قرار المستخدم 2026-11-22 — A1):** المعادلة تُحسب **لكل منتج خام على حدة** ولخامات العميل فقط (`CustodyLine` في `ReconciliationDao`):
> - `Issued` = حركات `CustomerStockMovements` للأمر (`movementType` في `issued_to_order` / `manufacturing_consumption`، و`referenceId` يطابق `mo.orderNumber` أو `mo.id.toString()`).
> - `Consumed` = `ConsumptionRecords` حيث `ownershipType == 'customer_owned'`.
> - `ReturnedExcess` = حركات `CustomerStockMovements` من النوع `return_excess` (نقطة توسعة لـ D-02 — لا يوجد مسار يكتب هذا النوع بعد).

### 2.2 خامات المصنع (Factory-owned products)

```text
Issued = Consumed + Remaining(factory inventory)
```

### 2.3 الفرغ الجوهري — **كل وحدة دخلتها عقود منظور واحد فقط:**

```text
Closed unit → exactly ONE of:
  a. Consumed          (stock movement type: manufacturing_consumption / issue)
  b. RemainingWIP      (not yet produced — inside an in_progress OperationInstance)
  c. ExcessReturn      (custody — D-02)
  d. DeliveredToCustomer (DN — the goods moved to the customer)
  e. Lost              (scrap — manufacturing_scrap + movement)
  f. AtExternalVendor  (ExternalOperation — sent, not yet received back)

At closure (Order completed + all stages done):
  RemainingWIP + AtExternalVendor == 0 must hold.
```

> **ملاحظة (قرار المستخدم 2026-11-22 — A2):** `Lost` هو تصرّف نهائي مقبول ولا يمنع الإقفال.

### 2.4 المنتج النهائي (قانون "لا تضع القطعة مرتين")

```text
produced = Σ( outputs on the LAST operations of the Routing, by outputType: primary/co_product )
         − ( scrap of primary from last operations )

Σ(all other operations' outputs) ≠ produced   ← intermediate stages, then rework — NOT added to good
```

### 2.5 المصالحة في الصرف (Scenario B/C/D, أوقف الصرف بعد التنفيذ)

```text
Issued = Consumed + ReturnedExcess + Remaining(custody)            ← perfect when factory returns exactly the difference
For mixed: Consumed(customer) = Σ per line ownership; Consumed(factory) = Σ factory lines
Overconsumption → factory absorbs OR is explicitly authorized as extra_material to the customer (D-04) — single disposition, no overlap with scrap.
```

---

## 3. النموذج العام: Routing (غير خاص بصناعة محددة)

### 3.1 Entity: RoutingTemplate (مستقل عن BOM)

```dart
class RoutingTemplate {
  int id;
  String code;               // RT-2026-01
  String name;               // e.g. "T-shirt: طباعة على قماش سابق"
  int? productId;            // optional — بيقع على قطعة الأم
  // Routing execution primitives:
  List<RoutingNode> operations;
}

class RoutingNode {
  int id;
  RoutingNode? parent;          // parallel branches
  List<RoutingNode> children;   // next operations in sequence
  String operationType;         // machining | decoration | assembly | finishing | inspection | external
  String technique;             // cnc_turning | embroidery | screen_print | heat_transfer | NULL (generic)
  Map<String, dynamic> parametersJson;  // versioned JSON per technique (stitch count, screens, tolerances...)
  String name;                  // e.g. "طباعة منكوك"
  String status;                // template: pending | active | inactive
}

class RoutingInstance (per ManufacturingOrder) {
  int orderId;
  String routingCode;               // نسخة استقلالية — تغيير RoutingTemplate لا يغيرها
  Map<String, OperationInstance> operations;  // بالإصدار
}

class OperationInstance {
  int id;
  int orderId;
  RoutingNode nodeId;               // reference to template node
  OperationStatus status;           // planned | in_progress | completed | rework | cancelled
  double inputQuantity;             // quantity that entered the operation
  double outputQuantity;            // good output (already rework-free)
  double scrapQuantity;             // lost here (adds to manufacturing_scrap + custody movement for customer pieces)
  double stageCost;                 // labor+machine+external attributed
  List<ExternalOperationRecord> externalOps; // عمل خارجي
  DateTime? startedAt, completedAt;
  double workHours;                 // لقياس كفاءة العامل
}

class Output {   // on the LAST operations — what ships / is deliverable
  int id;
  int orderId;
  int routingInstanceOperationId;
  int productId;                    // المنتج (primary/co_product بعكس بانتخاب product_type)
  int? variantId;
  double plannedQuantity, producedQuantity, scrapQuantity;
  String outputType;                // primary | co_product | by_product | waste — تصنيف مخرجات (D-6-4)
  double unitCostSnapshot, estimatedSellPrice;
}

class ExternalOperationRecord {
  int id;
  int orderId;
  int operationId;
  String vendor;                    // NOT NULL
  double sentQty, receivedQty, scrapQty;
  double cost;                      // external processing cost
  DateTime sentAt, receivedAt;
}

class ReworkRecord {               // operationId: الأصل الذي أُعاد تشغيله
  int id;
  int originalOperationId;
  int reworkOperationId;
  double qty;
  String reason, dispositionNote;
  DateTime reworkedAt;
}

class OperationInput / OperationOutput (التدقيق: حركات الكمية لكل عملية) — optional
```

### 3.2 Lifecycle / State Transitions

```text
Operations:   planned → in_progress → completed (→ rework → completed) ; cancelled
Order:        planned → in_progress → production_completed (MoDetailScreen now!)
                              → partially_delivered → delivered → invoiced → cancelled
```

### 3.3 Routing Copy + freeze (كل أمر يحصل على نسخة قابلة للتنفيذ)

- `RoutingInstance` + `OperationInstance` rows are **written at order creation** (bulk copy with version).
- Editing `RoutingTemplate` afterwards must NOT touch `RoutingInstance` rows.
- `producesQuantity` reconciliation: `Σ(OperationInstance.outputQuantity on last ops)`.

---

## 4. الجودة (D-07)

```dart
class InspectionRecord {   // new entity — audit only, no variance engine
  int id; int orderId; int operationId; int productId;
  DateTime inspectedAt;
  String inspectedBy;              // حقل حر — D-07
  String result;                   // accepted | rejected_for_rework | second_grade
  double qty;
  String dispositionNote;          // عينة/رسم/تقدير لا موصّل
  String photoRefs;                // D-10: internal only — paths on disk
}
```

---

## 5. التكلفة — النصوص (قبل ابدأ الكود — محددة لقطع العطلة الأولى في الحساب)

| المكون | النص |
|---|---|
| Material | `Σ(ConsumptionRecord.actualQty × unitCostSnapshot)` — **customer products: value = 0.0** (value never counted in factory cost) |
| Labor | `Σ(stage.laborHours × laborRate)` — الوظيفة على OperationalInstance.workHours |
| Machine/Operation | `Σ(stage.machineHours × machineRate)` |
| External | `Σ(ExternalOperationRecord.cost)` |
| Other approved | `Σ( manufacturing_cost_components (fixed/%/per_unit) )` — **نفسه كيوم الـcost_component_dao.computeAmount — for reuse. What about `operationType` vs `technique`? Standalone operation without technique — generic 'custom' or 'generic'. Same as today.
  - `Issued = Consumed + ExcessReturn + Remaining(custody)` (customer product) — before completion gate, Remaining ≥ 0.
  - Order completion gate: `producedQuantity ≤ plannedQuantity` for for_others; `≤ inputQuantity` for JW-style (construction assertion — always for_others now).
  - For customer-owned products: also assert `Consumed - Scrapped(customer) - Delivered(available) ≥ 0`... (skip, complexity)
  
4. Phase 3 — Costing & Billing:
   - `CostSnapshot` table (freeze per order: material/labor/machine/external/other, totalActual, variance = planned−actual, margin = delivered+extras−compensation − totalActual)
   - `generateServiceInvoice`: read from CostSnapshot if exists (freeze); else compute on the fly (non-frozen) — for new features.
   - Invoice line: extra_material lines (via approval records).
   - Impact on Phase 1 completion gate.
   
   Conflict note: Costing/Billing (Phase 3) naturally extends/modifies Phase 1 reconciliation (excess returns that need accounting). We want to finalize mutual exclusions in Phase 3.
   
5. Phase 4 — Quality & Reports:
   - InspectionRecord, StageYield, reports refresh.
```

## 8. Customer Delivery & Billing — المصروفات الإضافية (approval audit fields)

```dart
class ExtraMaterialApproval {
  int id;                          // للتتبع
  int orderId;
  String productId;                // الخام الإضافي
  double quantity;                 // == ExternalOperationRecord.costedQty (reconciliation by qty)
  String status;                   // pending | approved | rejected
  String requestedBy;              // supervisor (يطلب المصروف — D-5)
  String approvedBy;               // customer — وليمة يحتاج تفكير)
  String approvedAmount;           // actualCost × (1 + margin) — نص (ديسك سابق من approvedBy)
  DateTime? approvedAt;
  int? reference;                  // نقطة مرجع (مثلاً رقم علم قاميز الصرف)
}
```

## 9. Staging — What Executes When

| Phase | What | Files |
|---|---|---|
| 0 — Foundation | Fix migration_v80_unified_test (version-agnostic) + add migration_v81_manufacturing_test.dart | test/unit/ |
| 1 — Material Reconciliation | ConsumptionRecord + CustodyMovement('return_excess') + completion gate (produced ≤ planned) + Consumed-in-Movement linkage | lib/core/database/tables/consumption_record.dart, lib/core/database/dao/*, lib/ui/manufacturing/mo_detail_screen.dart |
| 2 — Universal Routing | RoutingTemplate/RoutingInstance/OperationInstance/Output/ExternalOperationRecord/ReworkRecord + A6 | lib/core/database/tables/*, migration v82, backup/restore, tests |
| 3 — Costing & Billing | CostSnapshot + ExtraMaterialApproval + extra_material invoice lines | lib/core/database/tables/cost_snapshot.dart, manufactureApproval, lib/ui/manufacturing/* |
| 4 — Quality & Reports | InspectionRecord + StageYield + Reports screen refresh | lib/ui/manufacturing/reports/* |

**Phase 1 — Batch 2 files:**
- Tables (v82): `lib/core/database/tables/consumption_record.dart`, `lib/core/database/tables/stage_yield.dart`, `lib/core/database/tables/external_operation_records.dart` (+ `manufacturing_orders_table.dart`, `manufacturing_stages_table.dart`)
- DAOs & DB: `lib/core/database/dao/consumption_record_dao.dart`, `stage_yield_dao.dart`, `external_operation_dao.dart`, `reconciliation_dao.dart`, `manufacturing_order_dao.dart` (gates), `manufacturing_scrap_dao.dart` (scrap cap + Lost movement), `lib/core/database/app_database.dart` (v82), `lib/core/services/backup_service.dart`
- Tests: `test/unit/dao/consumption_record_dao_test.dart`, `stage_yield_dao_test.dart`, `external_operation_dao_test.dart`, `reconciliation_dao_test.dart`, `test/unit/manufacturing_for_others_completion_test.dart` (gates + scrap cap), `test/unit/migration_v82_manufacturing_test.dart`

**Phase 1 — Batch 3 files:**
- Schema & Backup (v83): `lib/core/database/tables/consumption_record.dart` (`customer_stock_movement_id` FK), `lib/core/database/app_database.dart` (v83 migration + `idx_consumption_records_custody_move`), `lib/core/services/backup_service.dart` (`restoreOrder` places `consumption_records` after `customer_stock_movements`)
- DAOs: `lib/core/database/dao/consumption_record_dao.dart` (`customerStockMovementId`), `lib/core/database/dao/manufacturing_order_dao.dart` (`completeForOthersOrder` JW/main/mixed/same-product writes `ConsumptionRecords` + `productionCompletedAt`), `lib/core/database/dao/customer_material_receipt_dao.dart` (`returnExcessFromOrder` / `return_excess` + `returnCustodyToCustomer` / `return_custody`)
- UI (Mobile + Desktop, Light/Dark): `lib/ui/manufacturing/widgets/mo_reconciliation_section.dart`, `lib/ui/manufacturing/mo_detail_screen.dart`
- Tests: `test/unit/migration_v82_manufacturing_test.dart`, `test/unit/migration_v83_manufacturing_test.dart`, `test/unit/dao/customer_excess_and_custody_return_test.dart`, `test/widget/mo_reconciliation_section_test.dart`

**Phases 2, 3 & 4 (Schema v84) files:**
- Tables (v84): `lib/core/database/tables/routing_tables.dart` (`RoutingTemplates`, `RoutingTemplateNodes`, `ManufacturingReworkRecords`), `lib/core/database/tables/manufacturing_costing_tables.dart` (`ManufacturingCostSnapshots`, `ExtraMaterialApprovals`), `lib/core/database/tables/manufacturing_inspections_table.dart` (`ManufacturingInspections`), plus extensions in `lib/core/database/tables/manufacturing_orders_table.dart` (`routingTemplateId`, `routingCode`) and `lib/core/database/tables/manufacturing_stages_table.dart` (`rework`/`cancelled`, routing/node/parent/costing params, `isTerminal`, `outputType`)
- DAOs, DB & Backup: `lib/core/database/dao/routing_dao.dart`, `lib/core/database/dao/manufacturing_costing_dao.dart`, `lib/core/database/dao/manufacturing_inspection_dao.dart`, `lib/core/database/dao/manufacturing_stage_dao.dart` (auto `StageYieldRecord` + params + `outputType`), `lib/core/database/dao/manufacturing_delivery_dao.dart` (approved `ExtraMaterialApprovals` billing in `inclusive`/`separate` + auto-freeze `ManufacturingCostSnapshot` while preserving BOM `separate` line behavior), `lib/core/database/app_database.dart` (`schemaVersion => 84`, idempotent `_runV84UniversalManufacturing` & `_ensureV84Indexes`), `lib/core/services/backup_service.dart` (`tables` + `tableOrder` for all 6 v84 tables)
- UI & Router (Mobile + Desktop, Light/Dark): `lib/ui/manufacturing/routing_templates_screen.dart`, `lib/ui/manufacturing/widgets/mo_routing_quality_section.dart`, `lib/ui/manufacturing/widgets/mo_costing_approvals_section.dart`, `lib/ui/manufacturing/reports/widgets/manufacturing_yield_quality_tab.dart`, `lib/ui/manufacturing/reports/manufacturing_reports_screen.dart` (5th tab + responsive PDF dialog/date bar), `lib/ui/manufacturing/mo_list_screen.dart`, `lib/ui/manufacturing/mo_detail_screen.dart`, `lib/core/router/go_router.dart` (`/manufacturing/routings`)
- Tests: `test/unit/migration_v84_manufacturing_test.dart`, `test/unit/dao/routing_dao_test.dart`, `test/unit/dao/costing_and_billing_feat039_test.dart`, `test/unit/dao/manufacturing_inspection_dao_test.dart`, `test/unit/manufacturing_feat039_e2e_test.dart`, `test/widget/manufacturing_universal_ui_test.dart`

## 10. Regression & Safety

- **Sensitive zones:** Manufacturing, Ledger/Accounts (invoice lines), Cash/Backup — atomic transactions + regression tests (AGENTS.md §7.2).
- **Backup:** `backup_service.dart` + `restore_order` — add new tables to both lists; J3-style test.
- **Migration:** v82 — idempotent (`CREATE TABLE IF NOT EXISTS` + `safeAddColumn` pattern from v81), wind-back test pattern.
- **No double counting:** single disposition per unit (§2.3).

## 11. Open / Deferred Decisions

- O-1: Tolerance of `actualQty` vs movement? — 1% tolerance, clamp, logged.
- O-2: Invoice format — one invoice per order, invoice # is `formatInvoiceNumber(orderId)`, linked from `ManufacturingOrders.invoiceId`. (deferred — decided later.)
- O-3: How to handle invoice **partial-then-complete** (L9 accepted) — Part of Phase 3.

---

## Revision Log

| Date | Change |
|---|---|
| 2026-11-22 | D-01..D-11 — decisions from discovery session |
| 2026-11-22 | Corrected reconciliation identity — Customer-owned: Issued = Consumed + ReturnedExcess + Remaining (D-02) |
| 2026-11-22 | Added: `Consumed` = inventory_consumption movement (custody move), ConsumptionRecord = analytical log, stockMovementId links them (no double count) |
| 2026-11-22 | Phase reorder: 0 (foundation) → 1 (Material Reconciliation) → 2 (Universal Routing) → 3 (Costing & Billing) → 4 (Quality & Reports) |
| 2026-11-22 | Defined **ProductionCompleted** order status for partial delivery (removed Parts Delivered from MVP unless required) |
| 2026-11-22 | Added OutputType (primary/co_product/by_product/waste) distinction — by_products separated, not double counted |
| 2026-11-22 | **Phase 1 Batch 2 results:** Fixed DAO compile errors, updated v82 codegen (`build_runner` 790 outputs), and applied user decisions A1 (per-product customer custody via `CustomerStockMovements` + `customer_owned` `ConsumptionRecords`), A2 (closure gate b = `RemainingWIP + AtExternalVendor == 0`, `Lost` accepted), and A3 (`recordOrderScrapWithPolicy` cumulative scrap cap `<= producedQuantity` on finished good). `ReconciliationDao` is implemented & tested but not yet wired into any completion/UI flow. Verification: `flutter analyze` 0 errors on DB/backup & 0 issues on 5 test files; 37/37 new/gate tests passed; 174/174 regression tests across 25 files passed. |
| 2026-11-22 | **Phase 1 Batch 3 results:** Applied user decisions A1 (Schema v83 append-only migration adding `customer_stock_movement_id` FK on `consumption_records` + `BackupService.restoreOrder` updated), A2 (`returnExcessFromOrder` `+return_excess` with D-03 automatic `ConsumptionRecord.actualQty` trim + `returnCustodyToCustomer` `-return_custody`), and A3 (responsive Mobile/Desktop & Light/Dark `MoReconciliationSection` widget + `MoDetailScreen` overflow/theme/PDF fixes). Wired `completeForOthersOrder` (JW + main + mixed + same-product) to emit linked `ConsumptionRecords` and `productionCompletedAt`, and wired `ReconciliationDao` + `ConsumptionRecordDao` into `MoDetailScreen`. Verification: `build_runner` 798 outputs; `flutter analyze` 0 errors & 0 warnings across all 11 modified/new files; 5/5 widget tests (`Mobile Light/Dark`, `Desktop Light/Dark`, excess dialog) + 186/186 full regression tests across 29 files (incl. `v80..v83`, `backup_tables_test`, all manufacturing & DAO tests) passed. |
| 2026-11-22 | **Phases 2, 3 & 4 (Schema v84) results:** Completed Universal Routing (`RoutingDao`, `/manufacturing/routings` responsive Mobile/Desktop & Light/Dark `RoutingTemplatesScreen`, parallel branches, template freeze, `rework` stages, `isTerminal` §2.4 produced-qty anti-double-count, `ExternalOperationRecords` + `ReworkRecords`), Costing & Approved Billing (`ManufacturingCostingDao`, `ExtraMaterialApprovals` D-04/D-05/D-08 with customer approval & cost snapshot billed in `generateServiceInvoice` for both `inclusive` & `separate` + auto-frozen `ManufacturingCostSnapshots`), and Quality & Yield Reports (`ManufacturingInspectionDao` D-07 supervisor/worker judgment, auto `StageYieldRecord` in `updateStageStatus`, 5th reports tab `ManufacturingYieldQualityTab`, plus `MoRoutingQualitySection` & `MoCostingApprovalsSection` in `MoDetailScreen`). Schema `v84` idempotent migration + `BackupService` parity verified. Added full E2E + validation guard suite in `test/unit/manufacturing_feat039_e2e_test.dart` (3/3 passed). Verification: `build_runner` 840 outputs; `flutter analyze --no-fatal-infos` across all 25 Wave 1/2 files + `manufacturing_feat039_e2e_test.dart` = **0 errors, 0 warnings** (16 pre-existing `info` lints in untouched sections of `mo_detail_screen.dart`); full post-final-edit regression suite = **208/208 passed across 36 test files** (incl. `v79` + `v80..v84`, `manufacturing_feat039_e2e_test`, `routing_dao_test`, `costing_and_billing_feat039_test`, `manufacturing_inspection_dao_test`, `backup_tables_test`, `mo_reconciliation_section_test`, and 8/8 `manufacturing_universal_ui_test` across Mobile/Desktop & Light/Dark). |

**Registry of files to update per phase:** base flavor untouched; only lib/core/database + lib/ui/manufacturing + tests. Each phase: 1 ticket update + phase result → user review.
