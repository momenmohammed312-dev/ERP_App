import 'dart:developer';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pos_offline_desktop/core/database/dao/customer_container_dao.dart';
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
import 'package:pos_offline_desktop/core/database/tables/customer_containers_table.dart';
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
import 'package:pos_offline_desktop/core/database/tables/attendance_device_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/attendance_settings_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/database/tables/empty_barnika_tracking_table.dart';
import 'package:pos_offline_desktop/core/database/tables/sync_queue_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_cost_components_table.dart';
import 'package:pos_offline_desktop/core/database/tables/accounts_table.dart';
import 'package:pos_offline_desktop/core/database/tables/journal_entries_table.dart';
import 'package:pos_offline_desktop/core/database/tables/journal_lines_table.dart';
import 'package:pos_offline_desktop/core/database/tables/partners_table.dart';
import 'package:pos_offline_desktop/core/database/tables/equity_transactions_table.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/sync_queue_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/vegetable_shipment_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/empty_barnika_tracking_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_cost_component_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/accounts_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/journal_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/equity_dao.dart';
import 'customer_status_fix.dart';
import 'customer_opening_balance_fix.dart';
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
    CustomerContainers,
    BiometricDevices,
    StaffBiometricMappings,
    AttendanceRawEvents,
    AttendanceSyncLogs,
    AttendanceSettings,
    VegetableShipments,
    EmptyBarnikaTracking,
    SyncQueue,
    BillOfMaterials,
    BomItems,
    ManufacturingOrders,
    ManufacturingCostComponents,
    Accounts,
    JournalEntries,
    JournalLines,
    Partners,
    EquityTransactions,
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
    AttendanceDeviceDao,
    CustomerContainerDao,
    VegetableShipmentDao,
    EmptyBarnikaTrackingDao,
    SyncQueueDao,
    BomDao,
    ManufacturingOrderDao,
    ManufacturingCostComponentDao,
    AccountsDao,
    JournalDao,
    EquityDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  String _hashPassword(String password) {
    return SecurityUtils.hashPassword(password);
  }

  @override
  int get schemaVersion => 61;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _ensureStaffTables(m);
      await _ensureCriticalColumns(m);
      // Fresh installs also need the unique indexes (Drift doesn't emit them from uniqueKeys)
      try {
        await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_staff_date ON attendance_table(staff_id, date)');
      } catch (e) {
        log('onCreate attendance index warning: $e');
      }
      try {
        await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_payroll_staff_period ON payroll_table(staff_id, payroll_period)');
      } catch (e) {
        log('onCreate payroll index warning: $e');
      }
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

      // 4i. Schema v47 — attendance device integration
      if (from < 47) {
        await _runV47Migrations(m);
      }

      // 4j. Schema v48 — attendance settings + staff schedule columns
      if (from < 48) {
        await _runV48Migrations(m);
      }

      // 4k. Schema v49 — برنيكه (returnable containers) support
      if (from < 49) {
        await _runV49Migrations(m);
      }

      // 4l. Schema v50 — allow walk-in (cash) sales in customer_containers
      if (from < 50) {
        await _runV50Migrations(m);
      }

      // 4m. Schema v51 — vegetable shipments + empty barnika tracking tables
      if (from < 51) {
        await _runV51Migrations(m);
      }

      // 4n. Schema v52 — cash_sessions.settlement_amount (day-close settlement)
      if (from < 52) {
        await _runV52Migrations(m);
      }

      // 4o. Schema v53 — multi-device sync foundation (sync_id/created_at/updated_at
      // columns on products/invoices/invoice_items + sync_queue table)
      if (from < 53) {
        await _runV53Migrations(m);
      }

      // 4p. Schema v54 — sync_queue.device_name (enqueue-time device marker)
      if (from < 54) {
        await _runV54Migrations(m);
      }

      // 4q. Schema v55 — staff biometric index
      if (from < 55) {
        await _runV55Migrations(m);
      }

      // 4r. Schema v56 — manufacturing foundation (Phase 1: productType)
      if (from < 56) {
        await _runV56Migrations(m);
      }

      // 4s. Schema v57 — headless accounting core (Accounts + Journal)
      if (from < 57) {
        await _runV57Migrations(m);
      }

      // 4t. Schema v58 — unique constraints for attendance and payroll (A3)
      if (from < 58) {
        await _runV58Migrations(m);
      }

      // 4u. Schema v59 — equity / partners (Phase 6)
      if (from < 59) {
        await _runV59Migrations(m);
      }

      // 4v. Schema v60 — attendance excused (إذن/عذر) flag
      if (from < 60) {
        await _runV60Migrations(m);
      }

      // 4w. Schema v61 — attendance excused_hours (خصم تناسبي بالساعة)
      if (from < 61) {
        await _runV61Migrations(m);
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
      await CustomerStatusFix.fixCustomerStatusColumn(this);
      await CustomerOpeningBalanceFix.fixDuplicateOpeningTransactions(this);

      // Safety check to prevent SQL logic error on missing audit_log
      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS audit_log (
            id TEXT PRIMARY KEY,
            user_id INTEGER,
            action TEXT NOT NULL,
            table_name_field TEXT NOT NULL,
            record_id INTEGER,
            details TEXT,
            timestamp INTEGER NOT NULL,
            ip_address TEXT,
            old_value TEXT,
            new_value TEXT
          )
        ''');
      } catch (e) {
        log('Error creating audit_log table: $e');
      }

      // Safety check to prevent SQL logic error on missing cash_sessions
      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS cash_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            opened_by TEXT,
            opened_at INTEGER NOT NULL,
            closed_at INTEGER,
            status TEXT NOT NULL DEFAULT 'closed',
            opening_balance REAL NOT NULL DEFAULT 0.0,
            closing_balance REAL,
            closing_cash REAL,
            difference REAL,
            total_sales REAL NOT NULL DEFAULT 0.0,
            total_expenses REAL NOT NULL DEFAULT 0.0,
            notes TEXT
          )
        ''');
      } catch (e) {
        log('Error creating cash_sessions table: $e');
      }

      // Safety check to prevent SQL logic error on missing damaged_items
      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS damaged_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL REFERENCES products(id),
            quantity INTEGER NOT NULL,
            unit_cost REAL NOT NULL,
            total_loss REAL NOT NULL,
            reason TEXT NOT NULL,
            damage_date INTEGER NOT NULL,
            notes TEXT,
            recorded_by TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          )
        ''');
      } catch (e) {
        log('Error creating damaged_items table: $e');
      }

      // Safety check for customer_containers (ensure correct schema and no FK to customers)
      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS customer_containers (
            product_id INTEGER NOT NULL REFERENCES products(id),
            customer_id TEXT NOT NULL,
            quantity_out INTEGER NOT NULL DEFAULT 0,
            quantity_returned INTEGER NOT NULL DEFAULT 0,
            date INTEGER,
            note TEXT,
            updated_at INTEGER,
            PRIMARY KEY (product_id, customer_id)
          )
        ''');
      } catch (e) {
        log('Error ensuring customer_containers: $e');
      }

      // Recreate to drop FK constraint if needed, copying data safely without 'id'
      try {
        final tableInfo = await customSelect("PRAGMA foreign_key_list('customer_containers')").get();
        bool hasCustomerFk = false;
        for (final row in tableInfo) {
          if (row.read<String>('table') == 'customers') {
            hasCustomerFk = true;
            break;
          }
        }
        if (hasCustomerFk) {
          log('customer_containers has legacy foreign key to customers. Recreating table...');
          await customStatement('PRAGMA foreign_keys = OFF');
          await customStatement('''
            CREATE TABLE customer_containers_new (
              product_id INTEGER NOT NULL REFERENCES products(id),
              customer_id TEXT NOT NULL,
              quantity_out INTEGER NOT NULL DEFAULT 0,
              quantity_returned INTEGER NOT NULL DEFAULT 0,
              date INTEGER,
              note TEXT,
              updated_at INTEGER,
              PRIMARY KEY (product_id, customer_id)
            )
          ''');
          
          try {
            await customStatement('''
              INSERT INTO customer_containers_new
                (product_id, customer_id, quantity_out, quantity_returned, date, note, updated_at)
              SELECT
                product_id, customer_id, quantity_out, quantity_returned, date, note, updated_at
              FROM customer_containers
            ''');
          } catch (e) {
            log('Error copying customer_containers data: $e');
          }
          
          await customStatement('DROP TABLE customer_containers');
          await customStatement('ALTER TABLE customer_containers_new RENAME TO customer_containers');
          await customStatement('PRAGMA foreign_keys = ON');
          log('Recreated customer_containers successfully.');
        }
      } catch (e) {
        log('Error checking/recreating customer_containers FK: $e');
      }

      // Safety check to prevent SQL logic error on missing sales_returns tables
      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS sales_returns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            return_number TEXT NOT NULL,
            original_invoice_id INTEGER REFERENCES invoices(id),
            customer_id TEXT,
            customer_name TEXT NOT NULL,
            return_date INTEGER NOT NULL,
            total_amount REAL NOT NULL,
            return_reason TEXT NOT NULL,
            notes TEXT,
            status TEXT NOT NULL DEFAULT 'completed',
            processed_by TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
          )
        ''');
      } catch (e) {
        log('Error creating sales_returns table: $e');
      }

      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS sales_return_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            return_id INTEGER NOT NULL REFERENCES sales_returns(id) ON DELETE CASCADE,
            product_id INTEGER NOT NULL REFERENCES products(id),
            product_name TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            unit_price REAL NOT NULL,
            total_price REAL NOT NULL
          )
        ''');
      } catch (e) {
        log('Error creating sales_return_items table: $e');
      }

      // Safety check for app_notifications table
      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS app_notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_id TEXT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            send_at INTEGER NOT NULL,
            sent INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        log('Error creating app_notifications table: $e');
      }

      // Safety check for attendance_settings table
      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS attendance_settings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            setting_key TEXT NOT NULL UNIQUE,
            setting_value TEXT NOT NULL,
            description TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      } catch (e) {
        log('Error creating attendance_settings table: $e');
      }

      // Safety check for staff_table schedule columns
      try {
        await customStatement('ALTER TABLE staff_table ADD COLUMN work_schedule_start TEXT');
      } catch (_) {}
      try {
        await customStatement('ALTER TABLE staff_table ADD COLUMN work_schedule_end TEXT');
      } catch (_) {}
      try {
        await customStatement('ALTER TABLE staff_table ADD COLUMN work_days TEXT');
      } catch (_) {}
      try {
        await customStatement('ALTER TABLE staff_table ADD COLUMN weekend_day TEXT');
      } catch (_) {}
      try {
        await customStatement('ALTER TABLE staff_table ADD COLUMN use_default_schedule INTEGER NOT NULL DEFAULT 1');
      } catch (_) {}
      try {
        await customStatement('ALTER TABLE staff_biometric_mappings ADD COLUMN device_user_name TEXT');
      } catch (_) {}

      // Safety check for biometric attendance tables
      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS biometric_devices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_code TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            vendor TEXT,
            model TEXT,
            connection_type TEXT NOT NULL,
            ip_address TEXT,
            port INTEGER,
            serial_number TEXT,
            location TEXT,
            auth_token TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            last_sync_at INTEGER,
            last_sync_status TEXT,
            last_sync_error TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      } catch (e) {
        log('Error creating biometric_devices table: $e');
      }

      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS staff_biometric_mappings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            staff_id TEXT NOT NULL,
            device_id INTEGER NOT NULL REFERENCES biometric_devices(id),
            external_user_id TEXT NOT NULL,
            card_number TEXT,
            finger_index INTEGER,
            template_ref TEXT,
            enrollment_status TEXT NOT NULL,
            is_primary INTEGER NOT NULL DEFAULT 0,
            enrolled_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      } catch (e) {
        log('Error creating staff_biometric_mappings table: $e');
      }

      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS attendance_raw_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id INTEGER NOT NULL REFERENCES biometric_devices(id),
            external_user_id TEXT NOT NULL,
            event_time INTEGER NOT NULL,
            event_type TEXT,
            raw_payload TEXT,
            sync_batch_id TEXT,
            dedup_hash TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL,
            matched_staff_id TEXT,
            resulting_attendance_id INTEGER,
            error_message TEXT,
            created_at INTEGER NOT NULL,
            processed_at INTEGER
          )
        ''');
      } catch (e) {
        log('Error creating attendance_raw_events table: $e');
      }

      try {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS attendance_sync_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id INTEGER NOT NULL,
            sync_batch_id TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            finished_at INTEGER,
            status TEXT NOT NULL,
            events_fetched INTEGER NOT NULL DEFAULT 0,
            events_matched INTEGER NOT NULL DEFAULT 0,
            events_unmatched INTEGER NOT NULL DEFAULT 0,
            events_duplicate INTEGER NOT NULL DEFAULT 0,
            error_message TEXT,
            triggered_by TEXT
          )
        ''');
      } catch (e) {
        log('Error creating attendance_sync_logs table: $e');
      }

      // Performance indexes for attendance_raw_events
      try {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_raw_events_status ON attendance_raw_events(status)',
        );
      } catch (e) {
        log('Error creating idx_raw_events_status: $e');
      }

      try {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_raw_events_device_status ON attendance_raw_events(device_id, status)',
        );
      } catch (e) {
        log('Error creating idx_raw_events_device_status: $e');
      }

      try {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sync_logs_device ON attendance_sync_logs(device_id)',
        );
      } catch (e) {
        log('Error creating idx_sync_logs_device: $e');
      }

      // Safety check for critical columns on existing tables
      await _ensureCriticalColumnsInBeforeOpen();

      // Safety check for staff-related tables (missing in some DBs)
      await _ensureStaffTablesSafetyCheck();
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

  Future<void> _runV47Migrations(Migrator m) async {
    await _logMigrationStep(47, 'attendance_devices_integration', 'started');

    try {
      try {
        await m.createTable(biometricDevices);
        log('v47: Created biometric_devices table');
      } catch (e) {
        log('v47 warning biometric_devices: $e');
      }

      try {
        await m.createTable(staffBiometricMappings);
        log('v47: Created staff_biometric_mappings table');
      } catch (e) {
        log('v47 warning staff_biometric_mappings: $e');
      }

      try {
        await m.createTable(attendanceRawEvents);
        log('v47: Created attendance_raw_events table');
      } catch (e) {
        log('v47 warning attendance_raw_events: $e');
      }

      try {
        await m.createTable(attendanceSyncLogs);
        log('v47: Created attendance_sync_logs table');
      } catch (e) {
        log('v47 warning attendance_sync_logs: $e');
      }

      final attendanceColumns = [
        attendanceTable.source,
        attendanceTable.sourceDeviceId,
        attendanceTable.rawEventId,
        attendanceTable.overrideReason,
      ];

      for (final col in attendanceColumns) {
        try {
          await m.addColumn(attendanceTable, col);
          log('v47: Added column ${col.name} to attendance_table');
        } catch (e) {
          log('v47 warning attendance_table column ${col.name}: $e');
        }
      }

      // Add performance indexes for attendance_raw_events
      try {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_raw_events_status ON attendance_raw_events(status)',
        );
        log('v47: Created index idx_raw_events_status');
      } catch (e) {
        log('v47 warning idx_raw_events_status: $e');
      }

      try {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_raw_events_device_status ON attendance_raw_events(device_id, status)',
        );
        log('v47: Created index idx_raw_events_device_status');
      } catch (e) {
        log('v47 warning idx_raw_events_device_status: $e');
      }

      try {
        await m.database.customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sync_logs_device ON attendance_sync_logs(device_id)',
        );
        log('v47: Created index idx_sync_logs_device');
      } catch (e) {
        log('v47 warning idx_sync_logs_device: $e');
      }

      await _logMigrationStep(47, 'attendance_devices_integration', 'completed');
    } catch (e) {
      await _logMigrationStep(47, 'attendance_devices_integration', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v48 — attendance settings table + staff schedule columns
  Future<void> _runV48Migrations(Migrator m) async {
    await _logMigrationStep(48, 'attendance_settings_schedule', 'started');
    try {
      // 1. Create AttendanceSettings table
      try {
        await m.createTable(attendanceSettings);
        log('v48: Created attendance_settings table');
      } catch (e) {
        log('v48 warning attendance_settings: $e');
      }

      // 2. Add schedule columns to staff_table
      final scheduleColumns = [
        'ALTER TABLE staff_table ADD COLUMN work_schedule_start TEXT',
        'ALTER TABLE staff_table ADD COLUMN work_schedule_end TEXT',
        'ALTER TABLE staff_table ADD COLUMN work_days TEXT',
        'ALTER TABLE staff_table ADD COLUMN weekend_day TEXT',
        'ALTER TABLE staff_table ADD COLUMN use_default_schedule INTEGER NOT NULL DEFAULT 1',
      ];
      for (final sql in scheduleColumns) {
        try {
          await customStatement(sql);
          log('v48: $sql');
        } catch (e) {
          log('v48 warning (column may exist): $e');
        }
      }

      // 3. Insert default settings
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      try {
        await customStatement('''
          INSERT OR IGNORE INTO attendance_settings (setting_key, setting_value, description, created_at, updated_at)
          VALUES 
            ('default_work_start', '09:00', 'وقت بدء العمل الافتراضي', $nowMs, $nowMs),
            ('default_work_end', '17:00', 'وقت نهاية العمل الافتراضي', $nowMs, $nowMs),
            ('default_work_days', 'sun,mon,tue,wed,thu', 'أيام العمل الافتراضية', $nowMs, $nowMs),
            ('default_weekend', 'fri', 'يوم الإجازة الافتراضي', $nowMs, $nowMs),
            ('grace_period_minutes', '15', 'فترة السماح بالتأخير (دقائق)', $nowMs, $nowMs),
            ('overtime_threshold_hours', '8', 'ساعات العمل قبل حساب إضافي', $nowMs, $nowMs),
            ('late_penalty_amount', '0', 'مبلغ غرامة التأخير (0 = بدون)', $nowMs, $nowMs),
            ('absence_penalty_amount', '0', 'مبلغ غرامة الغياب (0 = بدون)', $nowMs, $nowMs),
            ('overtime_rate_multiplier', '1.5', 'مضاعف العمل الإضافي', $nowMs, $nowMs)
        ''');
        log('v48: Inserted default attendance settings');
      } catch (e) {
        log('v48 warning (default settings): $e');
      }

      await _logMigrationStep(48, 'attendance_settings_schedule', 'completed');
    } catch (e) {
      await _logMigrationStep(48, 'attendance_settings_schedule', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v49 — برنيكه (returnable containers) support
  Future<void> _runV49Migrations(Migrator m) async {
    await _logMigrationStep(49, 'barneka_containers', 'started');
    try {
      // 1. Add barneka flag to products
      try {
        await customStatement(
          'ALTER TABLE products ADD COLUMN barneka INTEGER NOT NULL DEFAULT 0',
        );
        log('v49: Added barneka column to products');
      } catch (e) {
        log('v49 warning (barneka column may exist): $e');
      }

      // 2. Create customer_containers table
      try {
        await m.createTable(customerContainers);
        log('v49: Created customer_containers table');
      } catch (e) {
        log('v49 warning customer_containers: $e');
      }

      await _logMigrationStep(49, 'barneka_containers', 'completed');
    } catch (e) {
      await _logMigrationStep(49, 'barneka_containers', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v50 — allow walk-in (cash) sales in customer_containers
  /// by dropping the strict FK to customers and using a nullable customer_id
  /// with a UNIQUE(product_id, customer_id) constraint. Existing data is kept.
  Future<void> _runV50Migrations(Migrator m) async {
    await _logMigrationStep(50, 'barneka_walkin', 'started');
    try {
      try {
        await customStatement('''
          CREATE TABLE customer_containers_new (
            product_id INTEGER NOT NULL REFERENCES products(id),
            customer_id TEXT NOT NULL,
            quantity_out INTEGER NOT NULL DEFAULT 0,
            quantity_returned INTEGER NOT NULL DEFAULT 0,
            date INTEGER,
            note TEXT,
            updated_at INTEGER,
            PRIMARY KEY (product_id, customer_id)
          )
        ''');
        await customStatement('''
          INSERT INTO customer_containers_new
            (id, product_id, customer_id, quantity_out, quantity_returned, date, note, updated_at)
          SELECT
            id, product_id, customer_id, quantity_out, quantity_returned, date, note, updated_at
          FROM customer_containers
        ''');
        await customStatement('DROP TABLE customer_containers');
        await customStatement(
          'ALTER TABLE customer_containers_new RENAME TO customer_containers',
        );
        log('v50: Recreated customer_containers without customers FK');
      } catch (e) {
        log('v50 warning (customer_containers recreate): $e');
      }

      await _logMigrationStep(50, 'barneka_walkin', 'completed');
    } catch (e) {
      await _logMigrationStep(50, 'barneka_walkin', 'failed', error: e.toString());
      rethrow;
    }
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
      {'table': 'products', 'column': 'cost_price',   'type': 'REAL'},
      {'table': 'products', 'column': 'min_stock_level', 'type': 'INTEGER DEFAULT 0'},
      {'table': 'products', 'column': 'barneka', 'type': 'INTEGER NOT NULL DEFAULT 0'},
      {'table': 'products', 'column': 'product_type', 'type': 'TEXT'},
      {'table': 'invoice_items', 'column': 'discount', 'type': 'REAL DEFAULT 0'},
      {'table': 'invoice_items', 'column': 'commission', 'type': 'REAL DEFAULT 0'},
      {'table': 'invoice_items', 'column': 'unit_cost_at_time', 'type': 'REAL'},
      {'table': 'attendance_table', 'column': 'source', 'type': 'TEXT'},
      {'table': 'attendance_table', 'column': 'source_device_id', 'type': 'INTEGER'},
      {'table': 'attendance_table', 'column': 'raw_event_id', 'type': 'INTEGER'},
      {'table': 'attendance_table', 'column': 'override_reason', 'type': 'TEXT'},
      {'table': 'attendance_table', 'column': 'excused', 'type': 'INTEGER NOT NULL DEFAULT 0'},
      {'table': 'attendance_table', 'column': 'excused_hours', 'type': 'REAL NOT NULL DEFAULT 0'},
      {'table': 'audit_log', 'column': 'old_value', 'type': 'TEXT'},
      {'table': 'audit_log', 'column': 'new_value', 'type': 'TEXT'},
      // Invoice void support columns
      {'table': 'invoices', 'column': 'voided_at', 'type': 'INTEGER'},
      {'table': 'invoices', 'column': 'void_reason', 'type': 'TEXT'},
      {'table': 'invoices', 'column': 'voided_by', 'type': 'TEXT'},
      // Expenses extra columns
      {'table': 'expenses', 'column': 'user_id', 'type': 'TEXT'},
      {'table': 'expenses', 'column': 'day_id', 'type': 'TEXT'},
      // Multi-device sync columns (v53)
      {'table': 'products', 'column': 'sync_id', 'type': 'TEXT'},
      {'table': 'products', 'column': 'created_at', 'type': 'INTEGER'},
      {'table': 'products', 'column': 'updated_at', 'type': 'INTEGER'},
      {'table': 'invoices', 'column': 'sync_id', 'type': 'TEXT'},
      {'table': 'invoices', 'column': 'created_at', 'type': 'INTEGER'},
      {'table': 'invoices', 'column': 'updated_at', 'type': 'INTEGER'},
      {'table': 'invoice_items', 'column': 'sync_id', 'type': 'TEXT'},
      {'table': 'invoice_items', 'column': 'created_at', 'type': 'INTEGER'},
      {'table': 'invoice_items', 'column': 'updated_at', 'type': 'INTEGER'},
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

    // Multi-device sync outbox table (idempotent safety net, same columns as
    // SyncQueue class in tables/sync_queue_table.dart).
    await _ensureSyncQueueTableIfMissing();
  }

  Future<void> _ensureCriticalColumnsInBeforeOpen() async {
    final columnChecks = [
      {'table': 'products', 'column': 'cost_price', 'type': 'REAL'},
      {'table': 'products', 'column': 'min_stock_level', 'type': 'INTEGER DEFAULT 0'},
      {'table': 'products', 'column': 'barneka', 'type': 'INTEGER NOT NULL DEFAULT 0'},
      {'table': 'products', 'column': 'product_type', 'type': 'TEXT'},
      {'table': 'invoices', 'column': 'customer_id', 'type': 'TEXT'},
      {'table': 'invoices', 'column': 'total_amount', 'type': 'REAL DEFAULT 0.0'},
      {'table': 'invoices', 'column': 'paid_amount', 'type': 'REAL DEFAULT 0.0'},
      {'table': 'invoices', 'column': 'status', 'type': 'TEXT DEFAULT "pending"'},
      {'table': 'customers', 'column': 'status', 'type': 'TEXT DEFAULT "Active"'},
      {'table': 'customers', 'column': 'created_at', 'type': 'INTEGER'},
      {'table': 'invoice_items', 'column': 'discount', 'type': 'REAL DEFAULT 0'},
      {'table': 'invoice_items', 'column': 'commission', 'type': 'REAL DEFAULT 0'},
      {'table': 'invoice_items', 'column': 'unit_cost_at_time', 'type': 'REAL'},
      {'table': 'attendance_table', 'column': 'source', 'type': 'TEXT'},
      {'table': 'attendance_table', 'column': 'source_device_id', 'type': 'INTEGER'},
      {'table': 'attendance_table', 'column': 'raw_event_id', 'type': 'INTEGER'},
      {'table': 'attendance_table', 'column': 'override_reason', 'type': 'TEXT'},
      {'table': 'attendance_table', 'column': 'excused', 'type': 'INTEGER NOT NULL DEFAULT 0'},
      {'table': 'attendance_table', 'column': 'excused_hours', 'type': 'REAL NOT NULL DEFAULT 0'},
      {'table': 'audit_log', 'column': 'old_value', 'type': 'TEXT'},
      {'table': 'audit_log', 'column': 'new_value', 'type': 'TEXT'},
      // Invoice void support columns
      {'table': 'invoices', 'column': 'voided_at', 'type': 'INTEGER'},
      {'table': 'invoices', 'column': 'void_reason', 'type': 'TEXT'},
      {'table': 'invoices', 'column': 'voided_by', 'type': 'TEXT'},
      // Expenses extra columns
      {'table': 'expenses', 'column': 'user_id', 'type': 'TEXT'},
      {'table': 'expenses', 'column': 'day_id', 'type': 'TEXT'},
      // Cash session day-close settlement (v52)
      {'table': 'cash_sessions', 'column': 'settlement_amount', 'type': 'REAL'},
      // Multi-device sync columns (v53)
      {'table': 'products', 'column': 'sync_id', 'type': 'TEXT'},
      {'table': 'products', 'column': 'created_at', 'type': 'INTEGER'},
      {'table': 'products', 'column': 'updated_at', 'type': 'INTEGER'},
      {'table': 'invoices', 'column': 'sync_id', 'type': 'TEXT'},
      {'table': 'invoices', 'column': 'created_at', 'type': 'INTEGER'},
      {'table': 'invoices', 'column': 'updated_at', 'type': 'INTEGER'},
      {'table': 'invoice_items', 'column': 'sync_id', 'type': 'TEXT'},
      {'table': 'invoice_items', 'column': 'created_at', 'type': 'INTEGER'},
      {'table': 'invoice_items', 'column': 'updated_at', 'type': 'INTEGER'},
    ];
    for (final check in columnChecks) {
      try {
        await customStatement(
          'ALTER TABLE ${check['table']} ADD COLUMN ${check['column']} ${check['type']}',
        );
      } catch (_) {}
    }

    await _ensureSyncQueueTableIfMissing();
  }

  /// Idempotent safety net that creates the sync outbox table when it is
  /// missing (mirrors the SyncQueue class in tables/sync_queue_table.dart,
  /// including the v54 `device_name` column). Also backfills sync ids for any
  /// rows that were left without them by an interrupted v53 migration.
  Future<void> _ensureSyncQueueTableIfMissing() async {
    try {
      await customStatement('''
        CREATE TABLE IF NOT EXISTS sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_ref TEXT NOT NULL,
          record_sync_id TEXT NOT NULL,
          operation TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000),
          synced_at INTEGER,
          retry_count INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          device_name TEXT
        )
      ''');
    } catch (e) {
      log('Ensure sync_queue table warning: $e');
    }

    for (final table in const ['products', 'invoices', 'invoice_items']) {
      try {
        final ids =
            await customSelect('SELECT id FROM $table WHERE sync_id IS NULL').get();
        for (final row in ids) {
          final id = row.data['id'];
          if (id is! int) continue;
          await customUpdate(
            'UPDATE $table SET sync_id = ? WHERE id = ?',
            variables: [
              Variable.withString(const Uuid().v4()),
              Variable.withInt(id),
            ],
          );
        }
      } catch (e) {
        log('Ensure sync_id backfill warning for $table: $e');
      }
    }
  }

  Future<void> _ensureStaffTablesSafetyCheck() async {
    final tables = {
      'staff_table': '''
        CREATE TABLE IF NOT EXISTS staff_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          national_id TEXT,
          phone TEXT,
          email TEXT,
          address TEXT,
          position TEXT NOT NULL,
          department TEXT,
          employment_type TEXT NOT NULL,
          basic_salary REAL NOT NULL,
          hourly_rate REAL,
          hire_date INTEGER NOT NULL,
          contract_end_date INTEGER,
          status TEXT NOT NULL,
          bank_name TEXT,
          bank_account TEXT,
          emergency_contact TEXT,
          emergency_phone TEXT,
          notes TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
          work_schedule_start TEXT,
          work_schedule_end TEXT,
          work_days TEXT,
          weekend_day TEXT,
          use_default_schedule INTEGER NOT NULL DEFAULT 1
        )
      ''',
      'attendance_table': '''
        CREATE TABLE IF NOT EXISTS attendance_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id TEXT NOT NULL,
          date INTEGER NOT NULL,
          check_in_time INTEGER,
          check_out_time INTEGER,
          check_in_location TEXT,
          check_out_location TEXT,
          working_hours REAL,
          status TEXT NOT NULL,
          leave_type TEXT,
          notes TEXT,
          overtime_hours REAL NOT NULL DEFAULT 0,
          excused INTEGER NOT NULL DEFAULT 0,
          excused_hours REAL NOT NULL DEFAULT 0,
          approved_by TEXT,
          approved_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''',
      'vacations': '''
        CREATE TABLE IF NOT EXISTS vacations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id TEXT NOT NULL,
          vacation_type TEXT NOT NULL,
          start_date INTEGER NOT NULL,
          end_date INTEGER NOT NULL,
          total_days INTEGER NOT NULL,
          reason TEXT,
          status TEXT NOT NULL,
          approved_by TEXT,
          approved_at INTEGER,
          rejection_reason TEXT,
          contact_during_vacation TEXT,
          handover_to TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''',
      'staff_advances': '''
        CREATE TABLE IF NOT EXISTS staff_advances (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id TEXT NOT NULL,
          amount REAL NOT NULL,
          reason TEXT,
          request_date INTEGER NOT NULL,
          payment_date INTEGER,
          status TEXT NOT NULL,
          approved_by TEXT,
          approved_at INTEGER,
          rejection_reason TEXT,
          payment_method TEXT,
          transaction_reference TEXT,
          installment_months INTEGER,
          monthly_deduction REAL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''',
      'payroll_table': '''
        CREATE TABLE IF NOT EXISTS payroll_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id TEXT NOT NULL,
          payroll_period TEXT NOT NULL,
          period_start INTEGER NOT NULL,
          period_end INTEGER NOT NULL,
          basic_salary REAL NOT NULL,
          overtime_hours REAL NOT NULL DEFAULT 0,
          overtime_rate REAL,
          overtime_pay REAL NOT NULL DEFAULT 0,
          allowances REAL NOT NULL DEFAULT 0,
          deductions REAL NOT NULL DEFAULT 0,
          advances REAL NOT NULL DEFAULT 0,
          taxes REAL NOT NULL DEFAULT 0,
          insurance REAL NOT NULL DEFAULT 0,
          other_deductions REAL NOT NULL DEFAULT 0,
          net_salary REAL NOT NULL,
          working_days INTEGER NOT NULL DEFAULT 0,
          present_days INTEGER NOT NULL DEFAULT 0,
          absent_days INTEGER NOT NULL DEFAULT 0,
          leave_days INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          payment_date INTEGER,
          payment_method TEXT,
          transaction_reference TEXT,
          approved_by TEXT,
          approved_at INTEGER,
          notes TEXT,
          bonus REAL NOT NULL DEFAULT 0.0,
          commission REAL NOT NULL DEFAULT 0.0,
          incentives REAL NOT NULL DEFAULT 0.0,
          rewards_total REAL NOT NULL DEFAULT 0.0,
          penalties_total REAL NOT NULL DEFAULT 0.0,
          expense_ref_id TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''',
      'rewards_penalties': '''
        CREATE TABLE IF NOT EXISTS rewards_penalties (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id TEXT NOT NULL,
          type TEXT NOT NULL,
          category TEXT NOT NULL,
          title TEXT NOT NULL,
          description TEXT,
          amount REAL,
          incident_date INTEGER NOT NULL,
          issued_by TEXT NOT NULL,
          status TEXT NOT NULL,
          effective_date INTEGER NOT NULL,
          expiry_date INTEGER,
          evidence TEXT,
          notes TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''',
      'performance_reviews': '''
        CREATE TABLE IF NOT EXISTS performance_reviews (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id TEXT NOT NULL,
          review_period TEXT NOT NULL,
          review_date INTEGER NOT NULL,
          reviewer_id TEXT NOT NULL,
          overall_rating REAL NOT NULL,
          work_quality_rating REAL NOT NULL,
          productivity_rating REAL NOT NULL,
          teamwork_rating REAL NOT NULL,
          punctuality_rating REAL NOT NULL,
          initiative_rating REAL NOT NULL,
          strengths TEXT,
          weaknesses TEXT,
          goals TEXT,
          recommendations TEXT,
          employee_comments TEXT,
          status TEXT NOT NULL,
          acknowledged_at INTEGER,
          next_review_date INTEGER,
          action_plan TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''',
      'staff_documents': '''
        CREATE TABLE IF NOT EXISTS staff_documents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id TEXT NOT NULL,
          document_type TEXT NOT NULL,
          document_name TEXT NOT NULL,
          file_path TEXT NOT NULL,
          file_name TEXT NOT NULL,
          file_type TEXT NOT NULL,
          file_size INTEGER NOT NULL,
          issue_date INTEGER,
          expiry_date INTEGER,
          issuing_authority TEXT,
          document_number TEXT,
          status TEXT NOT NULL,
          notes TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''',
    };

    for (final entry in tables.entries) {
      try {
        await customStatement(entry.value);
      } catch (e) {
        log('Staff table safety check (${entry.key}): $e');
      }
    }
  }

  /// Schema v51 — vegetable shipments + empty barnika tracking tables.
  /// These tables are registered in @DriftDatabase so `m.createAll()` handles
  /// fresh installs. For upgrades we create them defensively (IF NOT EXISTS).
  Future<void> _runV51Migrations(Migrator m) async {
    await _logMigrationStep(51, 'vegetable_shipments_barnika_tracking', 'started');
    try {
      // VegetableShipments table
      try {
        await m.createTable(vegetableShipments);
        log('v51: Created vegetable_shipments table');
      } catch (e) {
        log('v51: vegetable_shipments table likely already exists: $e');
      }

      // EmptyBarnikaTracking table
      try {
        await m.createTable(emptyBarnikaTracking);
        log('v51: Created empty_barnika_tracking table');
      } catch (e) {
        log('v51: empty_barnika_tracking table likely already exists: $e');
      }

      // shipmentId on Invoices (nullable FK, safe to add)
      try {
        await customStatement(
          'ALTER TABLE invoices ADD COLUMN shipment_id INTEGER REFERENCES vegetable_shipments(id)',
        );
        log('v51: Added shipment_id to invoices');
      } catch (e) {
        log('v51: invoices.shipment_id likely already exists: $e');
      }

      // shipmentId on InvoiceItems (nullable FK, safe to add)
      try {
        await customStatement(
          'ALTER TABLE invoice_items ADD COLUMN shipment_id INTEGER REFERENCES vegetable_shipments(id)',
        );
        log('v51: Added shipment_id to invoice_items');
      } catch (e) {
        log('v51: invoice_items.shipment_id likely already exists: $e');
      }

      await _logMigrationStep(51, 'vegetable_shipments_barnika_tracking', 'completed');
    } catch (e) {
      await _logMigrationStep(51, 'vegetable_shipments_barnika_tracking', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v52 — nullable settlement_amount on cash_sessions for the
  /// vegetable flavor day-close settlement entry. Safe to re-run; column is
  /// nullable so existing rows are never affected.
  Future<void> _runV52Migrations(Migrator m) async {
    await _logMigrationStep(52, 'cash_sessions_settlement_amount', 'started');
    try {
      try {
        await customStatement(
          'ALTER TABLE cash_sessions ADD COLUMN settlement_amount REAL',
        );
        log('v52: Added settlement_amount to cash_sessions');
      } catch (e) {
        log('v52: cash_sessions.settlement_amount likely already exists: $e');
      }
      await _logMigrationStep(52, 'cash_sessions_settlement_amount', 'completed');
    } catch (e) {
      await _logMigrationStep(52, 'cash_sessions_settlement_amount', 'failed', error: e.toString());
      rethrow;
    }
  }

  Future<void> _runV53Migrations(Migrator m) async {
    await _logMigrationStep(53, 'sync_columns_queue', 'started');
    try {
      // 1. Sync columns on the three int-PK tables (idempotent per column).
      for (final entry in const [
        ('products', 'sync_id', 'TEXT'),
        ('products', 'created_at', 'INTEGER'),
        ('products', 'updated_at', 'INTEGER'),
        ('invoices', 'sync_id', 'TEXT'),
        ('invoices', 'created_at', 'INTEGER'),
        ('invoices', 'updated_at', 'INTEGER'),
        ('invoice_items', 'sync_id', 'TEXT'),
        ('invoice_items', 'created_at', 'INTEGER'),
        ('invoice_items', 'updated_at', 'INTEGER'),
      ]) {
        try {
          await customStatement(
            'ALTER TABLE ${entry.$1} ADD COLUMN ${entry.$2} ${entry.$3}',
          );
          log('v53: Added ${entry.$2} to ${entry.$1}');
        } catch (e) {
          log('v53: ${entry.$1}.${entry.$2} likely already exists: $e');
        }
      }

      // 2. Outbox queue table (current schema, incl. device_name from v54 —
      //    the v54 step is a no-op when the column already exists here).
      try {
        await m.createTable(syncQueue);
        log('v53: Created sync_queue table');
      } catch (e) {
        log('v53: sync_queue table likely already exists: $e');
      }

      // 3. Backfill sync ids + timestamps for existing rows (fresh UUID per row).
      await _backfillSyncColumns('products');
      await _backfillSyncColumns('invoices');
      await _backfillSyncColumns('invoice_items');

      await _logMigrationStep(53, 'sync_columns_queue', 'completed');
    } catch (e) {
      await _logMigrationStep(53, 'sync_columns_queue', 'failed', error: e.toString());
      rethrow;
    }
  }

  Future<void> _runV54Migrations(Migrator m) async {
    await _logMigrationStep(54, 'sync_queue_device_name', 'started');
    try {
      try {
        await m.addColumn(syncQueue, syncQueue.deviceName);
        log('v54: Added sync_queue.device_name column');
      } catch (e) {
        log('v54: device_name column likely already exists: $e');
      }
      await _logMigrationStep(54, 'sync_queue_device_name', 'completed');
    } catch (e) {
      await _logMigrationStep(54, 'sync_queue_device_name', 'failed', error: e.toString());
      rethrow;
    }
  }

  Future<void> _runV55Migrations(Migrator m) async {
    await _logMigrationStep(55, 'biometric_mapping_index', 'started');
    try {
      try {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_staff_biometric_mapping_device_user '
          'ON staff_biometric_mappings(device_id, external_user_id)',
        );
        log('v55: Created index idx_staff_biometric_mapping_device_user');
      } catch (e) {
        log('v55: Index creation warning: $e');
      }
      await _logMigrationStep(55, 'biometric_mapping_index', 'completed');
    } catch (e) {
      await _logMigrationStep(55, 'biometric_mapping_index', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v56 — Manufacturing foundation (Phase 1: productType only).
  /// Purely additive: one nullable column, no data rewrite.
  /// Manufacturing foundation: productType + BOM tables.
  /// Purely additive, safe to re-run.
  Future<void> _runV56Migrations(Migrator m) async {
    await _logMigrationStep(56, 'manufacturing_foundation', 'started');
    try {
      try {
        await customStatement('ALTER TABLE products ADD COLUMN product_type TEXT');
        log('v56: Added products.product_type column');
      } catch (e) {
        log('v56: products.product_type likely already exists: $e');
      }
      try {
        await m.createTable(billOfMaterials);
        log('v56: Created bill_of_materials table');
      } catch (e) {
        log('v56: bill_of_materials likely already exists: $e');
      }
      try {
        await m.createTable(bomItems);
        log('v56: Created bom_items table');
      } catch (e) {
        log('v56: bom_items likely already exists: $e');
      }
      try {
        await m.createTable(manufacturingOrders);
        log('v56: Created manufacturing_orders table');
      } catch (e) {
        log('v56: manufacturing_orders likely already exists: $e');
      }
      try {
        await m.createTable(manufacturingCostComponents);
        log('v56: Created manufacturing_cost_components table');
      } catch (e) {
        log('v56: manufacturing_cost_components likely already exists: $e');
      }
      await _logMigrationStep(56, 'manufacturing_foundation', 'completed');
    } catch (e) {
      await _logMigrationStep(56, 'manufacturing_foundation', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v57 — Headless Accounting Core (Accounts + Journal double-entry)
  Future<void> _runV57Migrations(Migrator m) async {
    await _logMigrationStep(57, 'accounting_core', 'started');
    try {
      try {
        await m.createTable(accounts);
        log('v57: Created accounts table');
      } catch (e) {
        log('v57: accounts table likely already exists: $e');
      }
      try {
        await m.createTable(journalEntries);
        log('v57: Created journal_entries table');
      } catch (e) {
        log('v57: journal_entries table likely already exists: $e');
      }
      try {
        await m.createTable(journalLines);
        log('v57: Created journal_lines table');
      } catch (e) {
        log('v57: journal_lines table likely already exists: $e');
      }
      try {
        await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_posting_key ON journal_entries(posting_key)');
        log('v57: Created unique index on journal_entries.posting_key');
      } catch (e) {
        log('v57: posting_key index likely already exists: $e');
      }
      // Seed system accounts (INSERT OR IGNORE by code)
      final now = DateTime.now().millisecondsSinceEpoch;
      final systemAccounts = [
        ['1000', 'الصندوق (نقدية)', 'asset', 'debit'],
        ['1010', 'البنك', 'asset', 'debit'],
        ['1100', 'ذمم العملاء', 'asset', 'debit'],
        ['1200', 'المخزون', 'asset', 'debit'],
        ['2000', 'ذمم الموردين', 'liability', 'credit'],
        ['3000', 'رأس المال', 'equity', 'credit'],
        ['3100', 'مسحوبات الشريك', 'equity', 'debit'],
        ['3200', 'الأرباح المرحلة', 'equity', 'credit'],
        ['4000', 'إيرادات المبيعات', 'revenue', 'credit'],
        ['4100', 'مردودات المبيعات', 'revenue', 'debit'],
        ['5000', 'تكلفة البضاعة المباعة', 'expense', 'debit'],
        ['5100', 'مصروفات تشغيلية', 'expense', 'debit'],
      ];
      for (final acc in systemAccounts) {
        final id = const Uuid().v4();
        try {
          await customStatement(
            "INSERT OR IGNORE INTO accounts (id, code, name, type, normal_balance, is_system, is_active, created_at) VALUES (?, ?, ?, ?, ?, 1, 1, ?)",
            [id, acc[0], acc[1], acc[2], acc[3], now],
          );
        } catch (e) {
          log('v57: seed account ${acc[0]} failed: $e');
        }
      }
      log('v57: Seeded system accounts');
      await _logMigrationStep(57, 'accounting_core', 'completed');
    } catch (e) {
      await _logMigrationStep(57, 'accounting_core', 'failed', error: e.toString());
      rethrow;
    }
  }

  Future<void> _runV58Migrations(Migrator m) async {
    await _logMigrationStep(58, 'attendance_payroll_unique', 'started');
    try {
      // Clean duplicate attendance (keep latest per staffId+date)
      try {
        await customStatement('''
          DELETE FROM attendance_table WHERE id NOT IN (
            SELECT MAX(id) FROM attendance_table GROUP BY staff_id, date
          )
        ''');
        log('v58: Cleaned duplicate attendance');
      } catch (e) {
        log('v58 attendance dedup warning: $e');
      }
      // Clean duplicate payroll (keep latest per staffId+payroll_period)
      try {
        await customStatement('''
          DELETE FROM payroll_table WHERE id NOT IN (
            SELECT MAX(id) FROM payroll_table GROUP BY staff_id, payroll_period
          )
        ''');
        log('v58: Cleaned duplicate payroll');
      } catch (e) {
        log('v58 payroll dedup warning: $e');
      }
      // Create unique indexes
      try {
        await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_staff_date ON attendance_table(staff_id, date)');
        log('v58: Created idx_attendance_staff_date');
      } catch (e) {
        log('v58 attendance index warning: $e');
      }
      try {
        await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_payroll_staff_period ON payroll_table(staff_id, payroll_period)');
        log('v58: Created idx_payroll_staff_period');
      } catch (e) {
        log('v58 payroll index warning: $e');
      }
      await _logMigrationStep(58, 'attendance_payroll_unique', 'completed');
    } catch (e) {
      await _logMigrationStep(58, 'attendance_payroll_unique', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v59 — equity / partners (Phase 6)
  Future<void> _runV59Migrations(Migrator m) async {
    await _logMigrationStep(59, 'equity_partners', 'started');
    try {
      try {
        await m.createTable(partners);
        log('v59: Created partners table');
      } catch (e) {
        log('v59: partners table likely already exists: $e');
      }
      try {
        await m.createTable(equityTransactions);
        log('v59: Created equity_transactions table');
      } catch (e) {
        log('v59: equity_transactions table likely already exists: $e');
      }
      await _logMigrationStep(59, 'equity_partners', 'completed');
    } catch (e) {
      await _logMigrationStep(59, 'equity_partners', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v60 — attendance excused (إذن/عذر) flag
  Future<void> _runV60Migrations(Migrator m) async {
    await _logMigrationStep(60, 'attendance_excused', 'started');
    try {
      try {
        await customStatement('ALTER TABLE attendance_table ADD COLUMN excused INTEGER NOT NULL DEFAULT 0');
        log('v60: Added excused column to attendance_table');
      } catch (e) {
        log('v60 warning: excused column likely already exists: $e');
      }
      await _logMigrationStep(60, 'attendance_excused', 'completed');
    } catch (e) {
      await _logMigrationStep(60, 'attendance_excused', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Schema v61 — attendance excused_hours (الخصم التناسبي بالساعة للإذن/العذر)
  Future<void> _runV61Migrations(Migrator m) async {
    await _logMigrationStep(61, 'attendance_excused_hours', 'started');
    try {
      try {
        await customStatement('ALTER TABLE attendance_table ADD COLUMN excused_hours REAL NOT NULL DEFAULT 0');
        log('v61: Added excused_hours column to attendance_table');
      } catch (e) {
        log('v61 warning: excused_hours column likely already exists: $e');
      }
      await _logMigrationStep(61, 'attendance_excused_hours', 'completed');
    } catch (e) {
      await _logMigrationStep(61, 'attendance_excused_hours', 'failed', error: e.toString());
      rethrow;
    }
  }

  /// Backfills `sync_id` (a fresh UUID per row) plus `created_at`/`updated_at`
  /// for every existing row of a sync-enabled table that is still missing them.
  Future<void> _backfillSyncColumns(String table) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await customStatement(
        'UPDATE $table SET created_at = $now, updated_at = $now '
        'WHERE created_at IS NULL OR updated_at IS NULL',
      );
      final ids = await customSelect('SELECT id FROM $table').get();
      for (final row in ids) {
        final id = row.data['id'];
        if (id is! int) continue;
        await customUpdate(
          'UPDATE $table SET sync_id = ? WHERE id = ?',
          variables: [
            Variable.withString(const Uuid().v4()),
            Variable.withInt(id),
          ],
        );
      }
      log('v53: Backfilled sync_id for $table (${ids.length} rows)');
    } catch (e) {
      log('v53: Backfill $table warning: $e');
    }
  }
}
