# BUG-008 - Custody consumption not recorded for same-product receipt-first flow (BUG)

- **Status:** fixed (commit 85068fb - option A implemented + M5 regression test)
- **Severity:** High (custody accounting - Sensitive Zone)
- **Area:** Manufacturing completion + custody ledger
- **Worktree:** wt_manufacturing_fixes / feat/manufacturing-fixes

## Reported

Customer: "How did I receive 223 and it says custody 413 why, actually?" - the
PDF card showed consumed-from-custody 0.0 and an empty movements ledger while
the customer had received 223 and the order was completed and delivered.

## Evidence (live DB, MO-18798942 / customer CUST-eed5f36d51)

- customer_stock_movements summary: receipt CMR-2026-0007 +223 (product 172),
  delivered DN-2026-0002 +223 (product 172), NO issued_to_order rows AT ALL
  for any order.
- customer_stock_balances: product 172 (qamash) quantity_on_hand = 223 (the
  delivered rows were informational and did not balance-decrement).
- manufacturing_orders row: order_type mixed, finished_product_id = 172 (the
  SAME custody product), bom 6 "man" whose ONLY bill item is product 167
  qty 0.15 (a factory thread). input_product_id is NULL.
- `manufacturing_order_dao.dart` (l.749-772) consumes custody per ORDER LINES
  and writes issued_to_order rows only for BOM-line products. The receipt
  product (172) is not a BOM line (it is the finished output), so completion
  consumed nothing and wrote no ledger row.

## Consequences

1. The fabric stays in custody (223) although the job was completed on it and
   its output delivered - the PDF card correctly proves this by showing
   consumed 0.0.
2. Delivered rows (+223) never decrement or touch the balance, so custody
   never nets to zero across the loop.

## PDF side (already fixed in e2d8c50)

The FEAT-010 card now merges both the order-referenced rows AND the
delivery-note rows, and scopes balances to the order-connected products, so
the card no longer shows the customer-wide 413 or a falsely empty ledger.

## Owner decision needed (PROPOSAL A)

On completing a receipt-first order whose finished product EQUALS the custody
product (print/textile same-product flow): auto-issuance of the received
input quantity from custody (issued_to_order movement, negative), netting
custody to what remains un-processed. Delivered stays informational.
Alternative: require the custody product to be an explicit BOM line.

- Requires: atomic change inside the completion transaction + movement write
  + regression test (dao level) + migration NOT needed (no schema change).

## Sync
GitHub Issue + Notion page via sync script.