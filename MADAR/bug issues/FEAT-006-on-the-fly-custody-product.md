# FEAT-006: Receive non-stocked material via an on-the-fly custody product

- Status: done
- Priority: high
- Area: Manufacturing (customer material receipts / custody)
- Commit: d4746ea

## User story
Printing/textile shops receive fabric, skirts or garments from customers
that the workshop never stocks. The receipt dialog could only search the
local products table, so non-stocked material could not be received at all
(and the operator assumed the received product should not live in stock).

## Decision (approved by owner)
- Custody is keyed by Product, so receiving non-stocked material creates a
  real product row ON THE FLY from inside the receipt dialog:
  `productType = 'raw_material'`, quantity stays 0, price 0, optional unit.
- The product stays in the products LIST but its factory stock is always 0;
  consumption for for_others/mixed happens exclusively in custody
  (regression-locked by E1/E2/E3/M2/M3 tests).

## Implementation
- lib/ui/manufacturing/customer_material_receipt_list_screen.dart:
  `_createCustodyProduct` mini-dialog + `add custody product` button in the
  items header (Key fe006-add-custody-product). After creation the row is
  auto-selected (creates a new row when the first row is occupied).

## Regression tests
- test/unit/customer_material_receipt_quick_create_test.dart:
  1) button is visible when there are no products at all;
  2) a zero-quantity raw_material product receipt creates custody balance
     = received qty and factory stock stays 0 (end-to-end submit).
- test/unit/customer_material_receipt_dialog_guard_test.dart (BUG-006)
  covers the no-product-selected validation path.
- Run: flutter test (3 files incl. mixed M1-M3) -> 00:07 +6: All tests passed.
- flutter analyze: no new issues.

## Notes / future
The quick-create AlertDialog itself could get automated UI interaction once
dialog navigation in widget tests proves stable (tester async quirks with
showDialog/close animation under runAsync); the business contract is
locked by the zero-stock acceptance test above.