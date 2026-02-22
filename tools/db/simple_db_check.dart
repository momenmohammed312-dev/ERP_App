import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show debugPrint;

void main() async {
  debugPrint('=== Simple Database Schema Check ===');

  // Get database path
  final dbPath = p.join(
    'g:\\development\\POS-Offline-Desktop-main',
    'pos_offline_desktop_database',
    'pos_offline_desktop_database.sqlite',
  );

  debugPrint('Database path: $dbPath');
  debugPrint('Database exists: ${await File(dbPath).exists()}');

  if (!await File(dbPath).exists()) {
    debugPrint('❌ Database file not found!');
    debugPrint('Trying alternative paths...');

    // Try common Windows paths
    final paths = [
      p.join(
        'C:\\Users',
        Platform.environment['USERNAME'] ?? '',
        'Documents',
        'pos_offline_desktop_database',
        'pos_offline_desktop_database.sqlite',
      ),
      p.join(
        'g:\\development\\POS-Offline-Desktop-main',
        'build',
        'pos_offline_desktop_database.sqlite',
      ),
    ];

    for (final path in paths) {
      debugPrint('Checking: $path');
      if (await File(path).exists()) {
        debugPrint('✅ Found database at: $path');
        await checkSchema(path);
        return;
      }
    }

    debugPrint('❌ No database file found in any location');
    return;
  }

  await checkSchema(dbPath);
}

Future<void> checkSchema(String dbPath) async {
  debugPrint('\n=== Checking Customers Table Schema ===');

  // Try to run sqlite3 command
  try {
    final result = await Process.run('sqlite3', [
      dbPath,
      'PRAGMA table_info(customers);',
    ]);

    if (result.exitCode == 0) {
      debugPrint('✅ Schema check successful:');
      debugPrint(result.stdout);

      // Parse and analyze the schema
      final lines = result.stdout.toString().split('\n');
      debugPrint('\n=== Schema Analysis ===');
      debugPrint('Column\t\t\tType\t\tExpected\tStatus');
      debugPrint('-' * 70);

      for (final line in lines) {
        if (line.trim().isEmpty || line.startsWith('cid')) continue;

        final parts = line.split('|');
        if (parts.length >= 3) {
          final columnName = parts[1].trim();
          final columnType = parts[2].trim();

          String expected = '';
          String status = '';

          switch (columnName) {
            case 'phone':
              expected = 'TEXT';
              status = columnType.contains('TEXT') ? '✅ OK' : '❌ MISMATCH';
              break;
            case 'opening_balance':
            case 'total_debt':
            case 'total_paid':
              expected = 'REAL';
              status = columnType.contains('REAL') ? '✅ OK' : '❌ MISMATCH';
              break;
            case 'is_active':
              expected = 'INTEGER';
              status = columnType.contains('INTEGER') ? '✅ OK' : '❌ MISMATCH';
              break;
            case 'status':
            case 'created_at':
            case 'updated_at':
              expected = 'TEXT';
              status = columnType.contains('TEXT') ? '✅ OK' : '❌ MISMATCH';
              break;
          }

          if (expected.isNotEmpty) {
            debugPrint('$columnName\t\t$columnType\t\t$expected\t\t$status');
          }
        }
      }
    } else {
      debugPrint('❌ Error running sqlite3: ${result.stderr}');
    }
  } catch (e) {
    debugPrint('❌ Exception: $e');
    debugPrint('Make sure sqlite3 is installed and accessible in PATH');
  }
}
