import 'dart:io';
import 'package:path/path.dart';

/// Simple database fix script using direct SQLite commands
Future<void> main() async {
  print('🔧 Fixing database schema for Sales vs Purchases report...');

  try {
    // Find the database file
    final dbPath = findDatabaseFile();
    if (dbPath == null) {
      print('❌ Database file not found!');
      print('Please check if the app has been run at least once.');
      return;
    }

    print('Database path: $dbPath');

    // Check if database exists
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      print('❌ Database file not found!');
      return;
    }

    print('✅ Database file found');
    print('');
    print('📝 Manual fix instructions:');
    print('');
    print('To fix the "no such column: totalAmount" error, you need to:');
    print('1. Close the POS application completely');
    print(
      '2. Open the database file using a SQLite browser (like DB Browser for SQLite)',
    );
    print('3. Run these SQL commands:');
    print('');
    print('   ALTER TABLE invoices ADD COLUMN totalAmount REAL DEFAULT 0.0;');
    print('   ALTER TABLE invoices ADD COLUMN paidAmount REAL DEFAULT 0.0;');
    print('');
    print('4. Save the database and restart the POS application');
    print('');
    print(
      'Or alternatively, delete the database file and let the app recreate it:',
    );
    print('   - Delete: $dbPath');
    print(
      '   - Restart the POS app (it will create a fresh database with correct schema)',
    );
    print('');

    // Try to check if columns exist by reading the database file
    final fileSize = await dbFile.length();
    print('Database file size: $fileSize bytes');

    if (fileSize > 0) {
      print('✅ Database appears to have data');
      print(
        '⚠️  Recommended: Use SQLite browser to add missing columns to preserve existing data',
      );
    } else {
      print('⚠️  Database is empty - safe to delete and recreate');
    }
  } catch (e) {
    print('❌ Error: $e');
  }
}

String? findDatabaseFile() {
  // Common database locations
  final possiblePaths = [
    join(
      '..',
      '..',
      'AppData',
      'Local',
      'pos_offline_desktop_database',
      'pos_offline_desktop_database.sqlite',
    ),
    join(
      '..',
      '..',
      'AppData',
      'Roaming',
      'pos_offline_desktop_database',
      'pos_offline_desktop_database.sqlite',
    ),
    join('pos_offline_desktop_database', 'pos_offline_desktop_database.sqlite'),
    join('data', 'pos_offline_desktop_database.sqlite'),
  ];

  for (final path in possiblePaths) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }

  return null;
}
