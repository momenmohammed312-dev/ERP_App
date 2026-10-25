import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/purchase_print_service_simple.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/ui/purchase/widgets/purchase_detail_dialog.dart';
import 'package:pos_offline_desktop/ui/purchase/widgets/void_purchase_dialog.dart';
import 'package:pos_offline_desktop/ui/widgets/permission_guarded_action.dart';

/// Purchase invoices list — mirrors `SalesReportTab` card for card:
/// search, date range, grand total, Excel/PDF/thermal export, per-invoice
/// print, tap for full detail (عرض/تعديل/استرجاع).
class PurchasesReportTab extends StatelessWidget {
  final AppDatabase db;

  const PurchasesReportTab({super.key, required this.db});

  @override
  Widget build(BuildContext context) => _PurchasesReportTab(db: db);
}

class _PurchasesReportTab extends ConsumerStatefulWidget {
  final AppDatabase db;

  const _PurchasesReportTab({required this.db});

  @override
  ConsumerState<_PurchasesReportTab> createState() => _PurchasesReportTabState();
}

class _PurchasesReportTabState extends ConsumerState<_PurchasesReportTab> {
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

  /// إلغاء فاتورة المشتريات — نفس الـdialog، والخدمة هي اللي بتعمل العكس
  /// الكامل جوه transaction واحدة (مخزون + سطور + قيود المورد).
  Future<void> _voidPurchase(Purchase p) async {
    if (p.isDeleted) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => VoidPurchaseDialog(
        db: widget.db,
        purchaseId: p.id,
        voidedBy: ref.read<User?>(authProvider)?.username ?? 'unknown',
        onDone: _loadData,
      ),
    );
    if (done == true && mounted) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = _filteredPurchases.fold<double>(
      0.0,
      (sum, p) => sum + p.totalAmount,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'تقارير المشتريات',
          style: TextStyle(
            fontFamily: 'NotoSansArabic',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Controls & Filter Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.15),
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'البحث عن فاتورة (رقم، مورد، مبلغ)',
                        hintStyle: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectDateRange(context),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.15),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.date_range_rounded,
                                  size: 18,
                                  color: MadarColors.gold,
                                ),
                                const Gap(8),
                                Text(
                                  '${DateFormat('yyyy/MM/dd').format(_startDate)} - ${DateFormat('yyyy/MM/dd').format(_endDate)}',
                                  style: const TextStyle(
                                    fontFamily: 'NotoSansArabic',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Gap(10),
                      OutlinedButton.icon(
                        onPressed: _exportPDF,
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 17,
                        ),
                        label: Text(context.l10n.pdf_label),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const Gap(8),
                      OutlinedButton.icon(
                        onPressed: _printThermalSummary,
                        icon: const Icon(Icons.print_outlined, size: 17),
                        label: const Text('طباعة حرارية'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const Gap(8),
                      FilledButton.tonalIcon(
                        onPressed: _exportExcel,
                        icon: const Icon(Icons.table_chart_rounded, size: 17),
                        label: Text(context.l10n.excel_label),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(14),

            // Grand Total KPI Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF388BFD).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF388BFD).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF388BFD).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_rounded,
                      color: Color(0xFF388BFD),
                      size: 20,
                    ),
                  ),
                  const Gap(12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'إجمالي المشتريات',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'عدد الفواتير: ${_filteredPurchases.length}',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${grandTotal.toStringAsFixed(2)} جنيه',
                    style: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      color: Color(0xFF388BFD),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(14),

            // Purchases List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredPurchases.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.inventory_2_outlined,
                                size: 56,
                                color: Colors.grey,
                              ),
                              const Gap(12),
                              Text(
                                'لا توجد فواتير مشتريات في الفترة المحددة',
                                style: TextStyle(
                                  fontFamily: 'NotoSansArabic',
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredPurchases.length,
                          itemBuilder: (context, index) {
                            final p = _filteredPurchases[index];
                            final remaining = p.totalAmount - p.paidAmount;
                            final isPaid = remaining <= 0.001;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withValues(alpha: 0.15),
                                ),
                              ),
                              child: InkWell(
                                onTap: () => _openDetail(p),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Colors.purple
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: Text(
                                            (displayInvoiceNumber(
                                                  p.invoiceNumber,
                                                  null,
                                                ) ??
                                                '#')[0],
                                            style: const TextStyle(
                                              fontFamily: 'NotoSansArabic',
                                              color: Colors.purple,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
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
                                                fontFamily: 'NotoSansArabic',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const Gap(2),
                                            Text(
                                              _supplierNames[p.supplierId] ??
                                                  'مورد غير محدد',
                                              style: TextStyle(
                                                fontFamily: 'NotoSansArabic',
                                                fontSize: 12.5,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.7),
                                              ),
                                            ),
                                            Text(
                                              DateFormat(
                                                'yyyy-MM-dd HH:mm',
                                              ).format(
                                                p.purchaseDate.toLocal(),
                                              ),
                                              style: TextStyle(
                                                fontFamily: 'NotoSansArabic',
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.45),
                                                fontSize: 11,
                                              ),
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
                                              fontFamily: 'NotoSansArabic',
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const Gap(2),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: (isPaid
                                                      ? const Color(0xFF238636)
                                                      : const Color(0xFFD29922))
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isPaid
                                                  ? 'مدفوع'
                                                  : 'متبقي ${remaining.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontFamily: 'NotoSansArabic',
                                                color: isPaid
                                                    ? const Color(0xFF238636)
                                                    : const Color(0xFFD29922),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Gap(8),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.print_outlined,
                                          size: 18,
                                        ),
                                        onPressed: () => _printOne(p),
                                        tooltip: 'طباعة الفاتورة',
                                      ),
                                      if (!p.isDeleted)
                                        PermissionGuardedIconButton(
                                          icon: Icons.delete_outline_rounded,
                                          color: const Color(0xFFF85149),
                                          tooltip: 'إلغاء الفاتورة',
                                          onPressed: () => _voidPurchase(p),
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
