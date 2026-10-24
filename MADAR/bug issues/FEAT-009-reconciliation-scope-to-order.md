# FEAT-009 - Scope the reconciliation balance table to the order materials (FEAT)

- **Status:** done
- **Priority:** Medium
- **Area:** Manufacturing MO detail screen - Sensitive Zone
- **Worktree:** wt_manufacturing_fixes / feat/manufacturing-fixes

## Request

Customer question: receipt CMR-2026-0007 contains ONLY fabric-jiwid (172, qty 223),
but the MO reconciliation card shows three balances (azr 90, trikot 100, jiwid 223)
- "how did these materials come? they are supposed to belong together".

## Cause

The card lists `getAllBalancesForCustomer` (the customer's WHOLE custody from all
their historical receipts). azr/trikot belong to earlier receipts of the same
customer, not to this order. After FEAT-008 the names resolved but the SCOPE
still follows the customer, not the order.

## Fix

- `_loadData` already selects `customer_stock_movements` where
  `referenceId == order.orderNumber`; collect their `productId`s and store as
  `_orderBalanceIds`.
- `_buildReconciliationCard`: if any movement-linked products exist, show only
  those balances under the title "customer custody balances linked to this order",
  otherwise keep the full list with a clarifying note that nothing is linked yet.
- Keep the warehouse-wide custody stat (413) as-is: it describes the customer,
  not this order.

## Verification

- flutter analyze scope clean; manufacturing dao tests still green
- app relaunched for manual check on MO-18798942 (only jiwid should remain)

## Sync
GitHub Issue + Notion page via sync script.