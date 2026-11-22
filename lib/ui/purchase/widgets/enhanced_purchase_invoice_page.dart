import 'dart:async';
import 'dart:developer';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/purchase_edit_service.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/day_closed_dialog.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/product_card.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/product_selection_modal.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/order_line_item.dart';
import 'package:pos_offline_desktop/ui/invoice/models/product_entry.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/ui/widgets/document_date_picker.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'product_quick_add_dialog.dart';

// Payment method enum
enum PaymentMethod { cash, visa, mastercard, transfer, wallet, other }

class EnhancedPurchaseInvoicePage extends StatefulHookConsumerWidget {
  final AppDatabase db;

  /// When set, the page edits this purchase instead of creating a new one.
  /// The supplier stays locked (no cross-supplier moves); the invoice number
  /// is preserved, never regenerated.
  final String? purchaseId;

  const EnhancedPurchaseInvoicePage({super.key, required this.db, this.purchaseId});

  bool get isEdit => purchaseId != null;

  @override
  ConsumerState<EnhancedPurchaseInvoicePage> createState() =>
      _EnhancedPurchaseInvoicePageState();
}

class _EnhancedPurchaseInvoicePageState
    extends ConsumerState<EnhancedPurchaseInvoicePage> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _paidAmountController = TextEditingController();
  final _notesController = TextEditingController();

  // Purchase invoice data
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  Supplier? _selectedSupplier;
  DateTime _purchaseDate = DateTime.now();
  final List<ProductEntry> _productEntries = [];

  Future<void> _pickPurchaseDate() async {
    final picked = await pickDocumentDate(
      context: context,
      db: widget.db,
      initialDate: _purchaseDate,
    );
    if (picked != null) {
      setState(() => _purchaseDate = picked);
    }
  }

  // Products and search
  List<Product> _filteredProducts = [];
  List<Supplier> _suppliers = [];

  // Totals
  double _subtotal = 0.0;
  // ignore: unused_field
  // ignore: unused_field
  double _totalDiscount = 0.0;
  // ignore: unused_field
  // ignore: unused_field
  double _totalTax = 0.0;
  double _grandTotal = 0.0;
  double _paidAmount = 0.0;
  double _remainingAmount = 0.0;

  // State
  bool _isDayOpen = false;
  bool _isLoading = true;
  Timer? _searchDebounce;
  String? _invoiceNumber;

  @override
  void initState() {
    super.initState();
    _initializePurchaseInvoice();
    _searchController.addListener(_onSearchChanged);
    _paidAmountController.addListener(_onPaidAmountChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _paidAmountController.dispose();
    _notesController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recheck day status when returning to this page
    _checkDayStatus();
  }

  // Edit mode state: orphan lines (product deleted since, kept verbatim
  // on save) + their frozen value (stays in the header total).
  List<PurchaseItem> _orphanItems = [];
  double _orphanTotal = 0.0;

  /// Loads an existing purchase for editing. The supplier stays locked and
  /// the invoice number is preserved. Lines whose product was deleted since
  /// are carried forward untouched (never restocked, never deleted).
  Future<void> _loadForEdit() async {
    final purchase = await (widget.db.select(widget.db.purchases)
          ..where((t) => t.id.equals(widget.purchaseId!)))
        .getSingleOrNull();
    if (purchase == null) throw Exception('فاتورة المشتريات غير موجودة');

    _invoiceNumber = purchase.invoiceNumber;
    _purchaseDate = purchase.purchaseDate;
    _paidAmount = purchase.paidAmount;
    _paidAmountController.text = purchase.paidAmount.toStringAsFixed(2);
    _paymentMethod = PaymentMethod.values.firstWhere(
      (m) => m.name == purchase.paymentMethod,
      orElse: () => PaymentMethod.cash,
    );
    if (purchase.supplierId != null) {
      final s = await widget.db.supplierDao.getSupplierById(
        purchase.supplierId!,
      );
      if (s != null) _selectedSupplier = s;
    }

    final pairs = await widget.db.purchaseDao.getItemsWithProductsByPurchase(
      purchase.id,
    );
    _productEntries.clear();
    _orphanItems = [];
    _orphanTotal = 0.0;
    for (final pair in pairs) {
      final item = pair.$1;
      final product = pair.$2;
      if (product == null) {
        _orphanItems.add(item);
        _orphanTotal += item.totalPrice;
        continue;
      }
      final entry = ProductEntry(product: product)
        ..quantity = item.quantity
        ..unit = item.unit
        ..unitPrice = item.unitPrice
        ..discount = item.discount
        ..tax = item.tax
        ..lineTotal = item.totalPrice;
      _productEntries.add(entry);
    }
    _calculateTotals();
  }

  Future<void> _checkDayStatus() async {
    try {
      final isOpen = await widget.db.dayDao.isDayOpen();
      if (mounted) {
        setState(() {
          _isDayOpen = isOpen;
        });
      }
    } catch (e) {
      debugPrint('Error checking day status: $e');
    }
  }

  Future<void> _initializePurchaseInvoice() async {
    try {
      // Check day status first
      final isOpen = await widget.db.dayDao.isDayOpen();

      if (!isOpen) {
        setState(() {
          _isDayOpen = false;
          _isLoading = false;
        });
        return;
      }

      // Load data
      final products = await widget.db.productDao.getAllProducts();
      final suppliers = await widget.db.supplierDao.getAllSuppliers();

      // Bug 3: no pre-generated number. The PUR- sequence value is assigned
      // at SAVE time (_nextPurchaseNumber), so abandoned forms leave no gaps.
      // Edit mode loads the existing purchase instead (number preserved).
      if (widget.purchaseId != null) {
        await _loadForEdit();
      }

      setState(() {
        _isDayOpen = true;
        _filteredProducts = products;
        _suppliers = suppliers;
        _isLoading = false;
      });
    } catch (e) {
      log('Error initializing purchase invoice: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في تحميل البيانات: $e')));
      }
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _applyFilters();
    });
  }

  Future<void> _applyFilters() async {
    final query = _searchController.text.toLowerCase();

    final filtered = await widget.db.productDao.filterProducts(
      category: null,
      unit: null,
      searchQuery: query.isEmpty ? null : query,
    );

    setState(() {
      _filteredProducts = filtered;
    });
  }

  void _onPaidAmountChanged() {
    final paid = double.tryParse(_paidAmountController.text) ?? 0.0;
    setState(() {
      _paidAmount = paid;
      _remainingAmount = _grandTotal - paid;
    });
  }

  void _showProductSelectionModal([Product? product]) {
    showDialog(
      context: context,
      builder: (context) => ProductSelectionModal(
        product: product ?? _filteredProducts.first,
        db: widget.db,
        forPurchase: true,
        onConfirm: (quantity, unit, unitPrice, discount, tax, [variant]) {
          _addProductToPurchase(
            product ?? _filteredProducts.first,
            quantity,
            unitPrice,
            unit: unit,
            discount: discount,
            tax: tax,
          );
        },
      ),
    );
  }

  /// Show quick add product dialog
  Future<void> _showQuickAddProduct() async {
    final result = await showDialog<Product>(
      context: context,
      builder: (context) => ProductQuickAddDialog(
        database: widget.db,
        onProductAdded: (product) async {
          // Refresh products list
          final products = await widget.db.productDao.getAllProducts();
          setState(() {
            _filteredProducts = products;
          });
        },
      ),
    );

    // If product was added, optionally add it to the purchase immediately
    if (result != null) {
      _showProductSelectionModal(result);
    }
  }

  void _addProductToPurchase(
    Product product,
    int quantity,
    double unitPrice, {
    String unit = 'piece',
    double discount = 0.0,
    double tax = 0.0,
  }) {
    final entry = ProductEntry(product: product);
    entry.quantity = quantity;
    entry.unitPrice = unitPrice;
    entry.unit = unit;
    entry.discount = discount;
    entry.tax = tax;
    entry.lineTotal = (unitPrice * quantity) - discount + tax;

    setState(() {
      _productEntries.add(entry);
      _calculateTotals();
    });
  }

  void _removeProductEntry(int index) {
    setState(() {
      _productEntries.removeAt(index);
      _calculateTotals();
    });
  }

  void _updateProductEntry(int index, ProductEntry entry) {
    setState(() {
      _productEntries[index] = entry;
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    _subtotal = _productEntries.fold(
      0.0,
      (sum, entry) => sum + entry.lineTotal,
    );
    _totalDiscount = _productEntries.fold(
      0.0,
      (sum, entry) => sum + entry.discount,
    );
    _totalTax = _productEntries.fold(
      0.0,
      (sum, entry) => sum + entry.tax,
    );
    _grandTotal = _subtotal;
    _remainingAmount = _grandTotal - _paidAmount;
  }

  /// Next supplier number: max existing `PUR-(\d+)` + 1 (own series,
  /// never customer values). Existence loop closes even a theoretical
  /// same-moment collision; legacy non-matching numbers are ignored.
  Future<String> _nextPurchaseNumber() async {
    final rows = await widget.db.customSelect(
      "SELECT invoice_number AS n FROM purchases "
      "WHERE invoice_number LIKE 'PUR-%'",
    ).get();
    var maxN = 0;
    for (final r in rows) {
      final n = parsePurchaseNumber(r.readNullable<String>('n'));
      if (n != null && n > maxN) maxN = n;
    }
    var candidate = maxN + 1;
    while (true) {
      final num = formatPurchaseNumber(candidate);
      final exists = await (widget.db.select(widget.db.purchases)
            ..where((t) => t.id.equals(num)))
          .getSingleOrNull();
      if (exists == null) return num;
      candidate++;
    }
  }

  Future<void> _savePurchaseInvoice() async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار المورد'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Bug 3: supplier sequence (own series, never customer values).
    // Edit mode keeps the existing number (assigned at original save).
    if (widget.purchaseId == null) {
      _invoiceNumber ??= await _nextPurchaseNumber();
    }
    if (!mounted) return;

    if (_productEntries.isEmpty && _orphanItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة منتج واحد على الأقل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Edit mode: rewrite lines/stock/ledger around the preserved number.
    if (widget.purchaseId != null) {
      await _updatePurchaseInvoice();
      return;
    }

    try {
      // One atomic unit: purchase + items + stock + supplier ledger.
      // A partial save (e.g. stock updated but ledger missing) used to be
      // the zero-balance-cards bug — it can no longer happen.
      await widget.db.transaction(() async {
        // Create purchase invoice
        final purchaseInvoice = PurchasesCompanion.insert(
          id: _invoiceNumber!,
          invoiceNumber: _invoiceNumber!,
          description: 'فاتورة مشتريات من ${_selectedSupplier!.name}',
          totalAmount: _grandTotal,
          purchaseDate: _purchaseDate,
          createdAt: DateTime.now(),
          supplierId: Value(_selectedSupplier!.id),
          paidAmount: Value(_paidAmount),
          paymentMethod: Value(_paymentMethod.name),
          status: Value('completed'),
        );

        await widget.db.into(widget.db.purchases).insert(purchaseInvoice);

        // Add purchase items
        for (final entry in _productEntries) {
          await widget.db
              .into(widget.db.purchaseItems)
              .insert(
                PurchaseItemsCompanion.insert(
                  id: '${_invoiceNumber}_${entry.product!.id}',
                  purchaseId: _invoiceNumber!,
                  productId: entry.product!.id.toString(),
                  quantity: entry.quantity,
                  unitPrice: entry.unitPrice,
                  totalPrice: entry.lineTotal,
                  unit: entry.product!.unit ?? 'قطعة',
                  createdAt: DateTime.now(),
                ),
              );

          // Update inventory - INCREASE stock for purchases
          final currentProduct = entry.product!;
          final updatedProduct = currentProduct.copyWith(
            quantity: currentProduct.quantity + entry.quantity,
          );
          await widget.db.productDao.updateProduct(updatedProduct);
        }

        // Supplier ledger pair (due + payment) for EVERY payment method —
        // cash purchases used to skip this and left balances at zero.
        await widget.db.ledgerDao.recordSupplierPurchase(
          supplierId: _selectedSupplier!.id,
          invoiceNumber: _invoiceNumber!,
          total: _grandTotal,
          paid: _paidAmount,
          date: _purchaseDate,
        );
      });

      // Print invoice
      await _printPurchaseInvoice();

      // Reset form
      _resetForm();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ فاتورة المشتريات بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      log('Error saving purchase invoice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ الفاتورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Edit-mode save: the supplier and invoice number are preserved; lines,
  /// stock and the ledger pair are rewritten atomically around them.
  /// Orphan lines (product deleted since) stay verbatim and their frozen
  /// value remains part of the header total.
  Future<void> _updatePurchaseInvoice() async {
    final purchaseId = widget.purchaseId!;
    final number = _invoiceNumber;
    if (number == null || _selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بيانات الفاتورة غير مكتملة')),
      );
      return;
    }
    try {
      await PurchaseEditService(widget.db).applyEdit(
        purchaseId: purchaseId,
        invoiceNumber: number,
        supplierId: _selectedSupplier!.id,
        total: _grandTotal + _orphanTotal,
        paid: _paidAmount,
        paymentMethod: _paymentMethod.name,
        purchaseDate: _purchaseDate,
        lines: [
          for (final entry in _productEntries)
            if (entry.product != null)
              PurchaseEditLine(
                productId: entry.product!.id,
                quantity: entry.quantity,
                unit: entry.unit,
                unitPrice: entry.unitPrice,
                discount: entry.discount,
                tax: entry.tax,
              ),
        ],
      );

      await _printPurchaseInvoice();
      _resetForm();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تعديل فاتورة المشتريات بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      log('Error updating purchase invoice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تعديل الفاتورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _printPurchaseInvoice() async {
    try {
      final purchaseItems = _productEntries
          .map(
            (entry) => ups.InvoiceItem(
              id: 0,
              invoiceId: int.tryParse(_invoiceNumber ?? '0') ?? 0,
              description: entry.product?.name ?? 'منتج غير محدد',
              unit: entry.product?.unit ?? 'قطعة',
              quantity: entry.quantity,
              unitPrice: entry.unitPrice,
              totalPrice: entry.lineTotal,
            ),
          )
          .toList();

      final storeInfo = ups.StoreInfo(
        storeName: 'المحل التجاري',
        phone: '01234567890',
        zipCode: '12345',
        state: 'القاهرة',
      );

      final purchaseInvoice = ups.Invoice(
        id: int.tryParse(_invoiceNumber ?? '0') ?? 0,
        invoiceNumber: _invoiceNumber ?? '',
        customerName: _selectedSupplier?.name ?? 'مورد غير محدد',
        customerPhone: _selectedSupplier?.phone ?? '',
        customerZipCode: '',
        customerState: '',
        invoiceDate: _purchaseDate,
        subtotal: _subtotal,
        isCreditAccount: _paymentMethod != PaymentMethod.cash,
        previousBalance: 0.0,
        totalAmount: _grandTotal,
      );

      final invoiceData = ups.InvoiceData(
        invoice: purchaseInvoice,
        items: purchaseItems,
        storeInfo: storeInfo,
      );

      // Print using SOP 4.0 format
      await ups.UnifiedPrintService.printToThermalPrinter(
        documentType: ups.DocumentType.salesInvoice, // Reuse for now
        data: invoiceData,
      );
    } catch (e) {
      log('Error printing purchase invoice: $e');
    }
  }

  void _resetForm() {
    setState(() {
      _selectedSupplier = null;
      _purchaseDate = DateTime.now();
      _productEntries.clear();
      _paidAmountController.clear();
      _notesController.clear();
      _paymentMethod = PaymentMethod.cash;
      _calculateTotals();
      _invoiceNumber = null; // Next save assigns a fresh sequence value.
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDayOpen) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('فاتورة مشتريات جديدة'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/'),
            tooltip: 'رجوع',
          ),
        ),
        body: DayClosedDialog(
          onOpenDay: () {
            // Implement open day functionality
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('فاتورة مشتريات جديدة'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/'),
            tooltip: 'رجوع',
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: MadarColors.bgDark,
      appBar: AppBar(
        title: Text(
          widget.purchaseId != null
              ? 'تعديل فاتورة مشتريات ${_invoiceNumber ?? ''}'
              : (_invoiceNumber == null
                  ? 'فاتورة مشتريات جديدة'
                  : 'فاتورة مشتريات جديدة #$_invoiceNumber'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
          tooltip: 'رجوع',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: _savePurchaseInvoice,
            tooltip: 'حفظ الفاتورة',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Row(
          children: [
            // Products Panel (5/8 width - displayed on start/right in RTL)
            Expanded(
              flex: 5,
              child: _buildProductsPanel(),
            ),

            const VerticalDivider(width: 1, color: MadarColors.border),

            // Invoice Details Panel (3/8 width - displayed on end/left in RTL)
            Expanded(
              flex: 3,
              child: _buildDetailsPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsPanel() {
    return Container(
      color: MadarColors.bgDark,
      child: Column(
        children: [
          // Search bar with quick add button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: MadarColors.textLight, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'البحث عن المنتجات (الاسم، الباركود)...',
                        hintStyle: const TextStyle(color: MadarColors.textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: MadarColors.textSecondary, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: MadarColors.textMuted),
                                onPressed: () {
                                  _searchController.clear();
                                  _applyFilters();
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: MadarColors.bgCard,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: MadarColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: MadarColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: MadarColors.gold, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const Gap(10),
                ElevatedButton.icon(
                  onPressed: _showQuickAddProduct,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    'منتج جديد',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MadarColors.gold,
                    foregroundColor: Colors.black,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Products grid
          Expanded(
            child: _filteredProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: MadarColors.textMuted.withValues(alpha: 0.5),
                        ),
                        const Gap(12),
                        const Text(
                          'لا توجد منتجات مطابقة للبحث',
                          style: TextStyle(
                            color: MadarColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1.15,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      return ProductCard(
                        product: product,
                        onTap: () => _showProductSelectionModal(product),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel() {
    return Container(
      color: MadarColors.bgCard,
      child: Column(
        children: [
          // Invoice header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: MadarColors.bgSurface.withValues(alpha: 0.4),
              border: const Border(
                bottom: BorderSide(color: MadarColors.border),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.purchaseId != null
                          ? 'تعديل فاتورة مشتريات'
                          : 'فاتورة مشتريات جديدة',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: MadarColors.textLight,
                      ),
                    ),
                    const Gap(2),
                    Row(
                      children: [
                        Text(
                          'رقم الفاتورة: ${_invoiceNumber ?? '...'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: MadarColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•  ${DateFormat('yyyy/MM/dd HH:mm').format(_purchaseDate)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: MadarColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: MadarColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: MadarColors.gold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_bag_outlined, size: 14, color: MadarColors.gold),
                      SizedBox(width: 4),
                      Text(
                        'مشتريات',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: MadarColors.gold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Supplier selection and Purchase Date
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 44,
                        child: DropdownButtonFormField<Supplier>(
                          initialValue: _selectedSupplier,
                          dropdownColor: MadarColors.bgCard,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: 'اختر المورد',
                            labelStyle: const TextStyle(color: MadarColors.textSecondary, fontSize: 12),
                            filled: true,
                            fillColor: MadarColors.bgDark.withValues(alpha: 0.6),
                            prefixIcon: const Icon(Icons.business_outlined, color: MadarColors.gold, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: MadarColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: MadarColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: MadarColors.gold, width: 1.5),
                            ),
                          ),
                          items: _suppliers.map((supplier) {
                            return DropdownMenuItem(
                              value: supplier,
                              child: Text(
                                supplier.name,
                                style: const TextStyle(color: MadarColors.textLight, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: widget.purchaseId != null
                              ? null
                              : (supplier) {
                                  setState(() {
                                    _selectedSupplier = supplier;
                                  });
                                },
                        ),
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: _pickPurchaseDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: MadarColors.bgDark.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: MadarColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 16, color: MadarColors.gold),
                              const Gap(6),
                              Expanded(
                                child: Text(
                                  DateFormat('yyyy/MM/dd HH:mm').format(_purchaseDate),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: MadarColors.textLight,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.edit_calendar_outlined, size: 14, color: MadarColors.textMuted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(4),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('سيتم إضافة صفحة إضافة مورد'),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline, size: 14, color: MadarColors.gold),
                          SizedBox(width: 4),
                          Text(
                            'إضافة مورد جديد',
                            style: TextStyle(color: MadarColors.gold, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: MadarColors.border),

          // Order lines
          Expanded(
            child: _productEntries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 44,
                          color: MadarColors.textMuted.withValues(alpha: 0.35),
                        ),
                        const Gap(8),
                        const Text(
                          'لا توجد منتجات مضافة في الفاتورة',
                          style: TextStyle(
                            color: MadarColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        const Gap(4),
                        const Text(
                          'اختر المنتجات من القائمة المجاورة لإضافتها',
                          style: TextStyle(
                            color: MadarColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    itemCount: _productEntries.length,
                    itemBuilder: (context, index) {
                      final entry = _productEntries[index];
                      return OrderLineItem(
                        entry: entry,
                        index: index,
                        onEdit: (updatedEntry) =>
                            _updateProductEntry(index, updatedEntry),
                        onDelete: () => _removeProductEntry(index),
                      );
                    },
                  ),
          ),

          // Bottom docked totals and actions section
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MadarColors.bgDark.withValues(alpha: 0.8),
              border: const Border(
                top: BorderSide(color: MadarColors.border),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Totals box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: MadarColors.bgCard,
                    border: Border.all(color: MadarColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      _buildTotalRow(
                        'الإجمالي الفرعي:',
                        _subtotal.toStringAsFixed(2),
                      ),
                      const Divider(color: MadarColors.border, height: 10),
                      _buildTotalRow(
                        'المدفوع:',
                        _paidAmountController.text.isEmpty
                            ? '0.00'
                            : _paidAmountController.text,
                      ),
                      const Divider(color: MadarColors.border, height: 10),
                      _buildTotalRow(
                        'المتبقي:',
                        _remainingAmount.toStringAsFixed(2),
                        isBold: true,
                        color: _remainingAmount > 0 ? MadarColors.warning : MadarColors.success,
                      ),
                    ],
                  ),
                ),

                const Gap(10),

                // Payment method & notes row
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: SizedBox(
                        height: 42,
                        child: DropdownButtonFormField<PaymentMethod>(
                          initialValue: _paymentMethod,
                          dropdownColor: MadarColors.bgCard,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: 'طريقة الدفع',
                            labelStyle: const TextStyle(color: MadarColors.textSecondary, fontSize: 11),
                            filled: true,
                            fillColor: MadarColors.bgCard,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: MadarColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: MadarColors.border),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: PaymentMethod.cash,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.payments_outlined, size: 16, color: MadarColors.success),
                                  SizedBox(width: 6),
                                  Text('كاش', style: TextStyle(color: MadarColors.textLight, fontSize: 12)),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: PaymentMethod.visa,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.credit_card_outlined, size: 16, color: MadarColors.info),
                                  SizedBox(width: 6),
                                  Text('فيزا', style: TextStyle(color: MadarColors.textLight, fontSize: 12)),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: PaymentMethod.transfer,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.account_balance_outlined, size: 16, color: MadarColors.warning),
                                  SizedBox(width: 6),
                                  Text('تحويل بنكي', style: TextStyle(color: MadarColors.textLight, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (method) {
                            setState(() {
                              _paymentMethod = method!;
                            });
                          },
                        ),
                      ),
                    ),
                    if (_paymentMethod != PaymentMethod.cash) ...[
                      const Gap(8),
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 42,
                          child: TextFormField(
                            controller: _paidAmountController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: MadarColors.textLight, fontSize: 12),
                            decoration: InputDecoration(
                              labelText: 'المدفوع',
                              labelStyle: const TextStyle(color: MadarColors.textSecondary, fontSize: 11),
                              filled: true,
                              fillColor: MadarColors.bgCard,
                              prefixText: 'ج.م ',
                              prefixStyle: const TextStyle(color: MadarColors.gold, fontSize: 11),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: MadarColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: MadarColors.border),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const Gap(8),

                // Notes
                SizedBox(
                  height: 38,
                  child: TextFormField(
                    controller: _notesController,
                    style: const TextStyle(color: MadarColors.textLight, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'ملاحظات',
                      labelStyle: const TextStyle(color: MadarColors.textSecondary, fontSize: 11),
                      hintText: 'ملاحظات الفاتورة...',
                      hintStyle: const TextStyle(color: MadarColors.textMuted, fontSize: 11),
                      filled: true,
                      fillColor: MadarColors.bgCard,
                      prefixIcon: const Icon(Icons.note_alt_outlined, color: MadarColors.textMuted, size: 16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: MadarColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: MadarColors.border),
                      ),
                    ),
                  ),
                ),

                const Gap(10),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: _savePurchaseInvoice,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text(
                          'حفظ والطباعة',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MadarColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: _resetForm,
                        icon: const Icon(Icons.clear, size: 18, color: MadarColors.error),
                        label: const Text(
                          'مسح',
                          style: TextStyle(
                            color: MadarColors.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: MadarColors.error.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 13 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? MadarColors.textLight : MadarColors.textSecondary,
            ),
          ),
          Text(
            '$value ج.م',
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? (isBold ? MadarColors.goldLight : MadarColors.textLight),
            ),
          ),
        ],
      ),
    );
  }
}
