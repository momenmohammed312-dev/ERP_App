import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';

class SalesReportService {
  final AppDatabase db;
  final ExportService exportService;

  SalesReportService({required this.db, required this.exportService});

  Future<SalesReportData> generateSalesReport({
    DateTime? startDate,
    DateTime? endDate,
    String? customerId,
  }) async {
    final invoices = await _getFilteredInvoices(startDate, endDate, customerId);
    final customers = await db.customerDao.getAllCustomers();

    // Calculate totals
    double totalSales = 0.0;
    double totalPaid = 0.0;
    double totalOutstanding = 0.0;
    int totalInvoices = 0;

    for (final invoice in invoices) {
      totalSales += invoice.totalAmount;
      totalPaid += invoice.paidAmount;
      totalOutstanding += (invoice.totalAmount - invoice.paidAmount);
      totalInvoices++;
    }

    // Group by customer for breakdown
    final customerBreakdown = <String, CustomerSalesData>{};

    for (final invoice in invoices) {
      final customerKey = invoice.customerId ?? 'unknown';
      final customerData = customerBreakdown.putIfAbsent(
        customerKey,
        () => CustomerSalesData(
          customerId: invoice.customerId ?? '',
          customerName: invoice.customerName ?? 'عميل غير محدد',
          customerContact: invoice.customerContact ?? '',
          customerAddress: invoice.customerAddress ?? '',
          totalSales: 0.0,
          totalPaid: 0.0,
          totalOutstanding: 0.0,
          invoiceCount: 0,
          invoices: [],
        ),
      );

      customerData.totalSales += invoice.totalAmount;
      customerData.totalPaid += invoice.paidAmount;
      customerData.totalOutstanding +=
          (invoice.totalAmount - invoice.paidAmount);
      customerData.invoiceCount++;
      customerData.invoices.add(invoice);
    }

    // Get customer balances
    final customerBalances = <String, double>{};
    for (final customer in customers) {
      final balance = await db.ledgerDao.getCustomerBalance(customer.id);
      customerBalances[customer.id] = balance;
    }

    return SalesReportData(
      startDate: startDate,
      endDate: endDate,
      totalSales: totalSales,
      totalPaid: totalPaid,
      totalOutstanding: totalOutstanding,
      totalInvoices: totalInvoices,
      customerBreakdown: customerBreakdown.values.toList(),
      customerBalances: customerBalances,
      allInvoices: invoices,
    );
  }

  Future<List<Invoice>> _getFilteredInvoices(
    DateTime? startDate,
    DateTime? endDate,
    String? customerId,
  ) async {
    var query = db.select(db.invoices);

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
      query = query..where((tbl) => tbl.date.isSmallerThan(Constant(endOfDay)));
    }

    if (customerId != null && customerId.isNotEmpty) {
      query = query..where((tbl) => tbl.customerId.equals(customerId));
    }

    return await query.get();
  }

  Future<void> exportSalesReportToPDF(SalesReportData reportData) async {
    // Fix for Issue G: Use InvoiceDao.getInvoicesWithDetails to fetch product names
    final invoicesWithProducts = await db.invoiceDao.getInvoicesWithDetails(
      reportData.startDate ?? DateTime(2020),
      reportData.endDate ?? DateTime.now(),
    );

    // Use the enhanced export service that supports InvoiceReportDTO
    await exportService.exportSalesReport(
      title:
          'تقرير مبيعات مفصل${_getDateRangeText(reportData.startDate, reportData.endDate)}',
      data: invoicesWithProducts,
      fileName:
          'sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
    );
  }

  Future<void> exportSalesReportToExcel(SalesReportData reportData) async {
    // Fix for Issue G: Use InvoiceDao.getInvoicesWithDetails with product names
    final invoicesWithProducts = await db.invoiceDao.getInvoicesWithDetails(
      reportData.startDate ?? DateTime(2020),
      reportData.endDate ?? DateTime.now(),
    );

    // Convert InvoiceReportDTO to Map for Excel export
    final data = invoicesWithProducts.map((invoice) {
      return {
        'رقم الفاتورة': invoice.invoiceNumber,
        'التاريخ': invoice.date,
        'العميل': invoice.customerName,
        'المنتجات': invoice.productNames,
        'الإجمالي': invoice.totalAmount,
        'المدفوع': invoice.paidAmount,
        'المتبقي': invoice.remainingAmount,
        'الحالة': invoice.status,
      };
    }).toList();

    await exportService.exportToExcel(
      title:
          'تقرير مبيعات مفصل${_getDateRangeText(reportData.startDate, reportData.endDate)}',
      data: data,
      headers: [
        'رقم الفاتورة',
        'التاريخ',
        'العميل',
        'المنتجات',
        'الإجمالي',
        'المدفوع',
        'المتبقي',
        'الحالة',
      ],
      columns: [
        'رقم الفاتورة',
        'التاريخ',
        'العميل',
        'المنتجات',
        'الإجمالي',
        'المدفوع',
        'المتبقي',
        'الحالة',
      ],
      fileName:
          'sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
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
}

class SalesReportData {
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalSales;
  final double totalPaid;
  final double totalOutstanding;
  final int totalInvoices;
  final List<CustomerSalesData> customerBreakdown;
  final Map<String, double> customerBalances;
  final List<Invoice> allInvoices;

  SalesReportData({
    required this.startDate,
    required this.endDate,
    required this.totalSales,
    required this.totalPaid,
    required this.totalOutstanding,
    required this.totalInvoices,
    required this.customerBreakdown,
    required this.customerBalances,
    required this.allInvoices,
  });
}

class CustomerSalesData {
  String customerId;
  String customerName;
  String customerContact;
  String customerAddress;
  double totalSales;
  double totalPaid;
  double totalOutstanding;
  int invoiceCount;
  List<Invoice> invoices;

  CustomerSalesData({
    required this.customerId,
    required this.customerName,
    required this.customerContact,
    required this.customerAddress,
    required this.totalSales,
    required this.totalPaid,
    required this.totalOutstanding,
    required this.invoiceCount,
    required this.invoices,
  });
}
