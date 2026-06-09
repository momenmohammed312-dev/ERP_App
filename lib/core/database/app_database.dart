import 'dart:developer';

import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/dao/customer_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/credit_payments_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/expense_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/invoice_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/ledger_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/product_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/purchase_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/sales_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/supplier_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/day_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/enhanced_purchase_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/inventory_movement_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/purchase_budget_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/audit_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/user_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/cash_session_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/notifications_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/invoice_payments_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/damaged_items_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/sales_returns_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/audit_log_table.dart';
import 'package:pos_offline_desktop/core/database/tables/categories_table.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_table.dart';
import 'package:pos_offline_desktop/core/database/tables/credit_payments_table.dart';
import 'package:pos_offline_desktop/core/database/tables/employees_table.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_items_table.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_table.dart';
import 'package:pos_offline_desktop/core/database/tables/ledger_transactions_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';
import 'package:pos_offline_desktop/core/database/tables/purchase_table.dart';
import 'package:pos_offline_desktop/core/database/tables/purchase_items_table.dart';
import 'package:pos_offline_desktop/core/database/tables/sales_table.dart';
import 'package:pos_offline_desktop/core/database/tables/supplier_table.dart';
import 'package:pos_offline_desktop/core/database/tables/expenses_table.dart';
import 'package:pos_offline_desktop/core/database/tables/users_table.dart';
import 'package:pos_offline_desktop/core/database/tables/day_table.dart';
import 'package:pos_offline_desktop/core/database/tables/enhanced_purchase_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/inventory_movements_table.dart';
import 'package:pos_offline_desktop/core/database/tables/purchase_returns_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/purchase_orders_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/purchase_budget_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/staff_management_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/user_activity_log_table.dart';
import 'package:pos_offline_desktop/core/database/tables/cash_session_table.dart';
import 'package:pos_offline_desktop/core/database/tables/notifications_table.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_payments_table.dart';
import 'package:pos_offline_desktop/core/database/tables/damaged_items_table.dart';
import 'package:pos_offline_desktop/core/database/tables/sales_returns_table.dart';
import 'package:pos_offline_desktop/core/utils/security_utils.dart';
// import 'package:pos_offline_desktop/core/database/amount_types_fix.dart';

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
    AppNotifications,
    InvoicePayments,
    DamagedItems,
    SalesReturns,
    SalesReturnItems,
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
    InvoicePaymentsDao,
    DamagedItemsDao,
    SalesReturnsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  String _hashPassword(String password) {
    return SecurityUtils.hashPassword(password);
  }

  @override
  int get schemaVersion => 46;

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

      // 4b. Schema v40 migrations (new tables + columns)
      if (from < 40) {
        await _runV40Migrations(m);
      }

      // 4c. Schema v41 migrations (new columns)
      if (from < 41) {
        await _runV41Migrations(m);
      }

      // 4d. Schema v42 — days audit trail columns
      if (from < 42) {
        await _runV42Migrations(m);
      }

      // 4e. Schema v43 — payroll columns
      if (from < 43) {
        await _runV43Migrations(m);
      }

      // 4f. Schema v44 — attendance index + open-day trigger
      if (from < 44) {
        await _runV44Migrations(m);
      }

      // 4g. Schema v45 — partial unique index on days
      if (from < 45) {
        await _runV45Migrations(m);
      }

      // 4h. Schema v46 — ensure cash_sessions + damaged_items tables exist
      if (from < 46) {
        await _runV46Migrations(m);
      }

      // 4. Staff tables (also for DBs that skipped v35 createTable migrations)
      await _ensureStaffTables(m);

      // 5. Always ensure critical columns exist (to fix drifted schemas)
      await _ensureCriticalColumns(m);
      
      // 6. Special data fixes
      if (from < 36) {
        try {
          await _fixPurchaseAmountTypes();
          log('Migration v36: Fixed amount types in purchases');
        } catch (e) {
          log('Migration v36 error: $e');
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _ensureMigrationLogTable();
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
      for (final migration in [
        () => m.createTable(inventoryMovements),
        () => m.createTable(auditLog),
      ]) {
        try {
          await migration();
        } catch (e) {
          log('Migration warning (v32): $e');
        }
      }
    }

    if (from < 33) {
      try {
        await m.createTable(users);
        final adminPassword = _hashPassword('admin123');
        await customStatement(
          "INSERT INTO users (username, password, full_name, role, is_active, created_at, updated_at) "
          "VALUES ('admin', ?, 'مدير النظام', 'admin', 1, datetime('now'), datetime('now'))",
          [adminPassword],
        );
      } catch (e) {
        log('User table migration warning: $e');
      }
    }

    if (from < 35) {
      for (final migration in [
        () => m.createTable(staffTable),
        () => m.createTable(attendanceTable),
        () => m.createTable(vacations),
        () => m.createTable(staffAdvances),
        () => m.createTable(payrollTable),
        () => m.createTable(rewardsPenalties),
        () => m.createTable(performanceReviews),
        () => m.createTable(staffDocuments),
      ]) {
        try {
          await migration();
        } catch (e) {
          log('Migration warning (v35): $e');
        }
      }
    }

    if (from < 37) {
      try {
        await m.createTable(appNotifications);
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

  /// Migration v40 — adds new tables and columns
  Future<void> _runV40Migrations(Migrator m) async {
    // 1. New columns on existing tables
    final columnMigrations = [
      // Products
      'ALTER TABLE products ADD COLUMN cost_price REAL',
      // InvoiceItems
      'ALTER TABLE invoice_items ADD COLUMN discount REAL DEFAULT 0',
      'ALTER TABLE invoice_items ADD COLUMN commission REAL DEFAULT 0',
      'ALTER TABLE invoice_items ADD COLUMN unit_cost_at_time REAL',
      // Invoices (void support)
      'ALTER TABLE invoices ADD COLUMN voided_at INTEGER',
      'ALTER TABLE invoices ADD COLUMN void_reason TEXT',
      'ALTER TABLE invoices ADD COLUMN voided_by TEXT',
      // Expenses
      'ALTER TABLE expenses ADD COLUMN user_id TEXT',
      'ALTER TABLE expenses ADD COLUMN day_id TEXT',
      // CashSessions
      'ALTER TABLE cash_sessions ADD COLUMN closing_balance REAL',
      'ALTER TABLE cash_sessions ADD COLUMN closing_cash REAL',
      'ALTER TABLE cash_sessions ADD COLUMN difference REAL',
      'ALTER TABLE cash_sessions ADD COLUMN total_sales REAL DEFAULT 0',
      'ALTER TABLE cash_sessions ADD COLUMN total_expenses REAL DEFAULT 0',
      'ALTER TABLE cash_sessions ADD COLUMN notes TEXT',
      // AuditLog
      'ALTER TABLE audit_log ADD COLUMN old_value TEXT',
      'ALTER TABLE audit_log ADD COLUMN new_value TEXT',
    ];

    for (final sql in columnMigrations) {
      try {
        await customStatement(sql);
      } catch (e) {
        log('v40 column migration warning (likely already exists): $e');
      }
    }

    // 2. New tables
    for (final migration in [
      () => m.createTable(invoicePayments),
      () => m.createTable(damagedItems),
      () => m.createTable(salesReturns),
      () => m.createTable(salesReturnItems),
    ]) {
      try {
        await migration();
      } catch (e) {
        log('v40 table creation warning: $e');
      }
    }

    // 3. Migrate existing invoice payments → InvoicePayments table
    // Invoices where paid_amount > 0 get a corresponding payment record
    try {
      await customStatement('''
        INSERT OR IGNORE INTO invoice_payments (invoice_id, payment_method, amount, paid_at)
        SELECT 
          id,
          CASE 
            WHEN payment_method = 'visa' THEN 'visa'
            WHEN payment_method = 'bank' THEN 'bank'
            WHEN payment_method = 'credit' THEN 'credit'
            ELSE 'cash'
          END,
          paid_amount,
          date
        FROM invoices
        WHERE paid_amount > 0
      ''');
      log('v40: Migrated existing invoice payments to InvoicePayments table');
    } catch (e) {
      log('v40 invoice payment migration warning: $e');
    }
  }

  /// Migration v41 — adds split payment columns and min stock level
  Future<void> _runV41Migrations(Migrator m) async {
    final columnMigrations = [
      'ALTER TABLE products ADD COLUMN min_stock_level INTEGER DEFAULT 0',
      'ALTER TABLE invoices ADD COLUMN cash_amount REAL DEFAULT 0',
      'ALTER TABLE invoices ADD COLUMN card_amount REAL DEFAULT 0',
      'ALTER TABLE invoices ADD COLUMN credit_amount REAL DEFAULT 0',
    ];

    for (final sql in columnMigrations) {
      try {
        await customStatement(sql);
      } catch (e) {
        log('V41 migration warning (column may exist): $e');
      }
    }
  }

  Future<void> _ensureMigrationLogTable() async {
    try {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS _migration_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          version INTEGER NOT NULL,
          step TEXT NOT NULL,
          status TEXT NOT NULL,
          error TEXT,
          ran_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
    } catch (e) {
      log('CRITICAL: migration log table creation failed: $e');
    }
  }

  Future<void> _logMigrationStep(int version, String step, String status, {String? error}) async {
    try {
      await customStatement(
        'INSERT INTO _migration_log (version, step, status, error) VALUES (?, ?, ?, ?)',
        [version, step, status, error],
      );
    } catch (e) {
      log('WARNING: migration log insert failed (version=$version step=$step status=$status): $e');
    }
  }

  /// Schema v42 — days audit trail columns
  Future<void> _runV42Migrations(Migrator m) async {
    await _logMigrationStep(42, 'days_audit_columns', 'started');
    try {
      final columns = [
        'ALTER TABLE days ADD COLUMN opened_by TEXT',
        'ALTER TABLE days ADD COLUMN closed_by TEXT',
        'ALTER TABLE days ADD COLUMN reopened_at TEXT',
        'ALTER TABLE days ADD COLUMN reopened_by TEXT',
      ];
      for (final sql in columns) {
        try {
          await customStatement(sql);
        } catch (e) {
          log('v42 migration warning (column may exist): $e');
        }
      }
      await _logMigrationStep(42, 'days_audit_columns', 'completed');
    } catch (e) {
      await _logMigrationStep(42, 'days_audit_columns', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v43 — payroll bonus/commission/incentives columns
  Future<void> _runV43Migrations(Migrator m) async {
    await _logMigrationStep(43, 'payroll_columns', 'started');
    try {
      final columns = [
        'ALTER TABLE payroll_table ADD COLUMN bonus REAL DEFAULT 0.0',
        'ALTER TABLE payroll_table ADD COLUMN commission REAL DEFAULT 0.0',
        'ALTER TABLE payroll_table ADD COLUMN incentives REAL DEFAULT 0.0',
        'ALTER TABLE payroll_table ADD COLUMN rewards_total REAL DEFAULT 0.0',
        'ALTER TABLE payroll_table ADD COLUMN penalties_total REAL DEFAULT 0.0',
        'ALTER TABLE payroll_table ADD COLUMN expense_ref_id TEXT',
      ];
      for (final sql in columns) {
        try {
          await customStatement(sql);
        } catch (e) {
          log('v43 migration warning (column may exist): $e');
        }
      }
      await _logMigrationStep(43, 'payroll_columns', 'completed');
    } catch (e) {
      await _logMigrationStep(43, 'payroll_columns', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v44 — attendance index + open-day trigger + cleanup
  Future<void> _runV44Migrations(Migrator m) async {
    await _logMigrationStep(44, 'attendance_index_trigger', 'started');
    try {
      // Cleanup: close duplicate open days before creating trigger
      try {
        await customStatement('''
          UPDATE days SET is_open = 0 WHERE id NOT IN (
            SELECT MIN(id) FROM days WHERE is_open = 1
          ) AND is_open = 1
        ''');
      } catch (e) {
        log('v44 cleanup warning: $e');
      }

      // Attendance index
      try {
        await customStatement('CREATE INDEX IF NOT EXISTS idx_attendance_staff ON attendance_table(staff_id)');
      } catch (e) {
        log('v44 index warning: $e');
      }

      // Open-day prevention trigger
      try {
        await customStatement('''
          CREATE TRIGGER IF NOT EXISTS trg_prevent_multi_open
          BEFORE INSERT ON days
          WHEN NEW.is_open = 1
          BEGIN
            SELECT RAISE(ABORT, 'يوجد يوم مفتوح بالفعل')
            WHERE EXISTS (SELECT 1 FROM days WHERE is_open = 1);
          END
        ''');
      } catch (e) {
        log('v44 trigger warning: $e');
      }
      await _logMigrationStep(44, 'attendance_index_trigger', 'completed');
    } catch (e) {
      await _logMigrationStep(44, 'attendance_index_trigger', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v45 — partial unique index on open days
  Future<void> _runV45Migrations(Migrator m) async {
    await _logMigrationStep(45, 'days_partial_unique_index', 'started');
    try {
      await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_days_one_open ON days(is_open) WHERE is_open = 1');
      await _logMigrationStep(45, 'days_partial_unique_index', 'completed');
    } catch (e) {
      await _logMigrationStep(45, 'days_partial_unique_index', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v46 — ensure cash_sessions and damaged_items tables exist
  /// These tables were missing in some upgrades because they had no createTable migration
  Future<void> _runV46Migrations(Migrator m) async {
    await _logMigrationStep(46, 'ensure_missing_tables', 'started');

    // Create cash_sessions table if missing
    try {
      await m.createTable(cashSessions);
      log('v46: Created cash_sessions table');
    } catch (e) {
      log('v46: cash_sessions table likely already exists: $e');
    }

    // Create damaged_items table if missing
    try {
      await m.createTable(damagedItems);
      log('v46: Created damaged_items table');
    } catch (e) {
      log('v46: damaged_items table likely already exists: $e');
    }

    // Ensure critical columns that may have been missed in v40
    final missingColumns = [
      'ALTER TABLE products ADD COLUMN cost_price REAL',
      'ALTER TABLE products ADD COLUMN min_stock_level INTEGER DEFAULT 0',
      'ALTER TABLE suppliers ADD COLUMN opening_balance REAL DEFAULT 0',
      'ALTER TABLE customers ADD COLUMN opening_balance REAL DEFAULT 0',
      'ALTER TABLE customers ADD COLUMN total_debt REAL DEFAULT 0',
      'ALTER TABLE customers ADD COLUMN total_paid REAL DEFAULT 0',
    ];
    for (final sql in missingColumns) {
      try {
        await customStatement(sql);
        log('v46: Added missing column: $sql');
      } catch (_) {}
    }

    await _logMigrationStep(46, 'ensure_missing_tables', 'completed');
  }

  Future<void> _fixPurchaseAmountTypes() async {
    try {
      log(' Fixing amount types in purchases table...');

      // Check current schema
      final result = await customSelect('PRAGMA table_info(purchases)').get();

      bool needsFix = false;
      for (final row in result) {
        final columnName = row.data['name'] as String;
        final columnType = row.data['type'] as String;
        if ((columnName == 'total_amount' || columnName == 'paid_amount') &&
            columnType.toUpperCase().contains('INTEGER')) {
          needsFix = true;
          log('Found $columnName with INTEGER type, needs conversion to REAL');
        }
      }

      if (!needsFix) {
        log(' Amount columns already have correct REAL type');
        return;
      }

      log(' Converting INTEGER amount columns to REAL...');

      // 1. Create new table with correct schema
      await customStatement('''
        CREATE TABLE purchases_v2 (
          id INTEGER PRIMARY KEY,
          supplier_id TEXT,
          invoice_number TEXT,
          description TEXT,
          total_amount REAL,
          paid_amount REAL,
          payment_method TEXT,
          status TEXT,
          purchase_date TEXT,
          created_at TEXT,
          notes TEXT,
          created_by TEXT,
          is_deleted INTEGER DEFAULT 0
        )
      ''');

      // 2. Copy data with type conversion
      await customStatement('''
        INSERT INTO purchases_v2
        SELECT 
          id, supplier_id, invoice_number, description, 
          CAST(total_amount AS REAL), CAST(paid_amount AS REAL),
          payment_method, status, purchase_date, created_at, 
          notes, created_by, is_deleted
        FROM purchases
      ''');

      // 3. Drop old table
      await customStatement('DROP TABLE purchases');

      // 4. Rename new table
      await customStatement('ALTER TABLE purchases_v2 RENAME TO purchases');

      log(' Amount types fixed successfully');
    } catch (e) {
      log(' Error fixing amount types: $e');
    }
  }

  Future<void> _ensureStaffTables(Migrator m) async {
    final staffTablesList = [
      staffTable,
      attendanceTable,
      vacations,
      staffAdvances,
      payrollTable,
      rewardsPenalties,
      performanceReviews,
      staffDocuments,
    ];

    for (final table in staffTablesList) {
      try {
        await m.createTable(table as TableInfo);
        log('Created table');
      } catch (e) {
        // Table probably already exists
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
