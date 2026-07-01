import 'package:intl/intl.dart';
import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/sales_report_service.dart';

class SupplierExpenseService {
  final AppDatabase db;
  final ExportService exportService;

  SupplierExpenseService({required this.db, required this.exportService});

  Future<SupplierExpenseReportData> generateSupplierExpenseReport({
    DateTime? startDate,
    DateTime? endDate,
    String? supplierId,
  }) async {
    final expenses = await _getFilteredExpenses(startDate, endDate, supplierId);
    final suppliers = await db.supplierDao.getAllSuppliers();

    // Calculate totals
    double totalExpenses = 0.0;

    for (final expense in expenses) {
      totalExpenses += expense.amount;
    }

    // Group by supplier for breakdown
    final supplierBreakdown = <String, SupplierExpenseData>{};

    for (final expense in expenses) {
      final supplierKey = expense.supplierId ?? 'general';

      // Only include existing suppliers, don't create new ones
      Supplier? supplier;
      if (expense.supplierId != null && expense.supplierId!.isNotEmpty) {
        try {
          supplier = suppliers.firstWhere((s) => s.id == expense.supplierId);
        } catch (e) {
          // Supplier not found, skip this expense
          continue;
        }
      } else {
        // Create a placeholder for general expenses (not saved to DB)
        supplier = Supplier(
          id: 'general',
          name: 'عام',
          phone: '',
          address: '',
          openingBalance: 0.0,
          status: 'Active',
          createdAt: DateTime.now(),
        );
      }

      supplierBreakdown.putIfAbsent(
        supplierKey,
        () => SupplierExpenseData(
          supplierId: supplier!.id,
          supplierName: supplier.name,
          supplierContact: supplier.phone ?? '',
          supplierAddress: supplier.address ?? '',
          totalExpenses: 0.0,
          expenseCount: 0,
          expenses: [],
        ),
      );

      // Update values in map
      final existingData =
          supplierBreakdown[supplierKey] ??
          SupplierExpenseData(
            supplierId: supplier.id,
            supplierName: supplier.name,
            supplierContact: supplier.phone ?? '',
            supplierAddress: supplier.address ?? '',
            totalExpenses: 0.0,
            expenseCount: 0,
            expenses: [],
          );

      supplierBreakdown[supplierKey] = SupplierExpenseData(
        supplierId: existingData.supplierId,
        supplierName: existingData.supplierName,
        supplierContact: existingData.supplierContact,
        supplierAddress: existingData.supplierAddress,
        totalExpenses: existingData.totalExpenses + expense.amount,
        expenseCount: existingData.expenseCount + 1,
        expenses: [...existingData.expenses, expense],
      );
    }

    // Get supplier balances from ledger
    final supplierBalances = <String, double>{};
    for (final supplier in suppliers) {
      final transactions =
          await (db.select(db.ledgerTransactions)
                ..where((tbl) => tbl.refId.equals(supplier.id))
                ..where((tbl) => tbl.entityType.equals('Supplier')))
              .get();

      final balance = transactions.fold<double>(0.0, (sum, transaction) {
        return sum + transaction.credit - transaction.debit;
      });

      supplierBalances[supplier.id] = balance;
    }

    return SupplierExpenseReportData(
      startDate: startDate,
      endDate: endDate,
      totalExpenses: totalExpenses,
      totalExpensesCount: expenses.length,
      supplierBreakdown: supplierBreakdown.values.toList(),
      supplierBalances: supplierBalances,
      allExpenses: expenses,
    );
  }

  Future<List<Expense>> _getFilteredExpenses(
    DateTime? startDate,
    DateTime? endDate,
    String? supplierId,
  ) async {
    var query = db.select(db.expenses);

    if (startDate != null) {
      query = query..where((tbl) => tbl.date.isBiggerOrEqualValue(startDate));
    }

    if (endDate != null) {
      final endOfDay = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      );
      query = query..where((tbl) => tbl.date.isSmallerOrEqualValue(endOfDay));
    }

    if (supplierId != null && supplierId.isNotEmpty) {
      query = query..where((tbl) => tbl.supplierId.equals(supplierId));
    }

