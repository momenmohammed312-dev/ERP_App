import 'package:drift/drift.dart';
import 'dart:developer';

/// Fix for customer status datatype mismatch
/// This addresses SqliteException(20): datatype mismatch on INSERT INTO customers
class CustomerStatusFix {
  static Future<void> fixCustomerStatusColumn(DatabaseConnectionUser db) async {
    try {
      log('🔧 Fixing customer status column...');

      // Check if status column exists and its type
      final result = await db
          .customSelect('PRAGMA table_info(customers)')
          .get();

      bool hasStatusColumn = false;
      bool isIntegerType = false;

      for (final row in result) {
        final columnName = row.data['name'] as String;
        if (columnName == 'status') {
          hasStatusColumn = true;
          final columnType = row.data['type'] as String;
          isIntegerType = columnType.toUpperCase().contains('INTEGER');
          log('Found status column with type: $columnType');
          break;
        }
      }

      if (!hasStatusColumn) {
        log('Status column does not exist. Adding it...');
        await db.customStatement(
          "ALTER TABLE customers ADD COLUMN status TEXT DEFAULT 'Active'",
        );
        log('✅ Status column added successfully');
      } else if (isIntegerType) {
        log('Status column is INTEGER type. Fixing...');

        // 1. Backup existing data
        await db.customStatement(
          'CREATE TABLE customers_backup AS SELECT * FROM customers',
        );

        // 2. Drop the old table
        await db.customStatement('DROP TABLE customers');

        // 3. Create new table with correct schema (this will be handled by Drift)
        await db.customStatement('''
          CREATE TABLE customers (
            id TEXT NOT NULL PRIMARY KEY,
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
            status TEXT DEFAULT 'Active'
          )
        ''');

        // 4. Restore data (converting INTEGER status to TEXT)
        await db.customStatement('''
          INSERT INTO customers (
            id, name, phone, address, gstin_number, email, opening_balance,
            total_debt, total_paid, created_at, updated_at, notes, is_active, status
          )
          SELECT 
            id, name, phone, address, gstin_number, email, opening_balance,
            total_debt, total_paid, created_at, updated_at, notes, is_active,
            CASE 
              WHEN status = 1 THEN 'Active'
              WHEN status = 0 THEN 'Inactive'
              ELSE 'Active'
            END
          FROM customers_backup
        ''');

        // 5. Clean up backup
        await db.customStatement('DROP TABLE customers_backup');

        log('✅ Status column fixed successfully');
      } else {
        log('✅ Status column already has correct TEXT type');
      }
    } catch (e) {
      log('❌ Error fixing customer status column: $e');
      rethrow;
    }
  }
}
