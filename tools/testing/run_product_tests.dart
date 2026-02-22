import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import '../../test/test_product_management.dart';

void main() async {
  print('=====================================');
  print('   PRODUCT MANAGEMENT TEST SUITE');
  print('=====================================\n');

  // Create in-memory database for testing
  final database = AppDatabase(DatabaseConnection(NativeDatabase.memory()));

  try {
    // Initialize database
    await database.customStatement('PRAGMA foreign_keys = ON');

    // Run product tests
    final tester = ProductTester(database);
    final results = await tester.runAllTests();

    // Display results
    print('\n${'=' * 50}');
    print('PRODUCT TEST RESULTS');
    print('=' * 50);
    print('Overall Status: ${results['overall']}');
    print('Tests Passed: ${results['passed']}/${results['total']}');
    print('Pass Rate: ${results['passRate']}');

    if (results['overall'] != 'PASS') {
      print('\n⚠️ FAILED TESTS:');
      results['results'].forEach((testName, result) {
        if (result['status'] != 'PASS') {
          print('  $testName: ${result['message']}');
        }
      });
    }

    print('\n✅ DETAILED RESULTS:');
    results['results'].forEach((testName, result) {
      print('  $testName: ${result['status']}');
    });
  } catch (e) {
    print('❌ Test execution failed: $e');
  } finally {
    // Clean up
    await database.close();
  }

  print('\n${'=' * 50}');
  print('TEST COMPLETED');
  print('=' * 50);
}
