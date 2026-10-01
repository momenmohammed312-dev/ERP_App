# POS Offline Desktop — Offline-First Arabic ERP/POS

An offline-first, Arabic RTL point-of-sale and ERP system built with Flutter, for small and medium businesses in Egypt and the Middle East. Runs on Windows desktop today, with an Android mobile build in progress from the same codebase.

![Version](https://img.shields.io/badge/version-2.3.0-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.41.4-02569B)
![License](https://img.shields.io/badge/license-Proprietary-red)

## Contents

- [Why this exists](#why-this-exists)
- [Platform status](#platform-status)
- [ERP modules](#erp-modules)
- [SaaS license plans](#saas-license-plans)
- [Tech stack](#tech-stack)
- [Getting started](#getting-started)
- [Build flavors](#build-flavors)
- [Currently working on](#currently-working-on)
- [Project structure](#project-structure)
- [Contributing](#contributing)
- [License](#license)
- [Author](#author)

## Why this exists

Most POS systems stop working when the internet drops. This one doesn't: sales, inventory, and cash tracking all run on an encrypted local database, with automatic backups and optional multi-device cloud sync for when connectivity returns. The full interface is Arabic RTL, with receipts, invoices, and reports to match.

## Platform status

| Platform | Status | Notes |
|---|---|---|
| Windows desktop | ✅ Stable | Primary target, installer in `installer.iss` |
| Android | 🚧 In progress | Responsive/mobile adaptations on the `mobile` branch |
| Web admin dashboard | ✅ Available | Firebase-hosted panel, see `web_admin_dashboard/` |

## ERP modules

### FI — Finance 💰

- **General ledger** (`LedgerTransactions`) — every purchase posts a due + payment pair, so balances always reconcile.
- **Cash custody (NEW)** — open/close cash advances (`CashCustodies`) with per-custody expense tracking (`CustodyExpenses`).
- **Payroll v72 (active development)** — hourly rate from `/240` divisor, overtime multiplier, late-from-shift-start deduction, commitment bonus, advance cap, and first-class permission columns with a full breakdown per slip plus batch slip printing.
- **Expenses & budgets** — categorized expenses, purchase budgets with alerts, supplier/customer statements as branded PDFs.

### HR — Human resources 👥

- **Biometric attendance (active development)** — ZKTeco devices over TCP, raw-event pipeline with dedup hashes, and sync logs.
- **File import** — attendance import from Excel/export files with fingerprint-number matching against staff records.
- **Staff management** — employees, vacations, advances, rewards/penalties, performance reviews, and documents.

### PP — Manufacturing 🏭 (in progress)

- **Manufacturing recipes** — bill-of-material style recipes linking raw materials to finished products (currently in progress, not yet released).

### SD/MM — Sales & inventory

- Sales with cash and credit payments, thermal (cash) and A4 (credit) printing, full invoice history with reprint.
- Purchases from suppliers with detail/edit/return flows, purchase orders, and damaged-goods tracking.
- Product catalog with stock tracking, low-stock alerts, barcode label printing, and Excel import/export.
- Customer & supplier management with color-coded balances and full transaction history.
- **Industry flavors** — one codebase, separate entry points and databases:
  - 🍅 Vegetable market (`FLAVOR=vegetable`): shipment tracking, empty-container (barnika) tracking, commission/per-unit/lump-sum pricing, day-close settlement.
  - 👕 Clothing (`FLAVOR=clothing`): variant generator and returns flows.
- **Multi-device sync** — offline-first local store with Supabase sync, conflict handling, and row-level security.

### Security

- SQLCipher 256-bit database encryption, hardware device binding, AES-256 + HMAC-SHA256 license keys, audit-trail logging, and anti-tamper time/date protection.

## SaaS license plans

| Plan | Price / month | Users |
|---|---|---|
| Basic | 1,000 EGP | 1 |
| Standard | 2,500 EGP | 3 |
| Professional | 5,000 EGP | 5 |
| Enterprise | 10,000 EGP | 10 |

Feature-gated modules (staff, accounting, cloud backup) unlock on higher tiers. The end-user install and activation guide ships with the installer as `readme.txt`.

## Tech stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.41.4 (see `.fvmrc`) |
| Database | SQLite via Drift ORM, encrypted with SQLCipher |
| State management | Riverpod |
| Routing | GoRouter |
| Sync backend / Auth | Supabase + Firebase (Auth, Hosting, Firestore) |
| Export & printing | `pdf` + `printing`, `excel` |
| Localization | Arabic RTL (`flutter_localizations`, NotoNaskhArabic) |

No alternative state-management or ORM swaps — Riverpod + Drift are the decided stack (see `AGENTS.md`).

## Getting started

### Prerequisites

- Flutter 3.41.4 via [FVM](https://fvm.app) (`fvm use` in the repo root), with desktop support enabled
- Java 17+
- Windows 10/11

### Run locally

```bash
git clone https://github.com/momenmohammed312-dev/ERP_App.git
cd ERP_App
fvm flutter pub get
fvm flutter run -d windows
```

### Regenerate Drift code (after touching tables/DAOs)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Run tests

```bash
fvm flutter test
```

## Build flavors

`AppFeatures` (`lib/core/config/app_features.dart`) is the single source of truth for flavor flags — no scattered `if flavor ==` checks. Each flavor has its own entry point and database name.

```bash
# Base (default)
fvm flutter run -d windows

# Vegetable market (سوق الخضار)
fvm flutter run -t lib/main_vegetable.dart --dart-define=FLAVOR=vegetable
fvm flutter build windows -t lib/main_vegetable.dart --dart-define=FLAVOR=vegetable

# Clothing (محل ملابس)
fvm flutter run -t lib/main_clothing.dart --dart-define=FLAVOR=clothing
fvm flutter build apk -t lib/main_clothing.dart --dart-define=FLAVOR=clothing
```

> The base flavor stays untouched while flavor work is in progress.

## Currently working on

- Cash-custody module integration (`integration/attendance-import-good` branch)
- Attendance file import + ZKTeco sync hardening
- Payroll v72 invariants and batch slips
- Manufacturing recipes (PP module)
- Mobile/Android polish (`mobile` branch)

## Project structure

```
lib/
├── core/
│   ├── database/
│   │   ├── tables/   — Drift table definitions
│   │   └── dao/      — Data access objects (@DriftAccessor)
│   ├── router/       — GoRouter configuration
│   └── config/       — Flavors (app_flavor.dart) + feature flags (app_features.dart)
├── services/         — Backup, license, print, export, attendance (no business logic in widgets)
├── ui/<feature>/     — One screen per feature, widgets under <feature>/widgets/
└── main.dart / main_vegetable.dart / main_clothing.dart
```

Conventions: `camelCase` vars/functions, `PascalCase` classes, `snake_case` files. Money/stock operations run atomically in a single transaction. Soft delete (`status = 'Deleted'`) is the default. Never edit an applied migration step — new schema changes get a new version + `onUpgrade` step.

## Contributing

1. Read `AGENTS.md` first — database, flavor, and workflow rules are mandatory.
2. Implement one plan phase at a time; don't close a phase without review.
3. Add/extend tests for money, stock, and payroll logic; run `fvm flutter test` before pushing.

## License

Proprietary commercial license — see [license.txt](license.txt) for the full agreement. The user-facing install guide is [readme.txt](readme.txt) (also bundled by `installer.iss`).

## Author

**Moamen Mohamed** — Flutter Developer
[GitHub](https://github.com/momenmohammed312-dev)
