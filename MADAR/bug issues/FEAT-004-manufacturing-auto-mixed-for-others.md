# FEAT-004: Auto-escalate receipt-based for-others MOs to mixed

- Status: resolved
- Priority: high
- Area: Manufacturing (for-others/mixed flow)
- Commit: dd91c42

## User story
Printing shop: customer brings 100 blank t-shirts (custody receipt), the job
also consumes factory-owned materials (ink, film, paper). Previously the
operator had to know the order type matrix by heart: picking a recipe whose
lines are not all customer-owned failed at completion with a confusing
shortage error.

## Decision (approved)
- No third dropdown option for `mixed` (mixed IS a form of for-others).
- After the operator picks a recipe in the receipt flow the dialog shows a
  split preview: customer-owned lines (deducted from custody) vs
  factory-owned lines (deducted from factory stock), with required and
  available quantities; availability uses the same formula as the detail
  screen (quantityOnHand - quantityAllocated for custody, Products.quantity
  for factory).
- If any line is factory-owned, the dialog silently escalates the saved
  order type to `mixed` (decided on save via `_autoMixed`); otherwise the
  order keeps `for_others` and gives the loud validation error
  (protective against "show all" recipe mis-picks eating factory stock).
- Ownership rule is the shared `isCustomerOwnedBomLine`: for_for_others
  defaults all lines to customer-owned, mixed defaults them by custody
  balance presence, internal never.

## Implementation
- lib/ui/manufacturing/widgets/mo_form_dialog.dart: state `_selectedBomLines`,
  `_onForOthersBomPicked`, `_buildBomOwnershipSplit`, `update path` written copyWith.
- Regression tests: test/unit/manufacturing_mixed_order_job_test.dart
  (M1 mixed persists on create, M2 custody-balance presence beats factory
  stock and shortages abort with zero writes, M3 all-custody mixed leaves
  factory stock untouched). Library suite: 45 tests pass over 7 files.

## Verification
- flutter analyze lib/ui/manufacturing/widgets/mo_form_dialog.dart: 0 errors.
- flutter test (manufacturing set): All tests passed.