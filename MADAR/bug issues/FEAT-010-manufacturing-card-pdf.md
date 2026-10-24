# FEAT-010 - Production/consumption card PDF for every MO (FEAT)

- **Status:** done
- **Priority:** Medium
- **Area:** Manufacturing + UnifiedPrintService - Sensitive Zone (print/docs only, no money)
- **Worktree:** wt_manufacturing_fixes / feat/manufacturing-fixes

## Request

Customer wants the written record ("Documentation written for every order") of each
manufacturing order: a printable PDF card that documents the production and the
consumption of customer custody for that order (estimation: small).

## Design (SOP 4.0: single print service)

- Add `DocumentType.manufacturingCard` to `UnifiedPrintService` (title
  "Production/Consumption Card") and route through the EXISTING
  `generateUnifiedDocument` pipeline (global header/footer, Arabic Noto Naskh
  fonts, RTL). No new service, no parallel path.
- `_buildManufacturingCardContent` renders:
  1. order info box (order number, status, type, customer, BOM name, finished
     product, planned/produced/delivered/consumed, dates);
  2. custody movements table (date, type arabic label, product, qty, reference);
  3. remaining customer-custody balances table (product, available, allocated);
- `mo_detail_screen.dart` gets an AppBar action (pdf icon, tooltip
  "Production/Consumption card PDF") that collects data from the already-loaded
  state, opens the standard PdfPreview dialog (print/share/save).

## Verification

- New unit test `test/unit/services/manufacturing_print_card_test.dart`:
  generateUnifiedDocument(manufacturingCard) with sample maps saves bytes,
  expects them non-empty (font fallback protected by try/catch inside service).
- flutter analyze scope clean; app relaunched for manual PDF check on
  MO-18798942.

## Sync
GitHub Issue + Notion page via sync script.