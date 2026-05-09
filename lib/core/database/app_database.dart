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
  int get schemaVersion => 38;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
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

      // 3. Modern migrations (v31 - v38)
      if (from < 38) {
        await _runModernMigrations(m, from);
      }

      // 4. Always ensure critical columns exist (to fix drifted schemas)
      await _ensureCriticalColumns(m);
      
      // 5. Special data fixes
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
      await m.createTable(inventoryMovements);
      await m.createTable(auditLog);
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

  Future<void> _ensureCriticalColumns(Migrator m) async {
    // List of critical columns that often drift
    final checks = [
      {'table': 'invoices', 'column': 'customer_id', 'type': 'TEXT'},
      {'table': 'invoices', 'column': 'total_amount', 'type': 'REAL DEFAULT 0.0'},
      {'table': 'invoices', 'column': 'paid_amount', 'type': 'REAL DEFAULT 0.0'},
      {'table': 'invoices', 'column': 'status', 'type': 'TEXT DEFAULT "pending"'},
      {'table': 'customers', 'column': 'status', 'type': 'TEXT DEFAULT "Active"'},
      {'table': 'customers', 'column': 'created_at', 'type': 'INTEGER'},
    ];

    for (final check in checks) {
      try {
        await customStatement('ALTER TABLE ${check['table']} ADD COLUMN ${check['column']} ${check['type']}');
        log('Ensured column ${check['column']} exists in ${check['table']}');
      } catch (e) {
        // Ignore if already exists
      }
    }
  }
}
