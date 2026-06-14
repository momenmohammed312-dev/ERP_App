# POS Offline Desktop — Flutter SaaS Point of Sale System

A full-featured, offline-first Point of Sale desktop application built with Flutter. Designed as a SaaS product for Egyptian small and medium businesses, with tiered subscription plans, cloud sync, and a separate web admin dashboard.

## Overview

Most POS systems require constant internet. This one doesn’t. Built for Windows desktop with full offline capability, automatic local backups, and optional cloud sync — so businesses never lose a sale due to connectivity.

## Key Features

### Core POS

- Sales management with cash and credit payment options
- Smart printing — thermal for cash sales, A4 for credit invoices
- Daily cashier open/close with vault balance tracking
- Full invoice history with reprint support

### Customer & Supplier Management

- Complete CRUD with balance tracking (color-coded: green/red)
- Full transaction history per customer/supplier
- Professional PDF account statements

### Inventory

- Product catalog with stock tracking
- Purchase invoices from suppliers
- Low stock alerts

### Reports & Export

- PDF and Excel export for all reports
- Date-range filtering
- Branded report formatting

### Security

- SQLCipher 256-bit database encryption
- Hardware device binding (prevents license sharing)
- HMAC digital signature for license keys
- Full audit trail logging
- Anti-tamper protection (time/date manipulation detection)

### SaaS License System

|Plan        |Price/Month|Users|
|------------|-----------|-----|
|Basic       |1,000 EGP  |1    |
|Standard    |2,500 EGP  |3    |
|Professional|5,000 EGP  |5    |
|Enterprise  |10,000 EGP |10   |

Features unlock per plan — cashier and staff management require Professional+.

### Staff Management (Professional+)

- Employee records and attendance tracking
- Payroll and salary calculations
- Leave and vacation management

### Web Admin Dashboard

- Firebase-hosted web panel
- Real-time sales analytics and charts
- Inventory management
- User and permission management
- Full Arabic RTL interface

## Tech Stack

|Layer           |Technology                                     |
|----------------|-----------------------------------------------|
|Framework       |Flutter 3.32.5 (Desktop + Web)                 |
|Database        |SQLite via Drift ORM (encrypted with SQLCipher)|
|State Management|Riverpod                                       |
|Backend / Auth  |Firebase (Auth + Hosting + Firestore)          |
|Routing         |GoRouter                                       |
|Export          |PDF + Excel generation                         |
|Localization    |Arabic RTL                                     |

## Architecture

```
lib/
├── core/
│   ├── database/       — Drift ORM, tables, DAOs, migrations
│   ├── router/         — GoRouter configuration
│   └── utils/          — Shared utilities
├── services/
│   ├── BackupService       — Local + cloud backup
│   ├── LicenseManager      — License validation + hardware binding
│   ├── UnifiedPrintService — Thermal + A4 printing
│   └── ExportService       — PDF/Excel export
└── ui/
    ├── home/       — Dashboard
    ├── sales/      — Sales & invoices
    ├── customer/   — Customer management
    ├── supplier/   — Supplier management
    ├── products/   — Inventory
    ├── reports/    — Analytics
    ├── staff/      — Employee management
    └── settings/   — System configuration
```

Design patterns used: Repository (DAO), Service Layer, Provider (Riverpod), Widget Composition.

## Getting Started

### Prerequisites

- Flutter 3.0+ with Desktop support enabled
- Java 17+
- Windows 10/11

### Run locally

```bash
git clone https://github.com/momenmohammed312-dev/pOS-Offline-DesktoP
cd pOS-Offline-DesktoP
flutter pub get
flutter run -d windows
```

### Web admin dashboard

Live at: <https://posmo2-13dc1.web.app>

```bash
# Run locally
flutter run -d chrome
```

## Screenshots

> Coming soon

## Author

**Moamen Mohamed** — Flutter Developer  
[GitHub](https://github.com/momenmohammed312-dev)
