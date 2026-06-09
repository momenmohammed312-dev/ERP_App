import 'dart:io';
import 'package:drift/native.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

/// Script to fix missing totalAmount column in invoices table
Future<void> main() async {
  print('🔧 Fixing database schema for Sales vs Purchases report...');

  try {
    // Get the database directory
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbPath = join(
      dbFolder.path,
      'pos_offline_desktop_database',
      'pos_offline_desktop_database.sqlite',
    );

    print('Database path: $dbPath');

    // Check if database exists
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      print('❌ Database file not found!');
      return;
    }

    // Connect to database
    final db = AppDatabase(NativeDatabase(dbFile));

    // Check if totalAmount column exists
    try {
      final result = await db
          .customSelect("SELECT total_amount FROM invoices LIMIT 1")
          .get();
      print('✅ total_amount column already exists');
    } catch (e) {
      print('⚠️ total_amount column missing, adding it...');

      // Add the column
      await db.customStatement(
        'ALTER TABLE invoices ADD COLUMN total_amount REAL DEFAULT 0.0',
      );

      // Add paid_amount column if missing
      try {
        await db.customSelect("SELECT paid_amount FROM invoices LIMIT 1").get();
        print('✅ paid_amount column already exists');
      } catch (e) {
        await db.customStatement(
          'ALTER TABLE invoices ADD COLUMN paid_amount REAL DEFAULT 0.0',
        );
        print('✅ Added paid_amount column');
      }

      print('✅ Database schema updated successfully!');
    }

    // Verify the fix
    try {
      final result = await db.customSelect('''
        SELECT 
            COUNT(*) as invoice_count,
            SUM(total_amount) as total_sales
        FROM invoices 
        WHERE status != 'deleted'
        LIMIT 1
        ''').get();

      final count = result.first.data['invoice_count'];
      final sales = result.first.data['total_sales'];

      print('✅ Database verification successful!');
      print('   - Total invoices: $count');
      print('   - Total sales: $sales');
    } catch (e) {
      print('❌ Verification failed: $e');
    }

    await db.close();
    print('🎉 Database fix completed!');
  } catch (e) {
    print('❌ Database fix failed: $e');
  }
}
