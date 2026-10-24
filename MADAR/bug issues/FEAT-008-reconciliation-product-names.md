# FEAT-008 - Show material names in the MO reconciliation card (FEAT)

- **Status:** done
- **Priority:** Medium
- **Area:** Manufacturing MO detail screen - Sensitive Zone
- **Worktree:** wt_manufacturing_fixes / feat/manufacturing-fixes

## Request

Customer: on the MO detail screen the "Reconciliation" balance table shows
database ids ("#153", "#121", "#172") under the column "code of the item" -
they want the material NAME they can recognize, not the id.

## Cause

`mo_detail_screen.dart` `_buildReconciliationCard` renders
`Text('#${b.productId}')` straight from `CustomerStockBalance.productId`
without resolving `Product.name` (screenshots attached to the chat).

## Fix

- `_loadData` resolves a `Map<int,String>` of balance product ids -> names
  while customer balances are fetched (same async pass, no extra stream).
- Table header "code of the item" -> "the item"; cell shows the product name,
  falling back to "#id" only if the product row is missing (deleted).

## Verification

- flutter analyze scope clean
- app relaunched for manual verification of the reconciliation table

## Sync
GitHub Issue + Notion page via sync script.