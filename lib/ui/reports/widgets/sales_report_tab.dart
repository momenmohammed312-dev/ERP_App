import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/core/services/document_date_service.dart';
import 'package:pos_offline_desktop/ui/widgets/document_date_picker.dart';
import 'package:pos_offline_desktop/ui/invoice/edit_invoice_page.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/invoice_partial_return_dialog.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/void_invoice_dialog.dart';
import 'package:pos_offline_desktop/ui/widgets/permission_guarded_action.dart';

class SalesReportTab extends StatelessWidget {
  final AppDatabase db;

  const SalesReportTab({super.key, required this.db});

  @override
  Widget build(BuildContext context) =>
      _SalesReportTab(db: db);
}

class _SalesReportTab extends ConsumerStatefulWidget {
  final AppDatabase db;

  const _SalesReportTab({required this.db});

  @override
  ConsumerState<_SalesReportTab> createState() => _SalesReportTabState();
}

class _SalesReportTabState extends ConsumerState<_SalesReportTab> {
  DateTime _startDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  ); // Start of today
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    23,
    59,
    59,
  ); // End of today
  List<Invoice> _invoices = [];
  List<Invoice> _filteredInvoices = [];
  Map<int, double> _returnsByInvoice = {};
  bool _isLoading = false;
  final _exportService = ExportService();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterInvoices);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterInvoices() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      if (query.isEmpty) {
        _filteredInvoices = List.from(_invoices);
      } else {
        _filteredInvoices = _invoices.where((invoice) {
          final invoiceNumber = (invoice.invoiceNumber ?? '').toLowerCase();
          final customerName = (invoice.customerName ?? '').toLowerCase();
          final totalAmount = invoice.totalAmount.toString();

          return invoiceNumber.contains(query) ||
              customerName.contains(query) ||
              totalAmount.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Fetch invoices with date range filtering
      final invoices = await widget.db.invoiceDao.getInvoicesByDateRange(
        _startDate,
        _endDate,
      );

      // Fetch sales returns in the same range and index them by their
      // original invoice so the grand total can subtract them.
      final returns = await widget.db.salesReturnsDao.getReturnsByDateRange(
        _startDate,
        _endDate,
      );
      final returnsByInvoice = <int, double>{};
      for (final ret in returns) {
        returnsByInvoice.update(
          ret.originalInvoiceId,
          (sum) => sum + ret.totalAmount,
          ifAbsent: () => ret.totalAmount,
        );
      }

      setState(() {
        _invoices = invoices;
        _filteredInvoices = List.from(invoices);
        _returnsByInvoice = returnsByInvoice;
        _isLoading = false;
      });

      developer.log('✓ Invoice data loaded successfully');
      developer.log('Start date: $_startDate');
      developer.log('End date: $_endDate');
      developer.log('Found ${invoices.length} invoices in date range');
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading sales data: $e'),
            backgroundColor: Colors.red,
          ),
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(colorScheme: ColorScheme.light(primary: Colors.purple)),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  Future<void> _exportPDF() async {
    try {
      final List<Map<String, dynamic>> data = [];

      for (final invoice in _invoices) {
        data.add({
          'invoiceNumber': displayInvoiceNumber(
                invoice.invoiceNumber,
                invoice.id,
              ) ??
              '',
          'customerName': invoice.customerName ?? 'عميل غير محدد',
          'totalAmount': invoice.totalAmount,
          'paidAmount': invoice.paidAmount,
          'date': DateFormat('yyyy-MM-dd HH:mm').format(invoice.date.toLocal()),
          'status': invoice.status,
        });
      }

      // Use enhanced export with consistent Arabic columns
      await _exportService.exportToPDF(
        title: 'تقارير المبيعات',
        headers: [
          'رقم الفاتورة',
          'اسم العميل',
          'المبلغ الإجمالي',
          'المدفوع',
          'التاريخ',
          'الحالة',
        ],
        columns: [
          'invoiceNumber',
          'customerName',
          'totalAmount',
          'paidAmount',
          'date',
          'status',
        ],
        data: data,
        fileName:
            'sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    }
  }

  // Thermal receipt printing using UnifiedPrintService
  Future<void> _printThermalReceipt() async {
    try {
      final messengerContext = context; // Capture context before async
      if (_invoices.isEmpty) return;

      final grandTotal = _invoices.fold(
        0.0,
        (sum, inv) =>
            sum + inv.totalAmount - (_returnsByInvoice[inv.id] ?? 0),
      );

      // Create sales report data for UnifiedPrintService
      final reportItems = [
        ups.InvoiceItem(
          id: 0,
          invoiceId: 0,
          description: 'ملخص تقرير المبيعات',
          unit: 'تقرير',
          quantity: 1,
          unitPrice: grandTotal,
          totalPrice: grandTotal,
        ),
      ];

      final storeInfo = ups.StoreInfo(
        storeName: 'المحل التجاري',
        phone: '01234567890',
        zipCode: '12345',
        state: 'القاهرة',
      );

      final reportInvoice = ups.Invoice(
        id: 0,
        invoiceNumber: 'SALES-${DateTime.now().millisecondsSinceEpoch}',
        customerName: 'تقارير المبيعات',
        customerPhone: '',
        customerZipCode: '',
        customerState: '',
        invoiceDate: DateTime.now(),
        subtotal: grandTotal,
        isCreditAccount: false,
        previousBalance: 0.0,
        totalAmount: grandTotal,
      );

      final invoiceData = ups.InvoiceData(
        invoice: reportInvoice,
        items: reportItems,
        storeInfo: storeInfo,
      );

      // Print using new SOP 4.0 format
      await ups.UnifiedPrintService.printToThermalPrinter(
        documentType: ups.DocumentType.salesInvoice,
        data: invoiceData,
      );

      if (mounted && messengerContext.mounted) {
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          const SnackBar(content: Text('تم إرسال الطباعة الحرارية')),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  Future<void> _printIndividualInvoice(Invoice invoice) async {
    try {
      // Get invoice items with product details
      final itemsWithProducts = await widget.db.invoiceDao
          .getItemsWithProductsByInvoice(invoice.id);

      final variantMap = <int, String>{};
      for (final itemWithProduct in itemsWithProducts) {
        final vId = itemWithProduct.$1.variantId;
        if (vId != null && !variantMap.containsKey(vId)) {
          final v = await widget.db.productVariantDao.getVariantById(vId);
          if (v != null) {
            variantMap[vId] = v.name;
          }
        }
      }

      // Convert to maps for printing
      final itemsMaps = itemsWithProducts.map((itemWithProduct) {
        final item = itemWithProduct.$1;
        final product = itemWithProduct.$2;
        final baseName = product?.name ?? 'Product ${item.productId}';
        final vName = item.variantId != null ? variantMap[item.variantId] : null;
        final fullName = (vName != null && !baseName.endsWith('— $vName'))
            ? '$baseName — $vName'
            : baseName;
        return {
          'productName': fullName,
          'name': fullName,
          'quantity': item.quantity,
          'price': item.price,
          'total': item.quantity * item.price,
        };
      }).toList();

      // Print with REPRINT header
      await PrinterService.printDuplicateInvoice(
        invoice: {
          'id': invoice.id,
          'customerName': invoice.customerName,
          'date': invoice.date,
          'totalAmount': invoice.totalAmount,
          'paymentMethod': invoice.paymentMethod,
          'invoiceNumber': invoice.invoiceNumber,
        },
        items: itemsMaps,
        paymentMethod: invoice.paymentMethod ?? 'cash',
        ledgerDao: widget.db.ledgerDao,
        invoiceDao: widget.db.invoiceDao,
        customerDao: widget.db.customerDao,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إعادة طباعة الفاتورة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  Future<void> _exportExcel() async {
    try {
      final List<Map<String, dynamic>> data = [];

      for (final invoice in _invoices) {
        data.add({
          'رقم الفاتورة': displayInvoiceNumber(invoice.invoiceNumber, invoice.id) ?? '',
          'اسم العميل': invoice.customerName ?? 'عميل غير محدد',
          'المبلغ الإجمالي': invoice.totalAmount,
          'المدفوع': invoice.paidAmount,
          'التاريخ': DateFormat('yyyy-MM-dd HH:mm').format(invoice.date.toLocal()),
          'الحالة': invoice.status,
        });
      }

      await _exportService.exportToExcel(
        title: 'تقارير المبيعات',
        headers: [
          'رقم الفاتورة',
          'اسم العميل',
          'المبلغ الإجمالي',
          'المدفوع',
          'التاريخ',
          'الحالة',
        ],
        columns: [
          'رقم الفاتورة',
          'اسم العميل',
          'المبلغ الإجمالي',
          'المدفوع',
          'التاريخ',
          'الحالة',
        ],
        data: data,
        fileName:
            'sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  /// يفتح ديالوج المرتجع الجزئي الموحّد — نفس المسار اللي بيستخدمه
  /// transaction_detail_dialog. الـ dialog القديم الأول كان بيعمل إرجاع على
  /// مستوى المنتج مش السطر (من غير invoiceItemId) فكان ممكن يرجّع نفس
  /// الكمية أكتر من مرة ويضاعف المخزون، وبحسب السعر غلط.
  Future<void> _showReturnDialog(Invoice invoice) async {
    if (invoice.status == 'voided') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن المرتجع على فاتورة ملغاة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // الديالوج الجديد بيتولى رسالة النجاح/الخطأ بنفسه ويحدّث القائمة.
    await showDialog<bool>(
      context: context,
      builder: (ctx) => InvoicePartialReturnDialog(
        db: widget.db,
        invoiceId: invoice.id,
        onDone: _loadData,
      ),
    );
  }

  /// إلغاء الفاتورة من التقرير — نفس الـdialog ونفس الصلاحية المستخدمة في
  /// شاشة تفاصيل المعاملة، عشان السلوك يبقى واحد في كل الشاشات.
  void _openEditInvoice(Invoice invoice) {
    if (invoice.status == 'voided') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن تعديل فاتورة ملغاة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditInvoicePage(
          db: widget.db,
          invoiceId: invoice.id,
          onSaved: () {
            _loadData();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _editInvoiceDate(Invoice invoice) async {
    if (invoice.status == 'voided') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن تعديل تاريخ فاتورة ملغاة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final picked = await pickDocumentDate(
      context: context,
      db: widget.db,
      initialDate: invoice.date,
    );
    if (picked != null) {
      final user = ref.read<User?>(authProvider)?.username;
      await DocumentDateService(widget.db).updateInvoiceDate(
        invoiceId: invoice.id,
        newDate: picked,
        userId: user,
      );
      if (mounted) {
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تعديل تاريخ الفاتورة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _voidInvoice(Invoice invoice) async {
    if (invoice.status == 'voided') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الفاتورة ملغاة بالفعل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => VoidInvoiceDialog(
        db: widget.db,
        invoiceId: invoice.id,
        voidedBy:
            ref.read<User?>(authProvider)?.username ?? 'unknown',
        onDone: _loadData,
      ),
    );
    if (done == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = _filteredInvoices.fold(
      0.0,
      (sum, invoice) =>
          sum + invoice.totalAmount - (_returnsByInvoice[invoice.id] ?? 0),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'تقارير المبيعات',
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
                        hintText:
                            'البحث عن فاتورة (رقم الفاتورة، اسم العميل، المبلغ)',
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
                        onPressed: _printThermalReceipt,
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
                color: const Color(0xFF238636).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF238636).withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF238636).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      color: Color(0xFF238636),
                      size: 20,
                    ),
                  ),
                  const Gap(12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'صافي إجمالي المبيعات',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'عدد الفواتير: ${_filteredInvoices.length}',
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
                      color: Color(0xFF238636),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(14),

            // Data Table / List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredInvoices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.receipt_long_outlined,
                                size: 56,
                                color: Colors.grey,
                              ),
                              const Gap(12),
                              Text(
                                'لا توجد فواتير مبيعات في الفترة المحددة',
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
                          itemCount: _filteredInvoices.length,
                          itemBuilder: (context, index) {
                            final invoice = _filteredInvoices[index];
                            return _InvoiceExpansionTile(
                              invoice: invoice,
                              db: widget.db,
                              hasReturn:
                                  _returnsByInvoice.containsKey(invoice.id),
                              onPrint: () => _printIndividualInvoice(invoice),
                              onReturn: () => _showReturnDialog(invoice),
                              onVoid: () => _voidInvoice(invoice),
                              onEditInvoice: () => _openEditInvoice(invoice),
                              onEditDate: () => _editInvoiceDate(invoice),
                              isVoided: invoice.status == 'voided',
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

class _InvoiceExpansionTile extends StatefulWidget {
  final Invoice invoice;
  final AppDatabase db;
  final bool hasReturn;
  final VoidCallback onPrint;
  final VoidCallback onReturn;
  final VoidCallback onVoid;
  final VoidCallback? onEditInvoice;
  final VoidCallback? onEditDate;
  final bool isVoided;

  const _InvoiceExpansionTile({
    required this.invoice,
    required this.db,
    required this.hasReturn,
    required this.onPrint,
    required this.onReturn,
    required this.onVoid,
    this.onEditInvoice,
    this.onEditDate,
    this.isVoided = false,
  });

  @override
  State<_InvoiceExpansionTile> createState() => _InvoiceExpansionTileState();
}

class _InvoiceExpansionTileState extends State<_InvoiceExpansionTile> {
  bool _isExpanded = false;
  List<(InvoiceItem, Product?)> _invoiceItems = [];
  Map<int, String> _variantNames = {};
  bool _isLoadingItems = false;

  String _formatCustomerName(String? name) {
    if (name == null || name.trim().isEmpty) return 'عميل نقدي';
    final trimmed = name.trim();
    if (trimmed.startsWith('__SYNC_CUST_') ||
        trimmed.startsWith('TEMP_') ||
        trimmed.startsWith('CUST_') ||
        trimmed == 'null') {
      return 'عميل نقدي';
    }
    return trimmed;
  }

  Future<void> _loadInvoiceItems({bool force = false}) async {
    if ((_isExpanded || force) && _invoiceItems.isEmpty) {
      setState(() => _isLoadingItems = true);
      try {
        final items = await widget.db.invoiceDao.getItemsWithProductsByInvoice(
          widget.invoice.id,
        );
        final variantMap = <int, String>{};
        for (final itemWithProduct in items) {
          final vId = itemWithProduct.$1.variantId;
          if (vId != null && !variantMap.containsKey(vId)) {
            final v = await widget.db.productVariantDao.getVariantById(vId);
            if (v != null) {
              variantMap[vId] = v.name;
            }
          }
        }
        setState(() {
          _invoiceItems = items;
          _variantNames = variantMap;
          _isLoadingItems = false;
        });
      } catch (e) {
        setState(() => _isLoadingItems = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في تحميل عناصر الفاتورة: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showInvoiceDetailsDialog(BuildContext modalContext) async {
    if (_invoiceItems.isEmpty) {
      await _loadInvoiceItems(force: true);
    }
    if (!mounted || !modalContext.mounted) return;

    final remaining = widget.invoice.totalAmount - widget.invoice.paidAmount;
    final isFullyPaid = remaining <= 0.001;
    final formattedNumber = displayInvoiceNumber(widget.invoice.invoiceNumber, widget.invoice.id) ?? '';

    await showDialog(
      context: modalContext,
      builder: (dialogCtx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Dialog(
          backgroundColor: const Color(0xFF1E222B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Container(
            width: 620,
            constraints: const BoxConstraints(maxHeight: 700),
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dialog Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: MadarColors.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: MadarColors.gold,
                            size: 24,
                          ),
                        ),
                        const Gap(12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تفاصيل الفاتورة #$formattedNumber',
                              style: const TextStyle(
                                fontFamily: 'NotoSansArabic',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              DateFormat('yyyy-MM-dd HH:mm').format(widget.invoice.date.toLocal()),
                              style: TextStyle(
                                fontFamily: 'NotoSansArabic',
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                    ),
                  ],
                ),
                const Gap(16),

                // Info Badges
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildInfoItem('العميل', _formatCustomerName(widget.invoice.customerName), Icons.person_outline),
                      _buildInfoItem(
                        'حالة السداد',
                        isFullyPaid ? 'مدفوعة بالكامل' : 'متبقي ${remaining.toStringAsFixed(2)} ج.م',
                        isFullyPaid ? Icons.check_circle_outline : Icons.pending_outlined,
                        color: isFullyPaid ? Colors.greenAccent : Colors.orangeAccent,
                      ),
                      if (widget.hasReturn)
                        _buildInfoItem('المرتجع', 'يوجد مرتجع', Icons.undo_rounded, color: Colors.redAccent),
                    ],
                  ),
                ),
                const Gap(16),

                // Items list / table
                const Text(
                  'المنتجات والبنود',
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Gap(8),
                Flexible(
                  child: _isLoadingItems
                      ? const Center(child: CircularProgressIndicator())
                      : _invoiceItems.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('لا توجد منتجات مسجلة في الفاتورة', style: TextStyle(color: Colors.white60)),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(const Color(0xFF161B22)),
                                    dataRowColor: WidgetStateProperty.all(Colors.transparent),
                                    columns: const [
                                      DataColumn(label: Text('المنتج', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('سعر الوحدة', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                      DataColumn(label: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                                    ],
                                    rows: _invoiceItems.map((itemWithProduct) {
                                      final item = itemWithProduct.$1;
                                      final product = itemWithProduct.$2;
                                      final unitPrice = item.quantity > 0 ? item.price / item.quantity : 0.0;
                                      final baseName = product?.name ?? 'منتج ${item.productId}';
                                      final vName = item.variantId != null ? _variantNames[item.variantId] : null;
                                      final fullName = (vName != null && !baseName.endsWith('— $vName')) ? '$baseName — $vName' : baseName;

                                      return DataRow(
                                        cells: [
                                          DataCell(Text(fullName, style: const TextStyle(color: Colors.white70))),
                                          DataCell(Text('${item.quantity}', style: const TextStyle(color: Colors.white70))),
                                          DataCell(Text('${unitPrice.toStringAsFixed(2)} ج.م', style: const TextStyle(color: Colors.white70))),
                                          DataCell(Text('${item.price.toStringAsFixed(2)} ج.م', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent))),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                ),
                const Gap(16),

                // Financial Footer Summary
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MadarColors.gold.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المدفوع: ${widget.invoice.paidAmount.toStringAsFixed(2)} ج.م', style: const TextStyle(fontFamily: 'NotoSansArabic', color: Colors.white70, fontSize: 13)),
                          if (remaining > 0.001)
                            Text('المتبقي: ${remaining.toStringAsFixed(2)} ج.م', style: const TextStyle(fontFamily: 'NotoSansArabic', color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('الإجمالي الكلي: ', style: TextStyle(fontFamily: 'NotoSansArabic', color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          Text('${widget.invoice.totalAmount.toStringAsFixed(2)} ج.م', style: const TextStyle(fontFamily: 'NotoSansArabic', color: Color(0xFF10B981), fontSize: 18, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Gap(18),

                // Action Buttons in Dialog
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                      child: const Text('إغلاق', style: TextStyle(fontFamily: 'NotoSansArabic')),
                    ),
                    const SizedBox(width: 8),
                    if (!widget.isVoided && widget.onEditInvoice != null)
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(dialogCtx).pop();
                          widget.onEditInvoice?.call();
                        },
                        icon: const Icon(Icons.edit_note, size: 18),
                        label: const Text('تعديل الفاتورة', style: TextStyle(fontFamily: 'NotoSansArabic')),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                      ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(dialogCtx).pop();
                        widget.onPrint();
                      },
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('طباعة', style: TextStyle(fontFamily: 'NotoSansArabic')),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String title, String value, IconData icon, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? Colors.white54),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 10.5,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: color ?? Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MadarColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Icon(
                Icons.receipt_rounded,
                color: MadarColors.gold,
                size: 18,
              ),
            ),
          ),
        title: Row(
          children: [
            Text(
              displayInvoiceNumber(widget.invoice.invoiceNumber, widget.invoice.id) ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white, // White text for dark theme
              ),
            ),
            if (widget.hasReturn) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'مرتجع',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatCustomerName(widget.invoice.customerName),
              style: const TextStyle(
                fontFamily: 'NotoSansArabic',
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('yyyy-MM-dd HH:mm').format(widget.invoice.date.toLocal()),
              style: const TextStyle(
                fontFamily: 'NotoSansArabic',
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${widget.invoice.totalAmount.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                ),
                Text(
                  '${widget.invoice.paidAmount.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(
                    fontFamily: 'NotoSansArabic',
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            // Eye icon for quick view/preview modal
            IconButton(
              icon: const Icon(Icons.visibility_outlined, size: 20, color: Color(0xFF388BFD)),
              onPressed: () => _showInvoiceDetailsDialog(context),
              tooltip: 'معاينة تفاصيل الفاتورة',
            ),
            // Direct edit invoice button
            if (!widget.isVoided && widget.onEditInvoice != null)
              IconButton(
                icon: const Icon(Icons.edit_note_rounded, size: 22, color: Colors.amberAccent),
                onPressed: widget.onEditInvoice,
                tooltip: 'تعديل الفاتورة',
              ),
            IconButton(
              icon: const Icon(Icons.print_outlined, size: 20, color: Colors.orangeAccent),
              onPressed: widget.onPrint,
              tooltip: 'طباعة الفاتورة',
            ),
            IconButton(
              icon: const Icon(Icons.undo, size: 20, color: Colors.redAccent),
              onPressed: widget.onReturn,
              tooltip: 'مرتجع',
            ),
            if (!widget.isVoided && widget.onEditDate != null)
              IconButton(
                icon: const Icon(Icons.edit_calendar_outlined, size: 20, color: Colors.tealAccent),
                onPressed: widget.onEditDate,
                tooltip: 'تعديل تاريخ الفاتورة',
              ),
            // إلغاء الفاتورة — بيظهر دايماً (الفحص جوّه الديالوج).
            if (!widget.isVoided)
              PermissionGuardedIconButton(
                icon: Icons.delete_outline,
                color: Colors.red,
                tooltip: 'إلغاء الفاتورة',
                onPressed: widget.onVoid,
              ),
          ],
        ),
        onExpansionChanged: (expanded) {
          setState(() => _isExpanded = expanded);
          if (expanded) {
            _loadInvoiceItems();
          }
        },
        children: [
          if (_isLoadingItems)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_invoiceItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('لا توجد منتجات في هذه الفاتورة'),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(
                  0xFF21262D,
                ), // Slightly lighter dark for expanded content
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تفاصيل المنتجات',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      Colors.grey.withValues(alpha: 0.2),
                    ),
                    dataRowColor: WidgetStateProperty.all(Colors.transparent),
                    columns: const [
                      DataColumn(
                        label: Text(
                          'اسم المنتج',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'الكمية',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'سعر الوحدة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'الإجمالي',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    rows: _invoiceItems.map((itemWithProduct) {
                      final item = itemWithProduct.$1;
                      final product = itemWithProduct.$2;
                      final unitPrice = item.quantity > 0
                          ? item.price / item.quantity
                          : 0.0;

                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              () {
                                final base = product?.name ?? 'منتج ${item.productId}';
                                final v = item.variantId != null ? _variantNames[item.variantId] : null;
                                return (v != null && !base.endsWith('— $v')) ? '$base — $v' : base;
                              }(),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            Text(
                              item.quantity.toString(),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${unitPrice.toStringAsFixed(2)} ج.م',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${item.price.toStringAsFixed(2)} ج.م',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!widget.isVoided) ...[
                        if (widget.onEditInvoice != null)
                          OutlinedButton.icon(
                            onPressed: widget.onEditInvoice,
                            icon: const Icon(Icons.edit_note, size: 18),
                            label: const Text('تعديل الفاتورة'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blueAccent,
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (widget.onEditDate != null)
                          OutlinedButton.icon(
                            onPressed: widget.onEditDate,
                            icon: const Icon(Icons.edit_calendar, size: 18),
                            label: const Text('تعديل التاريخ'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.tealAccent,
                            ),
                          ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton.icon(
                        onPressed: widget.onPrint,
                        icon: const Icon(Icons.print),
                        label: const Text('طباعة الفاتورة'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }
}
