import 'package:drift/drift.dart';
import '../database/app_database.dart';

class CustodyService {
  final AppDatabase db;

  CustodyService(this.db);

  /// توليد رقم العهدة بالتنسيق الموحد CUST-000001
  String formatCustodyNumber(int id) => 'CUST-${id.toString().padLeft(6, '0')}';

  /// إنشاء عهدة جديدة مع خصم المبلغ من حركة الخزينة (Ledger)
  Future<int> createCustody({
    required String staffId,
    required String staffName,
    required double amount,
    DateTime? date,
    String? description,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw Exception('يجب أن يكون مبلغ العهدة أكبر من صفر');
    }

    final custodyDate = date ?? DateTime.now();

    return db.transaction(() async {
      final nextId = await db.custodyDao.getNextCustodyId();
      final custodyNumber = formatCustodyNumber(nextId);

      final companion = CashCustodiesCompanion.insert(
        custodyNumber: custodyNumber,
        staffId: staffId,
        staffName: staffName,
        date: custodyDate,
        amount: amount,
        description: Value(description),
        totalExpenses: const Value(0.0),
        remainingAmount: amount,
        status: const Value('open'),
        notes: Value(notes),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      );

      final id = await db.custodyDao.insertCustody(companion);

      // تسجيل حركة قيد في دفتر الأستاذ (خروج نقدية كعهدة)
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_custody_$id',
          entityType: 'Custody',
          refId: id.toString(),
          date: custodyDate,
          description: 'صرف عهدة نقدية: $custodyNumber للمسؤول $staffName',
          debit: Value(amount),
          credit: const Value(0.0),
          origin: 'custody',
          paymentMethod: const Value('cash'),
        ),
      );

      return id;
    });
  }

  /// إضافة مصروف على العهدة
  Future<int> addExpense({
    required int custodyId,
    required String description,
    required double amount,
    DateTime? date,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw Exception('قيمة المصروف يجب أن تكون أكبر من صفر');
    }
    if (description.trim().isEmpty) {
      throw Exception('يجب إدخال بيان المصروف');
    }

    return db.transaction(() async {
      final custody = await db.custodyDao.getCustodyById(custodyId);
      if (custody == null) {
        throw Exception('العهدة غير موجودة');
      }
      if (custody.status != 'open') {
        throw Exception('لا يمكن إضافة مصروف لعهدة مغلقة أو ملغاة');
      }

      final newTotal = custody.totalExpenses + amount;
      if (newTotal > custody.amount) {
        throw Exception(
          'المصروف يتجاوز المتبقي من العهدة! المتبقي المتاح: ${custody.remainingAmount} ج.م',
        );
      }

      final expenseId = await db.custodyDao.insertExpense(
        CustodyExpensesCompanion.insert(
          custodyId: custodyId,
          description: description.trim(),
          amount: amount,
          date: Value(date ?? DateTime.now()),
          notes: Value(notes),
          createdAt: Value(DateTime.now()),
        ),
      );

      // تحديث إجمالي المصروفات والمتبقي
      final remaining = custody.amount - newTotal;
      await db.custodyDao.updateCustody(
        custodyId,
        CashCustodiesCompanion(
          totalExpenses: Value(newTotal),
          remainingAmount: Value(remaining),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return expenseId;
    });
  }

  /// حذف مصروف من العهدة وإعادة حساب الرصيد
  Future<void> deleteExpense(int expenseId) async {
    return db.transaction(() async {
      final expense = await db.custodyDao.getExpenseById(expenseId);
      if (expense == null) return;

      final custody = await db.custodyDao.getCustodyById(expense.custodyId);
      if (custody == null || custody.status != 'open') {
        throw Exception('لا يمكن حذف مصروف من عهدة مغلقة أو ملغاة');
      }

      await db.custodyDao.deleteExpense(expenseId);

      // إعادة حساب إجمالي المصروفات من السجلات الفعلية
      final total = await db.custodyDao.calculateTotalExpenses(custody.id);
      final remaining = custody.amount - total;

      await db.custodyDao.updateCustody(
        custody.id,
        CashCustodiesCompanion(
          totalExpenses: Value(total),
          remainingAmount: Value(remaining),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// تسوية وإغلاق العهدة ورد المتبقي إلى الصندوق
  Future<void> settleCustody({
    required int custodyId,
    String? settledBy,
  }) async {
    return db.transaction(() async {
      final custody = await db.custodyDao.getCustodyById(custodyId);
      if (custody == null) throw Exception('العهدة غير موجودة');
      if (custody.status != 'open') {
        throw Exception('العهدة مغلقة أو ملغاة بالفعل');
      }

      final remaining = custody.remainingAmount;

      // تحديث حالة العهدة
      await db.custodyDao.updateCustody(
        custodyId,
        CashCustodiesCompanion(
          status: const Value('settled'),
          settledAt: Value(DateTime.now()),
          settledBy: Value(settledBy),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // في حال وجود متبقي نقدي، يتم إثبات استرداده في دفتر الأستاذ لحساب الصندوق
      if (remaining > 0) {
        await db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${DateTime.now().millisecondsSinceEpoch}_custody_settle_$custodyId',
            entityType: 'Custody',
            refId: custodyId.toString(),
            date: DateTime.now(),
            description: 'تسوية عهدة: ${custody.custodyNumber} - رد المتبقي للصندوق',
            debit: const Value(0.0),
            credit: Value(remaining),
            origin: 'custody',
            paymentMethod: const Value('cash'),
          ),
        );
      }
    });
  }

  /// إلغاء العهدة (في حال لم يتم تسجيل أي مصروف عليها)
  Future<void> cancelCustody(int custodyId) async {
    return db.transaction(() async {
      final custody = await db.custodyDao.getCustodyById(custodyId);
      if (custody == null) throw Exception('العهدة غير موجودة');
      if (custody.status != 'open') {
        throw Exception('العهدة ليست بحالة مفتوحة');
      }
      if (custody.totalExpenses > 0) {
        throw Exception('لا يمكن إلغاء عهدة تم تسجيل مصروفات عليها، يمكنك تسويتها بدلاً من ذلك');
      }

      // إلغاء العهدة
      await db.custodyDao.updateCustody(
        custodyId,
        CashCustodiesCompanion(
          status: const Value('cancelled'),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // رد كامل المبلغ للصندوق في دفتر الأستاذ
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_custody_cancel_$custodyId',
          entityType: 'Custody',
          refId: custodyId.toString(),
          date: DateTime.now(),
          description: 'إلغاء عهدة نقدية: ${custody.custodyNumber} - استرداد المبلغ بالكامل',
          debit: const Value(0.0),
          credit: Value(custody.amount),
          origin: 'custody',
          paymentMethod: const Value('cash'),
        ),
      );
    });
  }
}
