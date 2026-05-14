import 'dart:developer';

import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/dao/dao.dart';
import 'package:pos_offline_desktop/core/database/tables/tables.dart';
import 'package:pos_offline_desktop/core/utils/security_utils.dart';
import 'package:pos_offline_desktop/core/database/amount_types_fix.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Products,
    Customers,
    Suppliers,
    LedgerTransactions,
    Sales,
    Invoices,
    InvoiceItems,
    Expenses,
    Days,
    Purchases,
    PurchaseItems,
    CreditPayments,
    Employees,
    EnhancedSuppliers,
    EnhancedPurchases,
    EnhancedPurchaseItems,
    SupplierPayments,
    PurchaseBudgets,
    BudgetCategories,
    BudgetTransactions,
    BudgetAlerts,
    InventoryMovements,
    AuditLog,
    Categories,
    Users,
    StaffTable,
    AttendanceTable,
    Vacations,
    StaffAdvances,
    PayrollTable,
    RewardsPenalties,
    PerformanceReviews,
    StaffDocuments,
    PurchaseOrders,
    PurchaseOrderItems,
    PurchaseOrderStatuses,
    PurchaseReturns,
    PurchaseReturnItems,
    PurchaseRefunds,
    UserActivityLog,
    CashSessions,
    Notifications,
  ],
  daos: [
    ProductDao,
    CustomerDao,
    SupplierDao,
    LedgerDao,
    InvoiceDao,
    ExpenseDao,
    DayDao,
    PurchaseDao,
    SalesDao,
    CreditPaymentsDao,
    EnhancedPurchaseDao,
    PurchaseBudgetDao,
    InventoryMovementDao,
    AuditDao,
    UserDao,
    StaffManagementDao,
    CashSessionDao,
    NotificationsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  String _hashPassword(String password) {
    return SecurityUtils.hashPassword(password);
  }

  @override
  int get schemaVersion => 39;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _ensureStaffTables(m);
      await _ensureCriticalColumns(m);
    },
    onUpgrade: (Migrator m, int from, int to) async {
      log('Migration: from $from to $to');

      // 1. Initial migrations (v2 - v20)
      if (from < 20) {
        await _runLegacyMigrations(m, from);
      }

      // 2. Medium-term migrations (v21 - v30)
      if (from < 30) {
        await _runIntermediateMigrations(m, from);
      }

      // 3. Modern migrations (v31 - v39)
      if (from < 39) {
        await _runModernMigrations(m, from);
      }

      // 4. Staff tables (also for DBs that skipped v35 createTable migrations)
      await _ensureStaffTables(m);

      // 5. Always ensure critical columns exist (to fix drifted schemas)
      await _ensureCriticalColumns(m);
      
      // 6. Special data fixes
      if (from < 36) {
        try {
          await AmountTypesFix.fixAmountTypes(this);
          log('Migration v36: Fixed amount types in purchases');
        } catch (e) {
          log('Migration v36 error: $e');
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _runLegacyMigrations(Migrator m, int from) async {
    // Grouped legacy column additions
    if (from < 10) {
      try {
        await customStatement('ALTER TABLE products ADD COLUMN unit TEXT');
        await customStatement('ALTER TABLE products ADD COLUMN category TEXT');
        await customStatement('ALTER TABLE products ADD COLUMN barcode TEXT');
        await customStatement('ALTER TABLE products ADD COLUMN status TEXT DEFAULT "Active"');
        
        await customStatement('ALTER TABLE customers ADD COLUMN phone TEXT');
        await customStatement('ALTER TABLE customers ADD COLUMN address TEXT');
        await customStatement('ALTER TABLE customers ADD COLUMN status TEXT DEFAULT "Active"');
        
        await customStatement('ALTER TABLE invoices ADD COLUMN payment_method TEXT DEFAULT "cash"');
        await customStatement('ALTER TABLE invoices ADD COLUMN paid_amount REAL DEFAULT 0.0');
        await customStatement('ALTER TABLE invoices ADD COLUMN status TEXT DEFAULT "pending"');
        await customStatement('ALTER TABLE invoices ADD COLUMN invoice_number TEXT');
      } catch (e) {
        log('Legacy migration warning: $e');
      }
    }

    if (from < 15) {
      try {
        await m.createTable(days);
        await m.createTable(expenses);
      } catch (e) {
        log('Legacy table creation warning: $e');
      }
    }

    if (from < 20) {
      try {
        await m.createTable(purchases);
        await m.createTable(purchaseItems);
        await m.createTable(creditPayments);
        await m.createTable(employees);
      } catch (e) {
        log('Legacy table creation warning v20: $e');
      }
    }
  }

  Future<void> _runIntermediateMigrations(Migrator m, int from) async {
    if (from < 23) {
      try {
        await m.createTable(suppliers);
        await m.createTable(ledgerTransactions);
      } catch (e) {
        log('Intermediate migration warning: $e');
      }
    }

    if (from < 30) {
      try {
        await m.createTable(enhancedSuppliers);
        await m.createTable(enhancedPurchases);
        await m.createTable(enhancedPurchaseItems);
        await m.createTable(supplierPayments);
      } catch (e) {
        log('Intermediate migration warning v30: $e');
      }
    }
  }

  Future<void> _runModernMigrations(Migrator m, int from) async {
    if (from < 32) {
      try {
        await m.createTable(inventoryMovements);
        await m.createTable(auditLog);
      } catch (e) {
        log('Modern migration v32 warning: $e');
      }
    }

    if (from < 33) {
      try {
        await m.createTable(users);
        final adminPassword = _hashPassword('admin123');
        await customStatement(
          "INSERT INTO users (username, password_hash, full_name, role, is_active, created_at, updated_at) "
          "VALUES ('admin', ?, 'مدير النظام', 0, 1, datetime('now'), datetime('now'))",
          [adminPassword],
        );
      } catch (e) {
        log('User table migration warning: $e');
      }
    }

    if (from < 35) {
      await m.createTable(staffTable);
      await m.createTable(attendanceTable);
      await m.createTable(vacations);
      await m.createTable(staffAdvances);
      await m.createTable(payrollTable);
      await m.createTable(rewardsPenalties);
      await m.createTable(performanceReviews);
      await m.createTable(staffDocuments);
    }

    if (from < 37) {
      try {
        await m.createTable(notifications);
      } catch (e) {
        log('Notifications table migration warning: $e');
      }
    }

    if (from < 38) {
      try {
        await customStatement('ALTER TABLE users ADD COLUMN failed_attempts INTEGER DEFAULT 0');
        await customStatement('ALTER TABLE users ADD COLUMN locked_until INTEGER');
        await customStatement('ALTER TABLE users ADD COLUMN custom_permissions TEXT');
        await customStatement('ALTER TABLE users ADD COLUMN email TEXT');
        await customStatement('ALTER TABLE users ADD COLUMN phone TEXT');
      } catch (e) {
        log('User security columns migration warning: $e');
      }
    }
  }

  /// Ensures staff-related tables exist (fresh installs only run [onCreate], not [onUpgrade]).
  Future<void> _ensureStaffTables(Migrator m) async {
    const staffTableSql = [
      '''CREATE TABLE IF NOT EXISTS "staff_table" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "staff_id" TEXT NOT NULL UNIQUE,
        "name" TEXT NOT NULL,
        "national_id" TEXT,
        "phone" TEXT,
        "email" TEXT,
        "address" TEXT,
        "position" TEXT NOT NULL,
        "department" TEXT,
        "employment_type" TEXT NOT NULL,
        "basic_salary" REAL NOT NULL,
        "hourly_rate" REAL,
        "hire_date" INTEGER NOT NULL,
        "contract_end_date" INTEGER,
        "status" TEXT NOT NULL,
        "bank_name" TEXT,
        "bank_account" TEXT,
        "emergency_contact" TEXT,
        "emergency_phone" TEXT,
        "notes" TEXT,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL,
        "is_active" INTEGER NOT NULL DEFAULT 1
      )''',
      '''CREATE TABLE IF NOT EXISTS "attendance_table" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "staff_id" TEXT NOT NULL,
        "date" INTEGER NOT NULL,
        "check_in_time" INTEGER,
        "check_out_time" INTEGER,
        "check_in_location" TEXT,
        "check_out_location" TEXT,
        "working_hours" REAL,
        "status" TEXT NOT NULL,
        "leave_type" TEXT,
        "notes" TEXT,
        "overtime_hours" REAL NOT NULL DEFAULT 0,
        "approved_by" TEXT,
        "approved_at" INTEGER,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS "vacations" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "staff_id" TEXT NOT NULL,
        "vacation_type" TEXT NOT NULL,
        "start_date" INTEGER NOT NULL,
        "end_date" INTEGER NOT NULL,
        "total_days" INTEGER NOT NULL,
        "reason" TEXT,
        "status" TEXT NOT NULL,
        "approved_by" TEXT,
        "approved_at" INTEGER,
        "rejection_reason" TEXT,
        "contact_during_vacation" TEXT,
        "handover_to" TEXT,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS "staff_advances" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "staff_id" TEXT NOT NULL,
        "amount" REAL NOT NULL,
        "reason" TEXT,
        "request_date" INTEGER NOT NULL,
        "payment_date" INTEGER,
        "status" TEXT NOT NULL,
        "approved_by" TEXT,
        "approved_at" INTEGER,
        "rejection_reason" TEXT,
        "payment_method" TEXT,
        "transaction_reference" TEXT,
        "installment_months" INTEGER,
        "monthly_deduction" REAL,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS "payroll_table" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "staff_id" TEXT NOT NULL,
        "payroll_period" TEXT NOT NULL,
        "period_start" INTEGER NOT NULL,
        "period_end" INTEGER NOT NULL,
        "basic_salary" REAL NOT NULL,
        "overtime_hours" REAL NOT NULL DEFAULT 0,
        "overtime_rate" REAL,
        "overtime_pay" REAL NOT NULL DEFAULT 0,
        "allowances" REAL NOT NULL DEFAULT 0,
        "deductions" REAL NOT NULL DEFAULT 0,
        "advances" REAL NOT NULL DEFAULT 0,
        "taxes" REAL NOT NULL DEFAULT 0,
        "insurance" REAL NOT NULL DEFAULT 0,
        "other_deductions" REAL NOT NULL DEFAULT 0,
        "net_salary" REAL NOT NULL,
        "working_days" INTEGER NOT NULL DEFAULT 0,
        "present_days" INTEGER NOT NULL DEFAULT 0,
        "absent_days" INTEGER NOT NULL DEFAULT 0,
        "leave_days" INTEGER NOT NULL DEFAULT 0,
        "status" TEXT NOT NULL,
        "payment_date" INTEGER,
        "payment_method" TEXT,
        "transaction_reference" TEXT,
        "approved_by" TEXT,
        "approved_at" INTEGER,
        "notes" TEXT,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS "rewards_penalties" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "staff_id" TEXT NOT NULL,
        "type" TEXT NOT NULL,
        "category" TEXT NOT NULL,
        "title" TEXT NOT NULL,
        "description" TEXT,
        "amount" REAL,
        "incident_date" INTEGER NOT NULL,
        "issued_by" TEXT NOT NULL,
        "status" TEXT NOT NULL,
        "effective_date" INTEGER NOT NULL,
        "expiry_date" INTEGER,
        "evidence" TEXT,
        "notes" TEXT,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS "performance_reviews" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "staff_id" TEXT NOT NULL,
        "review_period" TEXT NOT NULL,
        "review_date" INTEGER NOT NULL,
        "reviewer_id" TEXT NOT NULL,
        "overall_rating" REAL NOT NULL,
        "work_quality_rating" REAL NOT NULL,
        "productivity_rating" REAL NOT NULL,
        "teamwork_rating" REAL NOT NULL,
        "punctuality_rating" REAL NOT NULL,
        "initiative_rating" REAL NOT NULL,
        "strengths" TEXT,
        "weaknesses" TEXT,
        "goals" TEXT,
        "recommendations" TEXT,
        "employee_comments" TEXT,
        "status" TEXT NOT NULL,
        "acknowledged_at" INTEGER,
        "next_review_date" INTEGER,
        "action_plan" TEXT,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL
      )''',
      '''CREATE TABLE IF NOT EXISTS "staff_documents" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "staff_id" TEXT NOT NULL,
        "document_type" TEXT NOT NULL,
        "document_name" TEXT NOT NULL,
        "file_path" TEXT NOT NULL,
        "file_name" TEXT NOT NULL,
        "file_type" TEXT NOT NULL,
        "file_size" INTEGER NOT NULL,
        "issue_date" INTEGER,
        "expiry_date" INTEGER,
        "issuing_authority" TEXT,
        "document_number" TEXT,
        "status" TEXT NOT NULL,
        "notes" TEXT,
        "created_at" INTEGER NOT NULL,
        "updated_at" INTEGER NOT NULL
      )''',
    ];

    for (final sql in staffTableSql) {
      try {
        await customStatement(sql);
      } catch (e) {
        log('_ensureStaffTables error: $e');
      }
    }
  }

  Future<void> _ensureCriticalColumns(Migrator m) async {
    // Critical columns for existing tables
    final columnChecks = [
      {'table': 'invoices', 'column': 'customer_id', 'type': 'TEXT'},
      {'table': 'invoices', 'column': 'total_amount', 'type': 'REAL DEFAULT 0.0'},
      {'table': 'invoices', 'column': 'paid_amount',  'type': 'REAL DEFAULT 0.0'},
      {'table': 'invoices', 'column': 'status',       'type': 'TEXT DEFAULT "pending"'},
      {'table': 'customers','column': 'status',       'type': 'TEXT DEFAULT "Active"'},
      {'table': 'customers','column': 'created_at',   'type': 'INTEGER'},
    ];

    for (final check in columnChecks) {
      try {
        await customStatement(
          'ALTER TABLE ${check['table']} ADD COLUMN ${check['column']} ${check['type']}',
        );
        log('Ensured column ${check['column']} in ${check['table']}');
      } catch (e) {
        // Ignore — column already exists
      }
    }
  }
}
