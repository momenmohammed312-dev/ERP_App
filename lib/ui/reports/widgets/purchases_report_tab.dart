import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/purchase_print_service_simple.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/ui/purchase/widgets/purchase_detail_dialog.dart';

/// Purchase invoices list — mirrors `SalesReportTab` card for card:
/// search, date range, grand total, Excel/PDF/thermal export, per-invoice
/// print, tap for full detail (عرض/تعديل/استرجاع).
class PurchasesReportTab extends StatefulWidget {
  final AppDatabase db;

  const PurchasesReportTab({super.key, required this.db});

  @override
  State<PurchasesReportTab> createState() => _PurchasesReportTabState();
}

class _PurchasesReportTabState extends State<PurchasesReportTab> {
  DateTime _startDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    23,
    59,
    59,
  );
  List<Purchase> _purchases = [];
  List<Purchase> _filteredPurchases = [];
  Map<String, String> _supplierNames = {};
  bool _isLoading = false;
  final _exportService = ExportService();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterPurchases);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterPurchases() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredPurchases = List.from(_purchases);
      } else {
        _filteredPurchases = _purchases.where((p) {
          final number = (p.invoiceNumber).toLowerCase();
          final supplier = (_supplierNames[p.supplierId] ?? '').toLowerCase();
          final total = p.totalAmount.toString();
          return number.contains(query) ||
              supplier.contains(query) ||
              total.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final purchases = await widget.db.purchaseDao.getPurchasesByDateRange(
        _startDate,
        _endDate,
      );
      final names = <String, String>{};
      for (final p in purchases) {
        if (p.supplierId != null && !names.containsKey(p.supplierId)) {
          final s =
              await widget.db.supplierDao.getSupplierById(p.supplierId!);
          names[p.supplierId!] = s?.name ?? 'مورد غير محدد';
        }
      }
      setState(() {
        _purchases = purchases;
        _filteredPurchases = List.from(purchases);
        _supplierNames = names;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل المشتريات: $e')),
        );
      }
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  Future<void> _exportExcel() async {
    try {
      final data = [
        for (final p in _purchases)
          {
            'رقم الفاتورة':
                displayInvoiceNumber(p.invoiceNumber, null) ?? '',
            'المورد': _supplierNames[p.supplierId] ?? 'مورد غير محدد',
            'المبلغ الإجمالي': p.totalAmount,
            'المدفوع': p.paidAmount,
            'التاريخ':
                DateFormat('yyyy-MM-dd HH:mm').format(p.purchaseDate.toLocal()),
            'الحالة': p.status,
          },
      ];
      await _exportService.exportToExcel(
        title: 'تقارير المشتريات',
        headers: [
          'رقم الفاتورة',
          'المورد',
          'المبلغ الإجمالي',
          'المدفوع',
          'التاريخ',
          'الحالة',
        ],
        columns: [
          'رقم الفاتورة',
          'المورد',
          'المبلغ الإجمالي',
          'المدفوع',
          'التاريخ',
          'الحالة',
        ],
        data: data,
        fileName:
            'purchase_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e')),
        );
      }
    }
  }

  Future<void> _exportPDF() async {
    try {
      final data = [
        for (final p in _purchases)
          {
            'invoiceNumber':
                displayInvoiceNumber(p.invoiceNumber, null) ?? '',
            'supplierName': _supplierNames[p.supplierId] ?? 'مورد غير محدد',
            'totalAmount': p.totalAmount,
            'paidAmount': p.paidAmount,
            'date': DateFormat(
              'yyyy-MM-dd HH:mm',
            ).format(p.purchaseDate.toLocal()),
            'status': p.status,
          },
      ];
      await _exportService.exportToPDF(
        title: 'تقارير المشتريات',
        headers: [
          'رقم الفاتورة',
          'المورد',
          'المبلغ الإجمالي',
          'المدفوع',
          'التاريخ',
          'الحالة',
        ],
        columns: [
          'invoiceNumber',
          'supplierName',
          'totalAmount',
          'paidAmount',
          'date',
          'status',
        ],
        data: data,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e')),
        );
      }
    }
  }

  Future<void> _printThermalSummary() async {
    try {
      if (_purchases.isEmpty) return;
      final grandTotal = _purchases.fold<double>(
        0.0,
        (sum, p) => sum + p.totalAmount,
      );
      final storeInfo = ups.StoreInfo(
        storeName: 'المحل التجاري',
        phone: '01234567890',
        zipCode: '12345',
        state: 'القاهرة',
      );
      // Report pseudo-model (not an invoice): deterministic date-based tag,
      // never a timestamp sequence.
      final tag =
          'PUR-REPORT-${DateFormat('yyyyMMdd').format(DateTime.now())}';
      final data = ups.InvoiceData(
        invoice: ups.Invoice(
          id: 0,
          invoiceNumber: tag,
          customerName: 'تقارير المشتريات',
          customerPhone: '',
          customerZipCode: '',
          customerState: '',
          invoiceDate: DateTime.now(),
          subtotal: grandTotal,
          isCreditAccount: false,
          previousBalance: 0.0,
          totalAmount: grandTotal,
        ),
        items: [
          ups.InvoiceItem(
            id: 0,
            invoiceId: 0,
            description: 'ملخص تقرير المشتريات',
            unit: 'تقرير',
            quantity: 1,
            unitPrice: grandTotal,
            totalPrice: grandTotal,
          ),
        ],
        storeInfo: storeInfo,
      );
      await ups.UnifiedPrintService.printToThermalPrinter(
        documentType: ups.DocumentType.salesInvoice,
        data: data,
      );
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  Future<void> _printOne(Purchase p) async {
    try {
      await PurchasePrintService(widget.db).printTextPurchase(
        db: widget.db,
        purchaseId: p.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الطباعة')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الطباعة: $e')),
        );
      }
    }
  }

  Future<void> _openDetail(Purchase p) async {
    await showDialog(
      context: context,
      builder: (_) => PurchaseDetailDialog(
        db: widget.db,
        purchaseId: p.id,
        onChanged: _loadData,
      ),
    );
    if (mounted) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = _filteredPurchases.fold<double>(
      0.0,
      (sum, p) => sum + p.totalAmount,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('تقارير المشتريات'),
        backgroundColor: const Color(0xFF1E1E2C),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              color: const Color(0xFF1E1E2C),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'البحث عن فاتورة (رقم، مورد، مبلغ)',
                        hintStyle: TextStyle(color: Colors.white54),
                        prefixIcon:
                            Icon(Icons.search, color: Colors.white54),
                        filled: true,
                        fillColor: Color(0xFF252535),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const Gap(16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDateRange(context),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade600),
                                borderRadius: BorderRadius.circular(8),
                                color: const Color(0xFF252535),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.date_range,
                                    color: Colors.orange,
                                  ),
                                  const Gap(8),
                                  Text(
                                    '${DateFormat('yyyy/MM/dd').format(_startDate)} - ${DateFormat('yyyy/MM/dd').format(_endDate)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Gap(8),
                        ElevatedButton.icon(
                          onPressed: _exportPDF,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: Text(context.l10n.pdf_label),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const Gap(8),
                        ElevatedButton.icon(
                          onPressed: _printThermalSummary,
                          icon: const Icon(Icons.print),
                          label: const Text('طباعة حرارية'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const Gap(8),
                        ElevatedButton.icon(
                          onPressed: _exportExcel,
                          icon: const Icon(Icons.table_chart),
                          label: Text(context.l10n.excel_label),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: const Color(0xFF1E1E2C),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الإجمالي الكلي',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${grandTotal.toStringAsFixed(2)} جنيه',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredPurchases.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد بيانات',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredPurchases.length,
                          itemBuilder: (context, index) {
                            final p = _filteredPurchases[index];
                            final remaining =
                                p.totalAmount - p.paidAmount;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              color: const Color(0xFF1E1E2C),
                              child: InkWell(
                                onTap: () => _openDetail(p),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.orange
                                            .withValues(alpha: 0.1),
                                        child: Text(
                                          (displayInvoiceNumber(
                                                        p.invoiceNumber,
                                                        null,
                                                      ) ??
                                                  '#')[0],
                                          style: const TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const Gap(12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              displayInvoiceNumber(
                                                    p.invoiceNumber,
                                                    null,
                                                  ) ??
                                                  '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _supplierNames[p.supplierId] ??
                                                  'مورد غير محدد',
                                              style: const TextStyle(
                                                  color: Colors.white70),
                                            ),
                                            Text(
                                              DateFormat('yyyy-MM-dd HH:mm')
                                                  .format(p.purchaseDate
                                                      .toLocal()),
                                              style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${p.totalAmount.toStringAsFixed(2)} ج.م',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.greenAccent,
                                            ),
                                          ),
                                          Text(
                                            remaining > 0
                                                ? 'متبقي ${remaining.toStringAsFixed(2)}'
                                                : 'مدفوع',
                                            style: TextStyle(
                                              color: remaining > 0
                                                  ? Colors.orange
                                                  : Colors.green,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.print,
                                          size: 20,
                                          color: Colors.orange,
                                        ),
                                        onPressed: () => _printOne(p),
                                        tooltip: 'طباعة الفاتورة',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
