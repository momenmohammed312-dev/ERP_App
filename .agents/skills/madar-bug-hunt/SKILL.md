---
name: madar-bug-hunt
description: "Debug and fix a defect in the MADAR POS/ERP Flutter app using evidence-first root-cause analysis, then prevent regression with a Dart test. Use when a bug, crash, wrong calculation, data corruption, or 'it behaves incorrectly' is reported in lib/ or test/. Applies MADAR rules: Drift migrations are append-only, money/stock paths must be atomic, Arabic RTL must stay intact, and the merge target is integration/all-agents. Not for new features (use requirement acceptance criteria first) and not for research-only questions."
---

# MADAR Bug Hunt

Debugging disciplined for a production business app. Fix the root cause, prove it with a test, never touch an applied migration.

## When to use

- Someone reports a bug, crash, or wrong number (total, balance, stock, payroll slip).
- A regression appears after a merge into `integration/all-agents`.
- Data looks corrupted, or day-close / drawer balance does not reconcile.
- A test fails intermittently.

Do NOT use for: new features (write acceptance criteria first), pure questions, or refactoring with no defect.

## MADAR facts you need

| Fact | Value |
|---|---|
| Stack | Flutter 3.41.4 (FVM) · Dart · Riverpod · Drift/SQLite (SQLCipher) |
| DB schema version | `AppDatabase.schemaVersion` in `lib/core/database/app_database.dart` |
| Layers | `core/database/{tables,dao}` → `services/` → `ui/<feature>/` |
| Flavors | `base` · `vegetable` · `clothing`, gated only by `lib/core/config/app_features.dart` |
| Merge target | `integration/all-agents` |
| Regen Drift | `dart run build_runner build --delete-conflicting-outputs` |
| Verify | `fvm flutter analyze` · `fvm flutter test` |

**Sensitive zones — always treat as high risk:** licensing · payroll/attendance · manufacturing (BOM/orders/scrap) · ledger · invoices/purchases/returns · cash session & day close · backup/restore · Supabase sync.

## Process

### 1. Reproduce first

Never edit code before the failure is reproducible or well-evidenced.

1. Get exact steps, app version (`pubspec.yaml`), flavor, and Windows environment.
2. Try to reproduce locally.
3. Decide: always · sometimes · once.
4. If not reproducible, ask for: flavor, device, preceding actions, exact error text, screenshot, and whether it happens on a real customer's data shape.

Use `test/fixtures/` data. Never paste real customer names, phone numbers, or barcodes into an issue file.

### 2. Gather evidence

- Reproduce as a failing Dart test when possible — that is the highest-value evidence.
- Read the stack trace to the exact `file:line`.
- Check whether the same logic exists in more than one place (duplicated invoice/payroll math is common in this repo).
- For regression, find the breaking commit:
  ```bash
  git log --oneline -20 -- lib/<path>
  git log -S "<offending-snippet>" --oneline
  git bisect start && git bisect bad && git bisect good <last-known-good>
  ```
- For a migration-related failure, check `onUpgrade` steps, not just the table definitions.

### 3. Form one hypothesis

Write it as: "The symptom happens because X, at `path:line`, triggered by Y." Then test it.
One hypothesis at a time. If evidence contradicts it, discard it and return to step 2 — do not patch around it.

### 4. Fix the root cause

Rules that are not negotiable in this repo:

- **No symptom masking.** Hiding an error, adding a guard that skips the case, or loosening a check is not a fix without a documented root cause.
- **Money and stock are atomic.** Sale, purchase, payment, return, payroll posting, and day-close must run inside one `transaction`. No partial updates.
- **Soft delete is the default** (`status = 'Deleted'`), matching `product_dao.dart`.
- **Migrations are append-only.** Never edit an already-applied step. Add a new version and a new `onUpgrade` step only. New columns nullable or with a default.
- **Reuse before new tables.** Check `Invoices`, `InvoiceItems`, `InvoicePayments`, `LedgerTransactions`, `expenses_table`, `day_table`, `cash_session_table` first.
- **No business logic inside widgets.** Logic goes through a DAO or service.
- **Flavor-gate with `AppFeatures`.** Never scatter `if (flavor == ...)`.
- **Do not touch the base flavor** without an explicit request from the project owner.

### 5. Prevent the regression (mandatory)

Add a test next to the existing suites — do not create a new test style:

| Area | Location |
|---|---|
| Business logic | `test/unit/` |
| DAO queries | `test/unit/dao/` |
| Migration steps | `test/unit/migration_v<N>_test.dart` |
| Services | `test/unit/services/` |
| Payroll parity | `test/unit/baseline_payroll_parity_test.dart` and siblings |

Then actually run it and record the real output:

```bash
fvm flutter test test/unit/<your_test>.dart
fvm flutter analyze
dart run build_runner build --delete-conflicting-outputs   # only if tables/DAOs changed
```

If a new migration step was added, test the upgrade path against a fixture database at the previous schema version — follow the pattern in `test/unit/migration_v77_test.dart`.

### 6. Document

Copy `MADAR/bug issues/_template-bug.md` to `MADAR/bug issues/BUG-<number>-<slug>.md` and fill sections 1–8. Set `status` to `done` only when the closure checklist at the bottom is satisfied.

After creating, updating, or closing any `MADAR/bug issues/BUG-<number>-<slug>.md`, run automatically (no tokens/secrets in repo; the script reads them from machine config):

```powershell
# تذكرة واحدة:
powershell -ExecutionPolicy Bypass -File "C:\Users\Momen\.gemini\config\scripts\sync_bug_to_github_and_notion.ps1" -File "MADAR/bug issues/BUG-<number>-<slug>.md"

# كل التذاكر دفعة واحدة:
powershell -ExecutionPolicy Bypass -File "C:\Users\Momen\.gemini\config\scripts\sync_bug_to_github_and_notion.ps1" -All
```

## Stop and ask the owner when

- The fix requires a **new table** or a **destructive data change** (deleting/rewriting financial rows).
- The fix requires **editing an already-applied migration**.
- The fix must touch the **base flavor** behavior.
- The bug is in production and involves **customer data or wrong money totals** — escalate to P1 and record a backup before touching anything.
- You cannot reproduce it and more evidence is needed — do not guess-fix.
- The scope grew beyond the reported symptom (that is a new feature request).

## Limits

- Do not claim a test passed unless it was executed and its output observed.
- Do not edit files while another agent is merging into `integration/all-agents` — work in your own worktree/branch.
- Do not run destructive git commands (`reset --hard`, `clean`, forced pushes, rebase on shared branches).
