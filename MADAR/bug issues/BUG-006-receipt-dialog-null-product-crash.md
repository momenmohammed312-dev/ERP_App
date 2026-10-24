# BUG-006: Customer-material receipt dialog crashes when a row has no product

- Status: done
- Priority: high (P1 - blocking operator flow)
- Area: Manufacturing (customer material receipts / custody)
- Commit: 851a42b

## 1. Symptom
While testing receipt CMR-2026-xxxx the operator searched for a raw material
in the items row, got "no matching results" (the material does not exist in
the products list), cleared the selection, entered quantity 100 and pressed
"register receipt". A red banner appeared:
`خطأ: Null check operator used on a null value`.

## 2. Environment
- Windows desktop, base flavor, debug build from feat/manufacturing-fixes.

## 3. Reproduction
Always (once the row has no selected product and a positive quantity):
1. Open customer-material receipt dialog (or New receipt).
2. Clear/auto-search and leave NO product selected for a row.
3. Enter received quantity > 0, choose customer, submit.

## 4. Root cause
`customer_material_receipt_list_screen.dart`:
- The items `SearchableProductPicker` was built WITHOUT a `validator`, so a
  row with `selectedProductId == null` passed `Form.validate()` silently.
- The submit path then built `ReceiptItemInput(productId: r.selectedProductId!)`
  a non-null assertion on a nullable field -> FlutterError
  "Null check operator used on a null value" caught into the error banner.
Related fact (by design, not the crash): the picker can only select products
that already exist in the products table; material brought by the customer
that is not a local product cannot be received at all.

## 5. Fix
- Added the missing picker validator: `v == null ? 'اختر المنتج أو الخامة' : null`.
- Defense in depth: explicit per-row guard before building inputs that
  surfaces a clear Arabic message instead of relying on `!`.

## 6. Regression test
- test/unit/customer_material_receipt_dialog_guard_test.dart (widget test):
  clears the seeded product, fills quantity, selects a customer, submits,
  and asserts (a) a visible 'اختر المنتج' error, (b) no 'Null check' text,
  (c) zero receipts written to the database.
  Result: flutter test -> 00:02 +1: All tests passed.
- flutter analyze on the changed file: no new issues.

## 7. Follow-up (feature, not this bug)
Receive material that is NOT an existing local product (create-on-the-fly
or allow productless custody lines) needs its own ticket with acceptance
criteria; custody balances are keyed by Product, so this needs a product
row to exist one way or another.

## 8. Closure checklist
- [x] Reproduced, root cause pinned to file:line
- [x] Fix is validation at the boundary (no symptom masking)
- [x] Regression test added and passing
- [x] No schema/migration changes
- [x] Money/stock paths untouched (no receipt was written in the failing case)