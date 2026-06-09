import 'dart:developer' as developer;
import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Utility class to add sample expense data for testing
class SampleExpensesData {
  static Future<void> addSampleExpenses(WidgetRef ref) async {
    try {
      final database = ref.read(appDatabaseProvider);

      final sampleExpenses = [
        ExpensesCompanion.insert(
          id: '',
          description: 'إيجار المحل',
          amount: 5000.0,
          category: 'مصروفات ثابتة',
          paymentMethod: Value('cash'),
          date: Value(DateTime.now().subtract(const Duration(days: 5))),
          notes: Value('إيجار شهر يناير 2026'),
        ),
        ExpensesCompanion.insert(
          id: '',
          description: 'فاتورة الكهرباء',
          amount: 850.0,
          category: 'فواتير',
          paymentMethod: Value('bank'),
          date: Value(DateTime.now().subtract(const Duration(days: 10))),
          notes: Value('فاتورة شهر ديسمبر'),
          receiptNumber: Value('ELC-2025-001'),
        ),
        ExpensesCompanion.insert(
          id: '',
          description: 'صيانة الحاسوب',
          amount: 250.0,
          category: 'صيانة',
          paymentMethod: Value('cash'),
          date: Value(DateTime.now().subtract(const Duration(days: 15))),
          notes: Value('تغيير قطع غيار'),
        ),
        ExpensesCompanion.insert(
          id: '',
          description: 'ورق وأقلام',
          amount: 120.0,
          category: 'مواد مكتبية',
          paymentMethod: Value('cash'),
          date: Value(DateTime.now().subtract(const Duration(days: 20))),
        ),
        ExpensesCompanion.insert(
          id: '',
          description: 'توصيل بضائع',
          amount: 75.0,
          category: 'نقل',
          paymentMethod: Value('cash'),
          date: Value(DateTime.now().subtract(const Duration(days: 25))),
          notes: Value('توصيل طلبية للعميل'),
        ),
        ExpensesCompanion.insert(
          id: '',
          description: 'غداء للموظفين',
          amount: 180.0,
          category: 'وجبات',
          paymentMethod: Value('cash'),
          date: Value(DateTime.now().subtract(const Duration(days: 2))),
          notes: Value('اجتماع العمل'),
        ),
        ExpensesCompanion.insert(
          id: '',
          description: 'اشتراك انترنت',
          amount: 300.0,
          category: 'مصروفات ثابتة',
          paymentMethod: Value('card'),
          date: Value(DateTime.now().subtract(const Duration(days: 30))),
          notes: Value('اشتراك سنوي'),
          receiptNumber: Value('NET-2025-001'),
        ),
        ExpensesCompanion.insert(
          id: '',
          description: 'شراء كرسي مكتب',
          amount: 450.0,
          category: 'أخرى',
          paymentMethod: Value('cash'),
          date: Value(DateTime.now().subtract(const Duration(days: 8))),
          notes: Value('كرسي جديد للمكتب'),
        ),
      ];

      for (final expense in sampleExpenses) {
        try {
          await database.expenseDao.insertExpense(expense);
          developer.log('Added expense: ${expense.description}');
        } catch (e) {
          // Ignore duplicate entries
          if (!e.toString().contains('UNIQUE constraint failed')) {
            developer.log('Error adding expense: $e');
          }
        }
      }

      developer.log('Sample expenses data added successfully!');
    } catch (e) {
      developer.log('Error adding sample expenses: $e');
    }
  }

  static Future<void> clearAllExpenses(WidgetRef ref) async {
    try {
      final database = ref.read(appDatabaseProvider);
      final expenses = await database.expenseDao.getAllExpenses();

      for (final expense in expenses) {
        await database.expenseDao.deleteExpense(expense.id);
      }

      developer.log('All expenses cleared successfully!');
    } catch (e) {
      developer.log('Error clearing expenses: $e');
    }
  }
}