    return await query.get();
  }

  Future<void> exportSupplierExpenseReportToPDF(
    SupplierExpenseReportData reportData,
  ) async {
    final data = <Map<String, dynamic>>[];

    // Summary section
    data.add({
      'النوع': 'ملخص التقرير',
      'الوصف': 'إجمالي المصروفات',
      'القيمة': _formatCurrency(reportData.totalExpenses),
    });
    data.add({
      'النوع': 'ملخص التقرير',
      'الوصف': 'عدد المصروفات',
      'القيمة': reportData.totalExpensesCount.toString(),
    });

    // Supplier breakdown
    for (final supplier in reportData.supplierBreakdown) {
      final balance = reportData.supplierBalances[supplier.supplierId] ?? 0.0;
      data.add({
        'النوع': 'تفصيل المورد',
        'المورد': supplier.supplierName,
        'الإجمالي': _formatCurrency(supplier.totalExpenses),
        'الرصيد': _formatCurrency(balance),
        'عدد المصروفات': supplier.expenseCount.toString(),
      });
    }

    await exportService.exportToPDF(
      title:
          'تقرير مصروفات الموردين${_getDateRangeText(reportData.startDate, reportData.endDate)}',
      data: data,
      headers: [
        'النوع',
        'المورد',
        'الوصف',
        'القيمة',
        'الإجمالي',
        'الرصيد',
        'عدد المصروفات',
      ],
      columns: [
        'النوع',
        'المورد',
        'الوصف',
        'القيمة',
        'الإجمالي',
        'الرصيد',
        'عدد المصروفات',
      ],
      fileName:
          'supplier_expense_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
    );
  }

  Future<void> exportSupplierExpenseReportToExcel(
    SupplierExpenseReportData reportData,
  ) async {
    final data = <Map<String, dynamic>>[];

    // Summary section
    data.add({
      'القسم': 'ملخص التقرير',
      'الوصف': 'إجمالي المصروفات',
      'القيمة': reportData.totalExpenses,
    });
    data.add({
      'القسم': 'ملخص التقرير',
      'الوصف': 'عدد المصروفات',
      'القيمة': reportData.totalExpensesCount,
    });

    // Supplier breakdown
    for (final supplier in reportData.supplierBreakdown) {
      final balance = reportData.supplierBalances[supplier.supplierId] ?? 0.0;
      data.add({
        'القسم': 'تفصيل المورد',
        'اسم المورد': supplier.supplierName,
        'هاتف المورد': supplier.supplierContact,
        'عنوان المورد': supplier.supplierAddress,
        'إجمالي المصروفات': supplier.totalExpenses,
        'الرصيد الحالي': balance,
        'عدد المصروفات': supplier.expenseCount,
      });
    }

    await exportService.exportToExcel(
      title:
          'تقرير مصروفات الموردين${_getDateRangeText(reportData.startDate, reportData.endDate)}',
      data: data,
      headers: [
        'القسم',
        'اسم المورد',
        'هاتف المورد',
        'عنوان المورد',
        'إجمالي المصروفات',
        'الرصيد الحالي',
        'عدد المصروفات',
      ],
      columns: [
        'القسم',
        'اسم المورد',
        'هاتف المورد',
        'عنوان المورد',
        'إجمالي المصروفات',
        'الرصيد الحالي',
        'عدد المصروفات',
      ],
      fileName:
          'supplier_expense_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
    );
  }

  Future<ComprehensiveReportData> generateComprehensiveReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final salesReportService = SalesReportService(
      db: db,
      exportService: exportService,
    );
    final salesReport = await salesReportService.generateSalesReport(
      startDate: startDate,
      endDate: endDate,
    );
    final expenseReport = await generateSupplierExpenseReport(
      startDate: startDate,
      endDate: endDate,
    );

    // Get total purchases for the period
    final purchaseResult = await db.customSelect(
      '''
      SELECT COALESCE(SUM(total_amount), 0) as total_purchases
      FROM purchases
      WHERE purchase_date BETWEEN ? AND ? AND is_deleted = 0
      ''',
      variables: [
        Variable.withDateTime(startDate ?? DateTime.now().subtract(const Duration(days: 30))),
        Variable.withDateTime(endDate ?? DateTime.now()),
      ],
    ).get();
    final totalPurchases = (purchaseResult.first.data['total_purchases'] as double?) ?? 0.0;

    // Calculate total outstanding payables from supplier balances
    final suppliers = await db.supplierDao.getAllSuppliers();
    double totalPayables = 0.0;
    for (final supplier in suppliers) {
      final transactions = await (db.select(db.ledgerTransactions)
        ..where((tbl) => tbl.refId.equals(supplier.id))
        ..where((tbl) => tbl.entityType.equals('Supplier'))).get();
      final balance = transactions.fold<double>(0.0, (sum, t) => sum + t.credit - t.debit);
      if (balance > 0) totalPayables += balance;
    }

    return ComprehensiveReportData(
      startDate: startDate ?? DateTime.now(),
      endDate: endDate ?? DateTime.now(),
      salesReport: salesReport,
      expenseReport: expenseReport,
      totalPurchases: totalPurchases,
      netProfit: salesReport.totalSales - totalPurchases - expenseReport.totalExpenses,
      totalOutstandingReceivables: salesReport.totalOutstanding,
      totalOutstandingPayables: totalPayables,
    );
  }

  Future<void> exportComprehensiveReportToPDF(
    ComprehensiveReportData reportData,
  ) async {
    final data = <Map<String, dynamic>>[];

    // Executive Summary
    data.add({
      'النوع': 'ملخص تنفيذي',
      'الوصف': 'إجمالي المبيعات',
      'القيمة': _formatCurrency(reportData.salesReport.totalSales),
    });
    data.add({
      'النوع': 'ملخص تنفيذي',
      'الوصف': 'إجمالي المصروفات',
      'القيمة': _formatCurrency(reportData.expenseReport.totalExpenses),
    });
    data.add({
      'النوع': 'ملخص تنفيذي',
      'الوصف': 'صافي الربح',
      'القيمة': _formatCurrency(reportData.netProfit),
    });
    data.add({
      'النوع': 'ملخص تنفيذي',
      'الوصف': 'الذمم المدينة',
      'القيمة': _formatCurrency(reportData.totalOutstandingReceivables),
    });
    data.add({
      'النوع': 'ملخص تنفيذي',
      'الوصف': 'الذمم الدائنة',
      'القيمة': _formatCurrency(reportData.totalOutstandingPayables),
    });

    await exportService.exportToPDF(
      title:
          'تقرير شامل${_getDateRangeText(reportData.startDate, reportData.endDate)}',
      data: data,
      headers: ['النوع', 'الوصف', 'القيمة'],
      columns: ['النوع', 'الوصف', 'القيمة'],
      fileName:
          'comprehensive_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
    );
  }

  String _getDateRangeText(DateTime? startDate, DateTime? endDate) {
    if (startDate == null && endDate == null) return '';
    if (startDate != null && endDate != null) {
      return ' (${DateFormat('yyyy/MM/dd').format(startDate)} - ${DateFormat('yyyy/MM/dd').format(endDate)})';
    }
    if (startDate != null) {
      return ' من ${DateFormat('yyyy/MM/dd').format(startDate)}';
    }
    return ' حتى ${DateFormat('yyyy/MM/dd').format(endDate!)}';
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      locale: 'en_EG',
      symbol: 'ج.م',
      decimalDigits: 2,
    ).format(amount);
  }
}

