import 'package:drift/drift.dart';
import 'dart:developer';

/// إصلاح تكرار الرصيد الافتتاحي للعملاء.
///
/// قبل هذا الإصلاح، كان الرصيد الافتتاحي للعميل بيتسجل في مكانين:
///   1. عمود `opening_balance` في جدول العملاء
///   2. `LedgerTransactions` بحرف `origin = 'opening'` و `entity_type = 'Customer'`
/// وكل حاجات حساب الرصيد (getCustomerBalance / getRunningBalance /
/// getAllCustomerBalances) بتحسب الاتنين مع بعض => الأرصدة كانت بتظهر ضعف القيمة.
///
/// الحل: الرصيد الافتتاحي بيتخزن في العمود بس (زي الموردين). هنا بنشيل
/// الـ ledger transactions المكررة دي مرة واحدة — idempotent، فآمن يتنفذ
/// عند كل فتح قاعدة بيانات.
class CustomerOpeningBalanceFix {
  static Future<void> fixDuplicateOpeningTransactions(
    DatabaseConnectionUser db,
  ) async {
    try {
      await db.customStatement(
        "DELETE FROM ledger_transactions "
        "WHERE entity_type = 'Customer' AND origin = 'opening'",
      );
      log('🔧 Cleaned up duplicate customer opening balance ledger transactions');
    } catch (e) {
      log('❌ Error fixing customer opening balance: $e');
    }
  }
}
