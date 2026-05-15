import 'dart:developer';
import 'app_database.dart';

/// Migration to fix amount column types in purchases table
/// Converts total_amount and paid_amount from INTEGER to REAL
class AmountTypesFix {
  static Future<void> fixAmountTypes(AppDatabase db) async {
    try {
      log(' Fixing amount types in purchases table...');

      // Check current schema
      final result = await db
          .customSelect('PRAGMA table_info(purchases)')
          .get();

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
      await db.customStatement('''
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
      await db.customStatement('''
        INSERT INTO purchases_v2
        SELECT
          id,
          supplier_id,
          invoice_number,
          description,
          CAST(total_amount AS REAL),
          CAST(paid_amount AS REAL),
          payment_method,
          status,
          purchase_date,
          created_at,
          notes,
          created_by,
          is_deleted
        FROM purchases
      ''');

      // 3. Drop old table
      await db.customStatement('DROP TABLE purchases');

      // 4. Rename new table
      await db.customStatement('ALTER TABLE purchases_v2 RENAME TO purchases');

      log(' Amount types fixed successfully');
    } catch (e) {
      log(' Error fixing amount types: $e');
      rethrow;
    }
  }
}