class SupplierExpenseReportData {
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalExpenses;
  final int totalExpensesCount;
  final List<SupplierExpenseData> supplierBreakdown;
  final Map<String, double> supplierBalances;
  final List<Expense> allExpenses;

  SupplierExpenseReportData({
    required this.startDate,
    required this.endDate,
    required this.totalExpenses,
    required this.totalExpensesCount,
    required this.supplierBreakdown,
    required this.supplierBalances,
    required this.allExpenses,
  });
}

class SupplierExpenseData {
  final String supplierId;
  final String supplierName;
  final String supplierContact;
  final String supplierAddress;
  final double totalExpenses;
  final int expenseCount;
  final List<Expense> expenses;

  SupplierExpenseData({
    required this.supplierId,
    required this.supplierName,
    required this.supplierContact,
    required this.supplierAddress,
    required this.totalExpenses,
    required this.expenseCount,
    required this.expenses,
  });
}

class ComprehensiveReportData {
  final DateTime? startDate;
  final DateTime? endDate;
  final SalesReportData salesReport;
  final SupplierExpenseReportData expenseReport;
  final double totalPurchases;
  final double netProfit;
  final double totalOutstandingReceivables;
  final double totalOutstandingPayables;

  ComprehensiveReportData({
    required this.startDate,
    required this.endDate,
    required this.salesReport,
    required this.expenseReport,
    this.totalPurchases = 0,
    required this.netProfit,
    required this.totalOutstandingReceivables,
    required this.totalOutstandingPayables,
  });
}
