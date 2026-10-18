# FEAT-007 - Custody Memory: searchable finished picker + recipe defaults (FEAT)

- **Status:** open
- **Priority:** High
- **Area:** Manufacturing (BOM, Receipts-first flow) - Sensitive Zone
- **Worktree:** wt_manufacturing_fixes / feat/manufacturing-fixes

## Request

Receipt-first flow: after the customer custody product is picked, it should
save automatically onto the received-from-customer product line, the recipe
finished-product must be searchable by name, and the yield must default from
the received quantity (received minus defective is what we owe back).

## Root cause (2 blockers in the user flow)

1. `bom_form_dialog.dart`: finished product used a plain `DropdownButtonFormField` -
   a large catalog cannot be searched (user screenshot #1).
2. `bom_dao.dart` `insertBomWithItemsChecked` (OQ6 rule): a `raw_material` product as
   the finished output threw "naw'uh raw_material la yamkin an yakun al-muntaj
   al-niha'i" (user screenshot #3) - but the printing/textile custody flow produces
   the SAME product the customer lends (fabric in -> printed same fabric out),
   so the strict rule blocked the whole receipt-first flow.

## Fix (commit 253de27)

- `bom_dao.dart`: `raw_material` as finished output -> warning (not throw); other
  explicitly-wrong types still throw.
- `bom_form_dialog.dart`:
  - finished product picker -> `SearchableProductPicker` (search by name/barcode).
  - new params `defaultFinishedProductId`, `defaultYield` (used when creating a
    fresh recipe, not when editing an existing one).
- `mo_form_dialog.dart` `_createRecipeInline` (the FEAT-005 'sifa jadida' button):
  when the receipt-first flow is active, prefill finished product = the custody
  balance product, and yield = available quantity (received - defective -
  allocated). This answers "after I pick it, it should auto-save onto the received
  product".
- `manufacturing_mixed_order_job_test.dart`: **M4** locks the DAO contract -
  raw-material finished BOM saves with a warning + a full mixed round-trip
  (receive -> recipe -> order -> persisted orderType=mixed).

## Quantity semantics confirmed (user question)

Custody = received - defective-at-receipt (already implemented in
`receiveCustomerMaterial`). The recipe `yield` = expected output units per full
recipe run; MO lines take what they need from custody. Defects at intake are
excluded from custody by the existing تالف الفحص field.

## Verification

- flutter test mixed+integrity -> 15/15 pass
- flutter test receipt quick_create+guard -> 3/3 pass
- flutter analyze manufacturing scopes -> 0 errors/warnings

## Sync
GitHub Issue + Notion page via sync script.