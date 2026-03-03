# POS System Architecture

## File Structure Overview

This document outlines the main architecture and file organization of the POS Offline Desktop system.

## Core Layers

### 1. Database Layer (`lib/core/database/`)
- **app_database.dart** - Main database configuration with Drift
- **tables/** - All database table definitions
- **dao/** - Data Access Objects for database operations
- **migrations/** - Database migration scripts

### 2. Services Layer (`lib/services/`)
- Business logic and external integrations
- API clients, file operations, printing services
- Background services (backup, notifications, etc.)

### 3. UI Layer (`lib/ui/`)
- **screens/** - Main app screens and navigation
- **widgets/** - Reusable UI components
- **pages/** - Complex page implementations

### 4. Utils Layer (`lib/core/utils/`)
- **app_utils.dart** - Common utility functions (parsing, formatting, validation)

## Route Structure

### Main App Routes (lib/core/router/go_router.dart)
- `/` - Home/Dashboard
- `/login` - Authentication
- `/activation` - License Activation
- `/sales` - Sales Management
- `/customers` - Customer Management
- `/suppliers` - Supplier Management
- `/products` - Product Management
- `/reports` - Reports & Analytics
- `/staff` - Staff Management (Enterprise)
- `/settings` - System Settings

### Screen File Mapping

| Route | Screen File | DAO/Service |
|-------|-------------|-------------|
| `/` | `lib/ui/home/home.dart` | Multiple DAOs |
| `/sales` | `lib/ui/sales/sales_page.dart` | InvoiceDao, ProductDao |
| `/customers` | `lib/ui/customer/customer_page.dart` | CustomerDao, LedgerDao |
| `/suppliers` | `lib/ui/supplier/supplier_page.dart` | SupplierDao, PurchaseDao |
| `/products` | `lib/ui/product/product_page.dart` | ProductDao |
| `/reports` | `lib/ui/reports/reports_page.dart` | Multiple DAOs |
| `/staff` | `lib/ui/staff/staff_list_page.dart` | StaffManagementDao |
| `/settings` | `lib/ui/settings/settings_page.dart` | Various Services |

## Database Schema

### Core Tables
- **users** - System users
- **products** - Product catalog
- **customers** - Customer information
- **suppliers** - Supplier information
- **invoices** - Sales transactions
- **invoice_items** - Invoice line items
- **purchases** - Purchase transactions
- **purchase_items** - Purchase line items
- **ledger_transactions** - Financial ledger
- **expenses** - Business expenses

### Enterprise Tables (Staff Management)
- **staff_table** - Employee records
- **attendance_table** - Attendance tracking
- **payroll_table** - Salary calculations
- **vacations** - Leave management
- **staff_advances** - Salary advances

## Service Architecture

### Core Services
- **BackupService** - Database backup/restore
- **NotificationService** - License expiry notifications
- **LicenseManager** - License validation
- **UnifiedPrintService** - Printing operations
- **ExportService** - Data export functionality

### DAO Pattern
- Each major entity has a dedicated DAO
- DAOs handle CRUD operations and complex queries
- Services orchestrate business logic using DAOs

## Key Design Patterns

1. **Repository Pattern** - DAOs abstract database operations
2. **Service Layer** - Business logic separation
3. **Provider Pattern** - State management (Riverpod)
4. **Widget Composition** - Reusable UI components
5. **Error Boundaries** - Comprehensive error handling

## Build Configuration

- **Flutter Version**: 3.8.1+
- **Database**: SQLite via Drift ORM
- **State Management**: Riverpod
- **UI Framework**: Material Design 3
- **Localization**: Arabic RTL support

## Deployment

- **Desktop**: Windows, macOS, Linux
- **Web**: Separate web admin dashboard
- **Mobile**: Android (planned)
