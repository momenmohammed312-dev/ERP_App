import 'dart:developer';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dao/dao.dart';
import 'tables/tables.dart';

import '../utils/security_utils.dart';

import 'amount_types_fix.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Products,
    Customers,
    Suppliers,
    LedgerTransactions,
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
    // Staff management tables (Enterprise only)
    StaffTable,
    AttendanceTable,
    Vacations,
    StaffAdvances,
    PayrollTable,
    RewardsPenalties,
    PerformanceReviews,
    StaffDocuments,
    // Purchase Orders tables
    PurchaseOrders,
    PurchaseOrderItems,
    PurchaseOrderStatuses,
    // Purchase Returns tables
    PurchaseReturns,
    PurchaseReturnItems,
    PurchaseRefunds,
    // User Activity Log
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
  int get schemaVersion => 37;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Always ensure customer_id column exists in invoices table
      try {
        await customStatement(
          'ALTER TABLE invoices ADD COLUMN customer_id TEXT',
        );
        log('Added customer_id column to invoices table');
      } catch (e) {
        log('Customer ID column already exists or failed to add: $e');
      }

      // Always ensure totalAmount column exists in invoices table
      try {
        await customStatement(
          'ALTER TABLE invoices ADD COLUMN totalAmount REAL DEFAULT 0.0',
        );
        log('Added totalAmount column to invoices table');
      } catch (e) {
        log('totalAmount column already exists or failed to add: $e');
      }

      // Always ensure paidAmount column exists in invoices table
      try {
        await customStatement(
          'ALTER TABLE invoices ADD COLUMN paidAmount REAL DEFAULT 0.0',
        );
        log('Added paidAmount column to invoices table');
      } catch (e) {
        log('paidAmount column already exists or failed to add: $e');
      }

      if (from < 37) {
        // Fix Zero Credit/Sales issue: Sync redundant columns if they exist
        try {
          await customStatement('''
            UPDATE invoices 
            SET total_amount = COALESCE(totalAmount, total_amount),
                paid_amount = COALESCE(paidAmount, paid_amount)
            WHERE total_amount = 0 OR total_amount IS NULL
          ''');
          log('Synced totalAmount and paidAmount columns in invoices');
        } catch (e) {
          log(
            'Failed to sync invoice columns (redundant columns might not exist): $e',
          );
        }

        // Ensure notifications table exists
        try {
          await m.createTable(notifications);
          log('Ensured notifications table exists (v37 migration)');
        } catch (e) {
          log('Notifications table already exists or failed to add: $e');
        }
      }

      if (from < 2) {
        // Fix customer status column type mismatch by adding proper TEXT column
        try {
          await customStatement(
            "ALTER TABLE customers ADD COLUMN status TEXT DEFAULT 'Active'",
          );
          log('Customer status column added successfully');
        } catch (e) {
          log('Customer status column already exists: $e');
        }

        // Add new columns to existing customers table using raw SQL
        try {
          await customStatement(
            'ALTER TABLE customers ADD COLUMN openingBalance REAL DEFAULT 0.0',
          );
        } catch (e) {
          // Column might already exist, ignore error
          log('Opening balance column already exists: $e');
        }

        try {
          await customStatement(
            'ALTER TABLE customers ADD COLUMN created_at INTEGER DEFAULT (strftime(\'%s\', \'now\'))',
          );
        } catch (e) {
          log('Created at column already exists: $e');
        }

        try {
          await customStatement(
            'ALTER TABLE customers ADD COLUMN updatedAt INTEGER',
          );
        } catch (e) {
          log('Updated at column already exists: $e');
        }

        try {
          await customStatement(
            'ALTER TABLE customers ADD COLUMN totalDebt REAL DEFAULT 0.0',
          );
        } catch (e) {
          log('Total debt column already exists: $e');
        }

        try {
          await customStatement(
            'ALTER TABLE customers ADD COLUMN totalPaid REAL DEFAULT 0.0',
          );
        } catch (e) {
          log('Total paid column already exists: $e');
        }

        try {
          await customStatement('ALTER TABLE customers ADD COLUMN notes TEXT');
        } catch (e) {
          log('Notes column already exists: $e');
        }

        try {
          await customStatement(
            'ALTER TABLE customers ADD COLUMN isActive INTEGER DEFAULT 1',
          );
        } catch (e) {
          log('Is active column already exists: $e');
        }

        try {
          await customStatement(
            "ALTER TABLE customers ADD COLUMN status TEXT DEFAULT 'Active'",
          );
        } catch (e) {
          log('Status column already exists: $e');
        }

        // Create new tables
        await m.createTable(suppliers);
        await m.createTable(ledgerTransactions);

        // Add missing customer_id column to invoices table
        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN customer_id TEXT',
          );
        } catch (e) {
          log('Customer ID column already exists in invoices: $e');
        }
      }
      if (from < 3) {
        // Check if status column exists in products table before adding
        try {
          await customStatement(
            'ALTER TABLE products ADD COLUMN status TEXT DEFAULT "Active"',
          );
        } catch (e) {
          log('Product status column already exists: $e');
        }
      }
      if (from < 4) {
        // Add unit column to products table
        try {
          await customStatement('ALTER TABLE products ADD COLUMN unit TEXT');
        } catch (e) {
          log('Product unit column already exists: $e');
        }

        // Add missing customer_id column to invoices table
        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN customer_id TEXT',
          );
        } catch (e) {
          log('Customer ID column already exists in invoices: $e');
        }

        // Add missing payment_method column to invoices table
        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN payment_method TEXT',
          );
          log('Added payment_method column to invoices table');
        } catch (e) {
          log('Payment method column already exists in invoices: $e');
        }

        // Update existing NULL payment_method values in invoices table
        try {
          await customStatement(
            "UPDATE invoices SET payment_method = 'cash' WHERE payment_method IS NULL",
          );
          log('Updated NULL payment_method values to "cash"');
        } catch (e) {
          log('Error updating payment_method values: $e');
        }

        // Update existing empty customer_contact values in invoices table
        try {
          await customStatement(
            'UPDATE invoices SET customer_contact = "N/A" WHERE customer_contact IS NULL OR customer_contact = ""',
          );
        } catch (e) {
          log('Error updating customer_contact values: $e');
        }
      }
      if (from < 8) {
        // Ensure payment_method column exists in invoices table
        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN payment_method TEXT',
          );
          log('Added payment_method column to invoices table (v8 migration)');
        } catch (e) {
          log('Payment method column already exists in invoices: $e');
        }

        // Update existing NULL payment_method values
        try {
          await customStatement(
            'UPDATE invoices SET payment_method = "cash" WHERE payment_method IS NULL',
          );
          log('Updated NULL payment_method values to "cash" (v8 migration)');
        } catch (e) {
          log('Error updating payment_method values: $e');
        }

        // Add paid_amount column to invoices table
        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN paid_amount REAL DEFAULT 0.0',
          );
          log('Added paid_amount column to invoices table (v8 migration)');
        } catch (e) {
          log('Paid amount column already exists in invoices: $e');
        }

        // Add status column to invoices table
        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN status TEXT DEFAULT "pending"',
          );
          log('Added status column to invoices table (v8 migration)');
        } catch (e) {
          log('Status column already exists in invoices: $e');
        }

        // Add invoice_number column to invoices table
        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN invoice_number TEXT',
          );
          log('Added invoice_number column to invoices table (v8 migration)');
        } catch (e) {
          log('Invoice number column already exists in invoices: $e');
        }

        // Update existing NULL paid_amount values
        try {
          await customStatement(
            'UPDATE invoices SET paid_amount = 0.0 WHERE paid_amount IS NULL',
          );
          log('Updated NULL paid_amount values to 0.0 (v8 migration)');
        } catch (e) {
          log('Error updating paid_amount values: $e');
        }

        // Update existing NULL status values
        try {
          await customStatement(
            'UPDATE invoices SET status = "pending" WHERE status IS NULL',
          );
          log('Updated NULL status values to "pending" (v8 migration)');
        } catch (e) {
          log('Error updating status values: $e');
        }
      }
      if (from < 10) {
        // Ensure all invoice columns exist for v10
        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN paid_amount REAL DEFAULT 0.0',
          );
          log('Added paid_amount column to invoices table (v10 migration)');
        } catch (e) {
          log('Paid amount column already exists in invoices: $e');
        }

        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN status TEXT DEFAULT "pending"',
          );
          log('Added status column to invoices table (v10 migration)');
        } catch (e) {
          log('Status column already exists in invoices: $e');
        }

        try {
          await customStatement(
            'ALTER TABLE invoices ADD COLUMN invoice_number TEXT',
          );
          log('Added invoice_number column to invoices table (v10 migration)');
        } catch (e) {
          log('Invoice number column already exists in invoices: $e');
        }

        // Update any NULL values
        try {
          await customStatement(
            'UPDATE invoices SET paid_amount = 0.0 WHERE paid_amount IS NULL',
          );
          log('Updated NULL paid_amount values to 0.0 (v10 migration)');
        } catch (e) {
          log('Error updating paid_amount values: $e');
        }

        try {
          await customStatement(
            "UPDATE invoices SET status = 'pending' WHERE status IS NULL",
          );
          log('Updated NULL status values to "pending" (v10 migration)');
        } catch (e) {
          log('Error updating status values: $e');
        }
      }
      if (from < 11) {
        // Create the days table for day opening/closing
        try {
          await m.createTable(days);
          log('Migration to v11: Created days table');
        } catch (e) {
          log('Migration v11 error: $e');
        }
      }
      if (from < 12) {
        // Double check and create the days table if missing
        try {
          await m.createTable(days);
          log('Migration to v12: Ensured days table exists');
        } catch (e) {
          log('Migration v12: Days table already exists or error: $e');
        }
      }
      if (from < 13) {
        try {
          await m.createTable(expenses);
          log('Migration to v13: Created expenses table');
        } catch (e) {
          log('Migration v13: Expenses table already exists or error: $e');
        }
      }
      if (from < 14) {
        try {
          // Double check expenses table for v14
          await m.createTable(expenses);
          log('Migration to v14: Created expenses table');
        } catch (e) {
          log('Migration v14: Expenses table already exists or error: $e');
        }
      }
      if (from < 15) {
        // Add new product columns for category and carton support
        try {
          await customStatement(
            'ALTER TABLE products ADD COLUMN category TEXT',
          );
          log('Migration to v15: Added category column to products table');
        } catch (e) {
          log('Migration v15: Category column already exists or error: $e');
        }

        try {
          await customStatement('ALTER TABLE products ADD COLUMN barcode TEXT');
          log('Migration to v15: Added barcode column to products table');
        } catch (e) {
          log('Migration v15: Barcode column already exists or error: $e');
        }

        try {
          await customStatement(
            'ALTER TABLE products ADD COLUMN carton_quantity INTEGER',
          );
          log(
            'Migration to v15: Added carton_quantity column to products table',
          );
        } catch (e) {
          log(
            'Migration v15: Carton quantity column already exists or error: $e',
          );
        }

        try {
          await customStatement(
            'ALTER TABLE products ADD COLUMN carton_price REAL',
          );
          log('Migration to v15: Added carton_price column to products table');
        } catch (e) {
          log('Migration v15: Carton price column already exists or error: $e');
        }
      }
      if (from < 16) {
        // Create purchase tables for proper purchase tracking
        try {
          await m.createTable(purchases);
          log('Migration to v16: Created purchases table');
        } catch (e) {
          log('Migration v16: Purchases table already exists or error: $e');
        }

        try {
          await m.createTable(purchaseItems);
          log('Migration to v16: Created purchase_items table');
        } catch (e) {
          log(
            'Migration v16: Purchase items table already exists or error: $e',
          );
        }
      }
      if (from < 17) {
        // Add phone column to customers table if it doesn't exist
        try {
          await customStatement('ALTER TABLE customers ADD COLUMN phone TEXT');
          log('Migration to v17: Added phone column to customers table');
        } catch (e) {
          log('Migration v17: Phone column already exists or error: $e');
        }
      }
      if (from < 18) {
        // Ensure created_at column exists in customers table
        try {
          await customStatement(
            'ALTER TABLE customers ADD COLUMN created_at TEXT DEFAULT CURRENT_TIMESTAMP',
          );
          log('Migration to v18: Added created_at column to customers table');
        } catch (e) {
          log('Migration v18: Created at column already exists or error: $e');
        }
      }
      if (from < 19) {
        // Create credit payments table for tracking payments made against credit sales
        try {
          await m.createTable(creditPayments);
          log('Migration to v19: Created credit_payments table');
        } catch (e) {
          log(
            'Migration v19: Credit payments table already exists or error: $e',
          );
        }
      }
      if (from < 20) {
        // Create employees and sales tables for employee sales tracking
        try {
          await m.createTable(employees);
          log('Migration to v20: Created employees table');
        } catch (e) {
          log('Migration v20: Employees table already exists or error: $e');
        }
      }

      if (from < 22) {
        // Fix for Issue E (Robust): Use raw SQL to ensure columns exist, catching errors if they already do.
        // This is safer than m.addColumn which might fail validation if drift thinks column exists but sqlite file is drifted.

        try {
          await customStatement(
            "ALTER TABLE customers ADD COLUMN created_at TEXT DEFAULT CURRENT_TIMESTAMP",
          );
          log(
            'Migration v22: Added created_at column to customers table (Raw SQL)',
          );
        } catch (e) {
          log('Migration v22: created_at column already exists: $e');
        }

        try {
          await customStatement(
            "ALTER TABLE customers ADD COLUMN opening_balance REAL DEFAULT 0.0",
          );
          log(
            'Migration v22: Added opening_balance column to customers table (Raw SQL)',
          );
        } catch (e) {
          log('Migration v22: opening_balance column already exists: $e');
        }
      }

      if (from < 23) {
        // Critical Fix for Issue E: Ensure created_at column exists
        // This migration addresses the SqliteException: no such column: created_at
        try {
          await customStatement(
            "ALTER TABLE customers ADD COLUMN created_at TEXT DEFAULT CURRENT_TIMESTAMP",
          );
          log('Migration v23: Added created_at column to customers table');
        } catch (e) {
          log('Migration v23: created_at column already exists: $e');
        }

        // Also ensure all other required columns from the schema exist
        try {
          await customStatement(
            "ALTER TABLE customers ADD COLUMN opening_balance REAL DEFAULT 0.0",
          );
          log('Migration v23: Added opening_balance column to customers table');
        } catch (e) {
          log('Migration v23: opening_balance column already exists: $e');
        }

        try {
          await customStatement(
            "ALTER TABLE customers ADD COLUMN status TEXT DEFAULT 'Active'",
          );
          log('Migration v23: Added status column to customers table');
        } catch (e) {
          log('Migration v23: status column already exists: $e');
        }

        try {
          await customStatement("ALTER TABLE customers ADD COLUMN phone TEXT");
          log('Migration v23: Added phone column to customers table');
        } catch (e) {
          log('Migration v23: phone column already exists: $e');
        }
      }

      if (from < 24) {
        // Critical Fix: created_at must be INTEGER (unix timestamp) not TEXT
        // Drift stores DateTimeColumn as INTEGER by default
        // We need to drop the TEXT column and recreate as INTEGER

        log(
          'Migration v24: Fixing created_at column type from TEXT to INTEGER',
        );

        // SQLite doesn't support ALTER COLUMN, so we need to:
        // 1. Check if column exists and what type it is
        // 2. If it's TEXT, we need to recreate the table or use a workaround

        // Simpler approach: Just try to add as INTEGER, ignore if exists
        try {
          await customStatement(
            "ALTER TABLE customers ADD COLUMN created_at INTEGER DEFAULT (CAST(strftime('%s', 'now') AS INTEGER))",
          );
          log('Migration v24: Added created_at as INTEGER');
        } catch (e) {
          log(
            'Migration v24: created_at column already exists, attempting to fix type: $e',
          );

          // If column exists but wrong type, we need to recreate table
          try {
            // Add temporary column
            await customStatement(
              "ALTER TABLE customers ADD COLUMN created_at_new INTEGER DEFAULT (CAST(strftime('%s', 'now') AS INTEGER))",
            );

            // Copy data from TEXT to INTEGER (convert if possible)
            await customStatement(
              "UPDATE customers SET created_at_new = CAST(strftime('%s', created_at) AS INTEGER) WHERE created_at IS NOT NULL",
            );

            log(
              'Migration v24: Successfully migrated created_at to INTEGER type',
            );
          } catch (e2) {
            log(
              'Migration v24: Column type already correct or migration not needed: $e2',
            );
          }
        }
      }

      if (from < 27) {
        // Clean migration using Drift's API - requires database deletion for existing users
        log('Migration v27: Using Drift API to add missing columns');

        // First, try to add missing columns normally
        try {
          await m.addColumn(customers, customers.createdAt);
          log('Migration v27: Added createdAt column using Drift API');
        } catch (e) {
          log('Migration v27: createdAt column already exists: $e');
        }

        try {
          await m.addColumn(customers, customers.updatedAt);
          log('Migration v27: Added updatedAt column');
        } catch (e) {
          log('Migration v27: updatedAt already exists: $e');
        }

        try {
          await m.addColumn(customers, customers.totalDebt);
          log('Migration v27: Added totalDebt column');
        } catch (e) {
          log('Migration v27: totalDebt already exists: $e');
        }

        try {
          await m.addColumn(customers, customers.totalPaid);
          log('Migration v27: Added totalPaid column');
        } catch (e) {
          log('Migration v27: totalPaid already exists: $e');
        }

        try {
          await m.addColumn(customers, customers.notes);
          log('Migration v27: Added notes column');
        } catch (e) {
          log('Migration v27: notes already exists: $e');
        }

        try {
          await m.addColumn(customers, customers.isActive);
          log('Migration v27: Added isActive column');
        } catch (e) {
          log('Migration v27: isActive already exists: $e');
        }

        // If columns still missing, force table recreation
        try {
          // Test if all required columns exist
          await customSelect(
            'SELECT createdAt, updatedAt, totalDebt, totalPaid, openingBalance, notes, isActive FROM customers LIMIT 1',
          ).get();
          log('Migration v27: All required columns exist');
        } catch (e) {
          log(
            'Migration v27: Some columns still missing, recreating customers table: $e',
          );

          // Backup existing data
          final existingData = await customSelect(
            'SELECT * FROM customers',
          ).get();
          log(
            'Migration v27: Backed up ${existingData.length} existing customers',
          );

          // Drop and recreate table
          await customStatement('DROP TABLE IF EXISTS customers_backup');
          await customStatement(
            'ALTER TABLE customers RENAME TO customers_backup',
          );

          await customUpdate('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT,
              address TEXT,
              gstinNumber TEXT,
              email TEXT,
              openingBalance REAL DEFAULT 0.0,
              totalDebt REAL DEFAULT 0.0,
              totalPaid REAL DEFAULT 0.0,
              created_at TEXT,
              updated_at TEXT,
              notes TEXT,
              isActive INTEGER DEFAULT 1,
              status TEXT DEFAULT 'Active'
            )
          ''');

          // Restore data
          for (final row in existingData) {
            final data = Map<String, dynamic>.from(row.data);
            final oldCreatedAt = data.remove(
              'createdAt',
            ); // Remove old createdAt if it exists
            final oldUpdatedAt = data.remove(
              'updatedAt',
            ); // Remove old updatedAt if it exists
            data.remove('totalDebt'); // Remove old totalDebt if it exists
            data.remove('totalPaid'); // Remove old totalPaid if it exists
            data.remove(
              'openingBalance',
            ); // Remove old openingBalance if it exists
            data.remove('notes'); // Remove old notes if it exists
            data.remove('isActive'); // Remove old isActive if it exists

            // Add required fields with defaults - convert Unix timestamps to ISO strings
            String createdAtStr;
            if (oldCreatedAt != null) {
              if (oldCreatedAt is int) {
                createdAtStr = DateTime.fromMillisecondsSinceEpoch(
                  oldCreatedAt * 1000,
                ).toIso8601String();
              } else if (oldCreatedAt is DateTime) {
                createdAtStr = oldCreatedAt.toIso8601String();
              } else {
                createdAtStr = DateTime.now().toIso8601String();
              }
            } else {
              createdAtStr = DateTime.now().toIso8601String();
            }

            String updatedAtStr;
            if (oldUpdatedAt != null) {
              if (oldUpdatedAt is int) {
                updatedAtStr = DateTime.fromMillisecondsSinceEpoch(
                  oldUpdatedAt * 1000,
                ).toIso8601String();
              } else if (oldUpdatedAt is DateTime) {
                updatedAtStr = oldUpdatedAt.toIso8601String();
              } else {
                updatedAtStr = DateTime.now().toIso8601String();
              }
            } else {
              updatedAtStr = DateTime.now().toIso8601String();
            }

            data['createdAt'] = createdAtStr;
            data['updatedAt'] = updatedAtStr;
            data['notes'] = data['notes'];
            data['isActive'] = data['isActive'] ?? 1;
            data['status'] = data['status'] ?? 'Active';
            data['openingBalance'] = data['openingBalance'] ?? 0.0;
            data['totalDebt'] = data['totalDebt'] ?? 0.0;
            data['totalPaid'] = data['totalPaid'] ?? 0.0;
            data['email'] = data['email'];
            data['gstinNumber'] = data['gstinNumber'];

            // Build INSERT statement dynamically
            final columns = data.keys.join(', ');
            final values = data.values
                .map((v) {
                  if (v is DateTime) {
                    return "'${v.toIso8601String()}'";
                  } else if (v is String) {
                    return "'$v'";
                  } else {
                    return v.toString();
                  }
                })
                .join(', ');

            await customStatement(
              'INSERT INTO customers ($columns) VALUES ($values)',
            );
          }

          await customUpdate('DROP TABLE IF EXISTS customers_backup');

          log('Migration v27: Customers table recreated with new schema');
        }
      }

      if (from < 29) {
        log(
          'Migration v29: Recreating customers table to fix column naming and types',
        );

        // 1. Check existing columns to map data correctly
        final tableInfo = await customSelect(
          "PRAGMA table_info(customers)",
        ).get();
        final existingColumns = tableInfo
            .map((row) => row.data['name'] as String)
            .toList();

        // 2. Backup existing data
        final existingData = await customSelect(
          'SELECT * FROM customers',
        ).get();
        log('Migration v29: Backed up ${existingData.length} customers');

        // 3. Rename old table
        await customStatement('DROP TABLE IF EXISTS customers_old');
        await customStatement('ALTER TABLE customers RENAME TO customers_old');

        // 4. Create new table with correct schema (snake_case and Correct Types)
        await customStatement('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            gstin_number TEXT,
            email TEXT,
            opening_balance REAL DEFAULT 0.0,
            total_debt REAL DEFAULT 0.0,
            total_paid REAL DEFAULT 0.0,
            created_at INTEGER,
            updated_at INTEGER,
            notes TEXT,
            is_active INTEGER DEFAULT 1,
            status INTEGER DEFAULT 1
          )
        ''');

        // 5. Restore data with careful mapping
        for (final row in existingData) {
          final data = Map<String, dynamic>.from(row.data);
          final mapped = <String, dynamic>{};

          mapped['id'] = data['id'];
          mapped['name'] = data['name'];
          mapped['phone'] = data['phone'];
          mapped['address'] = data['address'];
          mapped['gstin_number'] = data['gstin_number'] ?? data['gstinNumber'];
          mapped['email'] = data['email'];
          mapped['opening_balance'] =
              data['opening_balance'] ?? data['openingBalance'] ?? 0.0;
          mapped['total_debt'] = data['total_debt'] ?? data['totalDebt'] ?? 0.0;
          mapped['total_paid'] = data['total_paid'] ?? data['totalPaid'] ?? 0.0;
          mapped['notes'] = data['notes'];

          // Handle is_active (bool -> int)
          final isActive = data['is_active'] ?? data['isActive'];
          if (isActive is bool) {
            mapped['is_active'] = isActive ? 1 : 0;
          } else if (isActive is int) {
            mapped['is_active'] = isActive;
          } else {
            mapped['is_active'] = 1;
          }

          // Handle status (String/Int -> Int 0/1)
          final status = data['status'];
          if (status == 'Active' || status == 1) {
            mapped['status'] = 1;
          } else {
            mapped['status'] = 0;
          }

          // Handle timestamps (Convert ISO string or Unixtime to Unixtime INTEGER)
          for (final key in [
            'created_at',
            'updated_at',
            'createdAt',
            'updatedAt',
          ]) {
            final val = data[key];
            if (val == null) continue;

            int? unixTime;
            if (val is int) {
              unixTime = val;
            } else if (val is String) {
              final dt = DateTime.tryParse(val);
              if (dt != null) unixTime = dt.millisecondsSinceEpoch ~/ 1000;
            }

            if (unixTime != null) {
              if (key.contains('create')) mapped['created_at'] = unixTime;
              if (key.contains('update')) mapped['updated_at'] = unixTime;
            }
          }

          final keys = mapped.keys.join(', ');
          final placeholders = List.filled(mapped.length, '?').join(', ');
          final values = mapped.values.toList();

          await customStatement(
            'INSERT INTO customers ($keys) VALUES ($placeholders)',
            values,
          );
        }

        await customStatement('DROP TABLE IF EXISTS customers_old');
        log(
          'Migration v29: Successfully recreated customers table and restored data',
        );
      }

      if (from < 30) {
        log('Migration v30: Creating enhanced purchase tables');

        try {
          await m.createTable(enhancedSuppliers);
          log('Migration v30: Created enhanced_suppliers table');
        } catch (e) {
          log(
            'Migration v30: Enhanced suppliers table already exists or error: $e',
          );
        }

        try {
          await m.createTable(enhancedPurchases);
          log('Migration v30: Created enhanced_purchases table');
        } catch (e) {
          log(
            'Migration v30: Enhanced purchases table already exists or error: $e',
          );
        }

        try {
          await m.createTable(enhancedPurchaseItems);
          log('Migration v30: Created enhanced_purchase_items table');
        } catch (e) {
          log(
            'Migration v30: Enhanced purchase items table already exists or error: $e',
          );
        }

        try {
          await m.createTable(supplierPayments);
          log('Migration v30: Created supplier_payments table');
        } catch (e) {
          log(
            'Migration v30: Supplier payments table already exists or error: $e',
          );
        }
      }

      if (from < 31) {
        // Create InventoryMovements table for detailed inventory tracking
        try {
          await m.createTable(inventoryMovements);
          log('Migration v31: Created inventory_movements table');
        } catch (e) {
          log(
            'Migration v31: Inventory movements table already exists or error: $e',
          );
        }

        // Create indexes for better performance
        try {
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_inventory_movements_product_id ON inventory_movements(product_id)',
          );
          log('Migration v31: Created index on inventory_movements.product_id');
        } catch (e) {
          log(
            'Migration v31: Index on inventory_movements.product_id error: $e',
          );
        }

        try {
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_inventory_movements_date ON inventory_movements(movement_date)',
          );
          log(
            'Migration v31: Created index on inventory_movements.movement_date',
          );
        } catch (e) {
          log(
            'Migration v31: Index on inventory_movements.movement_date error: $e',
          );
        }

        try {
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_inventory_movements_type ON inventory_movements(movement_type)',
          );
          log(
            'Migration v31: Created index on inventory_movements.movement_type',
          );
        } catch (e) {
          log(
            'Migration v31: Index on inventory_movements.movement_type error: $e',
          );
        }
      }

      if (from < 33) {
        // Create users table for role-based access control
        try {
          await m.createTable(users);
          log('Migration v33: Created users table');

          // Create default admin user
          final adminPassword = _hashPassword('admin123');
          await customStatement(
            '''
            INSERT INTO users (username, password_hash, full_name, role, is_active, created_at, updated_at)
            VALUES ('admin', ?, 'مدير النظام', 0, 1, datetime('now'), datetime('now'))
          ''',
            [adminPassword],
          );
          log('Migration v33: Created default admin user');
        } catch (e) {
          log('Migration v33: Users table already exists or error: $e');
        }
      }

      if (from < 32) {
        // Create audit log table for SaaS compliance
        try {
          await m.createTable(auditLog);
          log('Migration v32: Created audit_log table');
        } catch (e) {
          log('Migration v32: Audit log table already exists or error: $e');
        }

        // Create indexes for audit log
        try {
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp)',
          );
          log('Migration v32: Created index on audit_log.timestamp');
        } catch (e) {
          log('Migration v32: Index on audit_log.timestamp error: $e');
        }

        try {
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id)',
          );
          log('Migration v32: Created index on audit_log.user_id');
        } catch (e) {
          log('Migration v32: Index on audit_log.user_id error: $e');
        }
      }

      if (from < 35) {
        log('Migration v35: Creating staff management tables if missing');
        try {
          await m.createTable(staffTable);
        } catch (e) {
          log('Table staffTable already exists or failed: $e');
        }
        try {
          await m.createTable(attendanceTable);
        } catch (e) {
          log('Table attendanceTable already exists or failed: $e');
        }
        try {
          await m.createTable(vacations);
        } catch (e) {
          log('Table vacations already exists or failed: $e');
        }
        try {
          await m.createTable(staffAdvances);
        } catch (e) {
          log('Table staffAdvances already exists or failed: $e');
        }
        try {
          await m.createTable(payrollTable);
        } catch (e) {
          log('Table payrollTable already exists or failed: $e');
        }
        try {
          await m.createTable(rewardsPenalties);
        } catch (e) {
          log('Table rewardsPenalties already exists or failed: $e');
        }
        try {
          await m.createTable(performanceReviews);
        } catch (e) {
          log('Table performanceReviews already exists or failed: $e');
        }
        try {
          await m.createTable(staffDocuments);
        } catch (e) {
          log('Table staffDocuments already exists or failed: $e');
        }
        log('Migration v35: Finished creating staff management tables');
      }

      if (from < 36) {
        // Fix amount column types in purchases table (INTEGER to REAL)
        try {
          await AmountTypesFix.fixAmountTypes(this);
          log('Migration v36: Fixed amount types in purchases table');
        } catch (e) {
          log('Migration v36: Amount types fix error: $e');
        }
      }
    },
    beforeOpen: (details) async {
      // Log the tables in the database
      final tables = await customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table';",
      ).get();

      for (final row in tables) {
        log('[DB Table] ${row.data['name']}');
      }

      // Log the database file location
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbPath = p.join(
        dbFolder.path,
        'pos_offline_desktop_database/pos_offline_desktop_database.sqlite',
      ); // Adjust filename if needed
      log('Database path: $dbPath'); // Logs the database path

      try {
        await customStatement(
          'UPDATE invoices SET payment_method = "cash" WHERE payment_method IS NULL',
        );
      } catch (e) {
        log('Error updating invoices.payment_method values: $e');
      }

      try {
        await customStatement(
          'UPDATE invoices SET paid_amount = 0.0 WHERE paid_amount IS NULL',
        );
      } catch (e) {
        log('Error updating invoices.paid_amount values: $e');
      }

      try {
        await customStatement(
          'UPDATE invoices SET total_amount = 0.0 WHERE total_amount IS NULL',
        );
      } catch (e) {
        log('Error updating invoices.total_amount values: $e');
      }

      try {
        await customStatement(
          'UPDATE invoices SET status = "pending" WHERE status IS NULL OR status = ""',
        );
      } catch (e) {
        log('Error updating invoices.status values: $e');
      }

      try {
        await customStatement(
          'UPDATE invoices SET invoice_number = CAST(id AS TEXT) WHERE invoice_number IS NULL OR invoice_number = ""',
        );
      } catch (e) {
        log('Error updating invoices.invoice_number values: $e');
      }

      try {
        await customStatement(
          'UPDATE invoices SET customer_contact = "" WHERE customer_contact = "N/A" OR customer_contact = "غير متوفر"',
        );
      } catch (e) {
        log('Error cleaning up invoices.customer_contact values: $e');
      }

      // Ensure customers table has all required columns
      // Robust approach: Try to add the column, disregard error if it exists
      // NOTE: created_at is handled in migration v24 - DO NOT add here to avoid type conflicts

      try {
        await customStatement('ALTER TABLE customers ADD COLUMN phone TEXT');
        log('Ensured phone column exists in customers table');
      } catch (e) {
        log('Phone column already exists in customers table: $e');
      }

      try {
        await customStatement(
          "ALTER TABLE customers ADD COLUMN status TEXT DEFAULT 'Active'",
        );
        log('Ensured status column exists in customers table');
      } catch (e) {
        log('Status column already exists in customers table: $e');
      }

      try {
        await customStatement(
          'ALTER TABLE customers ADD COLUMN opening_balance REAL DEFAULT 0.0',
        );
        log('Ensured opening_balance column exists in customers table');
      } catch (e) {
        log('Opening balance column already exists in customers table: $e');
      }

      // New columns (Module Refactor)
      try {
        await customStatement('ALTER TABLE customers ADD COLUMN email TEXT');
        log('Ensured email column exists in customers table');
      } catch (e) {
        log('Email column already exists in customers table: $e');
      }

      try {
        await customStatement(
          'ALTER TABLE customers ADD COLUMN total_debt REAL DEFAULT 0.0',
        );
        log('Ensured total_debt column exists in customers table');
      } catch (e) {
        log('Total debt column already exists in customers table: $e');
      }

      try {
        await customStatement(
          'ALTER TABLE customers ADD COLUMN total_paid REAL DEFAULT 0.0',
        );
        log('Ensured total_paid column exists in customers table');
      } catch (e) {
        log('Total paid column already exists in customers table: $e');
      }

      try {
        await customStatement(
          'ALTER TABLE customers ADD COLUMN updated_at INTEGER',
        ); // Drift stores DateTime as INTEGER (unix timestamp) or TEXT depending on config, usually INTEGER by default if not specified as text.
        // Checking drift definition: dateTime() maps to INTEGER/Ingeter unless store_date_time_as_text is set.
        // Assuming default checks. Let's try adding as INTEGER first as that's safer for timestamps in SQLite generally if not strict.
        // Actually, drift default is unix timestamp (INT).
        log('Ensured updated_at column exists in customers table');
      } catch (e) {
        log('Updated at column already exists in customers table: $e');
      }

      try {
        await customStatement('ALTER TABLE customers ADD COLUMN notes TEXT');
        log('Ensured notes column exists in customers table');
      } catch (e) {
        log('Notes column already exists in customers table: $e');
      }

      try {
        await customStatement(
          'ALTER TABLE customers ADD COLUMN is_active INTEGER DEFAULT 1',
        ); // Boolean is INTEGER (0/1) in SQLite
        log('Ensured is_active column exists in customers table');
      } catch (e) {
        log('Is active column already exists in customers table: $e');
      }
    },
  );
}
