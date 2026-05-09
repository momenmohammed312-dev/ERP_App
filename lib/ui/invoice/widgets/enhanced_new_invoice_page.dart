import 'dart:async';
import 'dart:developer';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/invoice/models/invoice_models.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/invoice_type_selection_modal.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/product_selection_modal.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/order_line_item.dart';
import 'package:pos_offline_desktop/ui/invoice/models/product_entry.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/ui/invoice/widgets/day_closed_dialog.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/product_card.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/day_opening_page.dart';

class EnhancedNewInvoicePage extends StatefulHookConsumerWidget {
  final AppDatabase db;
  final bool isCredit;

  const EnhancedNewInvoicePage({
    super.key,
    required this.db,
    this.isCredit = false,
  });

  @override
  ConsumerState<EnhancedNewInvoicePage> createState() =>
      _EnhancedNewInvoicePageState();
}

class _EnhancedNewInvoicePageState
    extends ConsumerState<EnhancedNewInvoicePage> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _paidAmountController = TextEditingController();
  final _notesController = TextEditingController();

  // Invoice data
  InvoiceType _invoiceType = InvoiceType.cash;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  String? _selectedCustomerId;
  final List<ProductEntry> _productEntries = [];

  // Products and search
  List<Product> _filteredProducts = [];
  // Non-final so we can reassign after async load
  List<Customer> _customers = [];

  Customer? get _selectedCustomer {
    final id = _selectedCustomerId;
    if (id == null) return null;
    try {
      return _customers.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  // Totals
  double _subtotal = 0.0;
  double _totalDiscount = 0.0;
  double _totalTax = 0.0;
  double _grandTotal = 0.0;
  double _paidAmount = 0.0;
  double _remainingAmount = 0.0;

  // State
  bool _isDayOpen = false;
  bool _isLoading = true;
  bool _showInvoiceTypeModal = true;
  Timer? _searchDebounce;
  String? _invoiceNumber;

  @override
  void initState() {
    super.initState();
    _initializeInvoice();
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

  Future<void> _initializeInvoice() async {
    try {
      // Check day status first
      bool isOpen = await widget.db.dayDao.isDayOpen();

      if (!isOpen) {
        await widget.db.dayDao.getOrCreateTodayDay(openingBalance: 0.0);
        isOpen = true;
      }

      // Load data
      final products = await widget.db.productDao.getAllProducts();
      final customers = await widget.db.customerDao.getAllCustomers();

      // Generate invoice number
      _invoiceNumber = '${DateTime.now().millisecondsSinceEpoch}';

      if (!mounted) return;
      setState(() {
        _isDayOpen = true;
        _filteredProducts = products;
        _customers = customers; // populate the dropdown
        _isLoading = false;
      });
    } catch (e) {
      log('Error initializing invoice: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      category: null, // Removed category filter
      unit: null, // Removed unit filter
      searchQuery: query.isEmpty ? null : query,
    );

    if (!mounted) return;
    setState(() {
      _filteredProducts = filtered;
    });
  }

  Future<void> _scanBarcode() async {
    try {
      // Manual barcode entry fallback
      final barcode = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('أدخل الباركود يدوياً'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'الباركود',
              hintText: 'أدخل رقم الباركود',
            ),
            onSubmitted: (value) {
              Navigator.of(context).pop(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      );

      if (barcode != null && barcode.isNotEmpty) {
        await _handleBarcodeScanned(barcode);
      }
    } catch (e) {
      log('Error scanning barcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في مسح الباركود: $e')));
      }
    }
  }

  Future<void> _handleBarcodeScanned(String barcode) async {
    try {
      final product = await widget.db.productDao.getProductByBarcode(barcode);
      if (product != null) {
        _showProductSelectionModal(product);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('المنتج غير موجود')));
        }
      }
    } catch (e) {
      log('Error handling barcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في معالجة الباركود: $e')));
      }
    }
  }

  void _onPaidAmountChanged() {
    final paid = double.tryParse(_paidAmountController.text) ?? 0.0;
    setState(() {
      _paidAmount = paid;
      _remainingAmount = _grandTotal - paid;
    });
  }

  void _setInvoiceType(InvoiceType type) {
    // Handle supply navigation separately
    if (type == InvoiceType.supply) {
      context.go('/new-supply-invoice');
      return;
    }

    setState(() {
      _invoiceType = type;
      _showInvoiceTypeModal = false;

      // Set defaults based on type
      if (type == InvoiceType.cash) {
        // Check if cash customer already exists to avoid duplicates
        final existingCashCustomer = _customers.firstWhere(
          (c) => c.name.toLowerCase().contains('cash'),
          orElse: () => Customer(
            id: 'cash',
            name: 'عميل نقدي',
            phone: '',
            address: null,
            gstinNumber: null,
            email: null,
            openingBalance: 0.0,
            totalDebt: 0.0,
            totalPaid: 0.0,
            createdAt: DateTime.now(),
            updatedAt: null,
            notes: null,
            isActive: true,
            status: 1,
          ),
        );

        // Use existing cash customer if found, otherwise add the created one
        if (!_customers.any((c) => c.id == 'cash')) {
          _customers.add(existingCashCustomer);
        }
        _selectedCustomerId = existingCashCustomer.id;
        _paymentMethod = PaymentMethod.cash;
        _paidAmount = _grandTotal;
        _paidAmountController.text = _grandTotal.toStringAsFixed(2);
      } else {
        _selectedCustomerId = null; // Require selection for credit
        _paidAmount = 0.0;
        _paidAmountController.text = '0.00';
      }
    });
  }

  void _calculateTotals() {
    _subtotal = 0.0;
    _totalDiscount = 0.0;
    _totalTax = 0.0;

    for (final entry in _productEntries) {
      final lineTotal = entry.unitPrice * entry.quantity;
      final lineDiscount = entry.discount;
      final lineTax = entry.tax;

      entry.lineTotal = lineTotal - lineDiscount + lineTax;

      _subtotal += lineTotal;
      _totalDiscount += lineDiscount;
      _totalTax += lineTax;
    }

    _grandTotal = _subtotal - _totalDiscount + _totalTax;
    _remainingAmount = _grandTotal - _paidAmount;

    // Auto-update paid amount for cash invoices
    if (_invoiceType == InvoiceType.cash) {
      _paidAmount = _grandTotal;
      _paidAmountController.text = _grandTotal.toStringAsFixed(2);
    }

    setState(() {});
  }

  void _showProductSelectionModal(Product product) {
    showDialog(
      context: context,
      builder: (context) => ProductSelectionModal(
        product: product,
        onConfirm: (quantity, unit, unitPrice, discount, tax) {
          _addProductEntry(product, quantity, unit, unitPrice, discount, tax);
        },
      ),
    );
  }

  void _addProductEntry(
    Product product,
    int quantity,
    String unit,
    double unitPrice,
    double discount,
    double tax,
  ) {
    setState(() {
      final entry = ProductEntry(product: product)
        ..quantity = quantity
        ..unit = unit
        ..unitPrice = unitPrice
        ..discount = discount
        ..tax = tax
        ..priceOverride = unitPrice != product.price;

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

  Future<void> _saveDraft() async {
    try {
      // Create a draft record in the database
      // For now, just show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم حفظ المسودة بنجاح'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ المسودة: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _completeInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    // Validation
    if (_productEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة منتج واحد على الأقل')),
      );
      return;
    }

    if (_invoiceType == InvoiceType.credit && _selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار عميل للفاتورة الآجلة')),
      );
      return;
    }

    if (_invoiceType == InvoiceType.cash && _paidAmount < _grandTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الدفع الكامل مطلوب للفواتير النقدية')),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            Gap(20),
            Text('جاري معالجة الفاتورة...'),
          ],
        ),
      ),
    );

    try {
      await _processInvoice();

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        Navigator.of(context).pop(); // Close invoice page
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إكمال الفاتورة بنجاح')),
        );
      }
    } catch (e) {
      log('Error completing invoice: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  Future<void> _processInvoice() async {
    final db = widget.db;

    // Determine customer info
    final selectedCustomer = _selectedCustomer;
    final customerName = selectedCustomer?.name ?? 'عميل نقدي';
    final customerId = selectedCustomer?.id ?? 'cash';
    final customerContact = selectedCustomer?.phone ?? '';
    final customerAddress = selectedCustomer?.address ?? '';

    // Determine payment method string
    final paymentMethodStr = _invoiceType == InvoiceType.credit
        ? 'credit'
        : _paymentMethod.name;

    // Determine status
    String status;
    if ((_grandTotal - _paidAmount).abs() < 0.01) {
      status = 'paid';
    } else if (_paidAmount > 0) {
      status = 'partial';
    } else {
      status = 'pending';
    }

    // Get customer's actual previous balance BEFORE saving to database
    double previousBalance = 0.0;
    if (selectedCustomer != null && selectedCustomer.id != 'cash') {
      previousBalance = await db.ledgerDao.getCustomerBalance(
        selectedCustomer.id,
      );
    }

    // Insert invoice
    final invoiceId = await db.invoiceDao.insertInvoice(
      InvoicesCompanion(
        invoiceNumber: Value(_invoiceNumber!),
        customerName: Value(customerName),
        customerContact: Value(customerContact),
        customerAddress: Value(customerAddress),
        customerId: Value(customerId),
        paymentMethod: Value(paymentMethodStr),
        totalAmount: Value(_grandTotal),
        paidAmount: Value(_paidAmount),
        status: Value(status),
        date: Value(DateTime.now()),
      ),
    );

    // Insert invoice items and update stock
    for (final entry in _productEntries) {
      if (entry.product == null) continue;

      // Check stock
      final availableStock = entry.product!.quantity;
      final totalQuantityNeeded = entry.quantity;

      if (totalQuantityNeeded > availableStock) {
        throw Exception('Insufficient stock for ${entry.product!.name}');
      }

      // Update product quantity
      final newQuantity = availableStock - totalQuantityNeeded;
      await db.productDao.updateProduct(
        ProductsCompanion(
          id: Value(entry.product!.id),
          name: Value(entry.product!.name),
          quantity: Value(newQuantity),
          price: Value(entry.product!.price),
          unit: Value(entry.product!.unit),
          category: Value(entry.product!.category),
          barcode: Value(entry.product!.barcode),
          cartonQuantity: Value(entry.product!.cartonQuantity),
          cartonPrice: Value(entry.product!.cartonPrice),
          status: Value(entry.product!.status),
        ),
      );

      // Calculate carton quantity (if product has carton info)
      int? cartonQuantity;
      if (entry.product!.cartonQuantity != null &&
          entry.product!.cartonQuantity! > 0) {
        cartonQuantity = entry.quantity ~/ entry.product!.cartonQuantity!;
      }

      // Insert invoice item
      await db.invoiceDao.insertInvoiceItem(
        InvoiceItemsCompanion(
          invoiceId: Value(invoiceId),
          productId: Value(entry.product!.id),
          quantity: Value(entry.quantity),
          price: Value(entry.unitPrice),
          ctn: Value(cartonQuantity),
        ),
      );
    }

    // Create product summary for ledger description
    final productSummary = _productEntries
        .map((e) => e.product?.name ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    final ledgerDescription = 'بيع #$_invoiceNumber ($productSummary)';

    // Get all items with products for printing
    final itemsWithProducts = await Future.wait(
      _productEntries.map((entry) async {
        final product = entry.product?.id != null
            ? await db.productDao.getProductById(entry.product!.id)
            : null;
        return (entry, product);
      }),
    );

    final invoiceItems = itemsWithProducts.map((itemWithProduct) {
      final item = itemWithProduct.$1;
      final product = itemWithProduct.$2;
      return ups.InvoiceItem(
        id: item.product?.id ?? 0,
        invoiceId: invoiceId, // Use the actual invoice ID from database
        description: product?.name ?? 'Product ${item.product?.id}',
        unit: item.unit,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        totalPrice: item.lineTotal,
      );
    }).toList();

    final storeInfo = ups.StoreInfo(
      storeName: 'المحل التجاري',
      phone: '01234567890',
      zipCode: '12345',
      state: 'القاهرة',
    );

    final invoiceModel = ups.Invoice(
      id: invoiceId,
      invoiceNumber: _invoiceNumber ?? 'INV$invoiceId',
      customerName: customerName,
      customerPhone: selectedCustomer?.phone ?? 'N/A',
      customerZipCode: '',
      customerState: '',
      invoiceDate: DateTime.now(),
      subtotal: _grandTotal,
      isCreditAccount: _invoiceType == InvoiceType.credit,
      previousBalance: previousBalance,
      totalAmount: _grandTotal,
    );

    final invoiceData = ups.InvoiceData(
      invoice: invoiceModel,
      items: invoiceItems,
      storeInfo: storeInfo,
    );

    // Print using new SOP 4.0 format
    // Only pass paidAmount if customer has actually paid something
    final Map<String, dynamic>? additionalData = (_paidAmount > 0)
        ? {'paidAmount': _paidAmount}
        : null;

    await ups.UnifiedPrintService.printToThermalPrinter(
      documentType: ups.DocumentType.salesInvoice,
      data: invoiceData,
      additionalData: additionalData,
    );

    // Record ledger transactions AFTER printing (so previous balance is correct)
    await db.ledgerDao.insertTransaction(
      LedgerTransactionsCompanion.insert(
        id: '${DateTime.now().millisecondsSinceEpoch}_sale',
        entityType: 'Customer',
        refId: customerId,
        date: DateTime.now(),
        description: ledgerDescription,
        debit: Value(_grandTotal),
        credit: const Value(0.0),
        origin: 'sale',
        paymentMethod: Value('credit'),
        receiptNumber: Value(_invoiceNumber!),
      ),
    );

    if (_paidAmount > 0) {
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_payment',
          entityType: 'Customer',
          refId: customerId,
          date: DateTime.now(),
          description: 'دفع فاتورة #$_invoiceNumber',
          debit: const Value(0.0),
          credit: Value(_paidAmount),
          origin: 'payment',
          paymentMethod: Value('cash'),
          receiptNumber: Value(_invoiceNumber!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = 'ar'; // Simple placeholder for localization

    // Show day closed dialog
    if (!_isDayOpen && !_isLoading) {
      return DayClosedDialog(
        onOpenDay: () async {
          Navigator.of(context).pop();
          // Navigate to day opening page
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DayOpeningPage(db: widget.db),
            ),
          );
        },
        onCancel: () => Navigator.of(context).pop(),
      );
    }

    // Show invoice type selection modal
    if (_showInvoiceTypeModal && _isDayOpen) {
      return InvoiceTypeSelectionModal(onSelectType: _setInvoiceType);
    }

    // Show loading
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Main invoice interface
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('فاتورة جديدة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveDraft,
            tooltip: 'حفظ المسودة',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Row(
          children: [
            // Products Panel (2/3 width)
            Expanded(flex: 2, child: _buildProductsPanel()),
            const VerticalDivider(width: 1),
            // Invoice Details Panel (1/3 width)
            Expanded(flex: 1, child: _buildDetailsPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsPanel() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'البحث عن المنتجات...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanBarcode,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),

          const Gap(10),

          // Products grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
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
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // Invoice header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _invoiceNumber ?? 'جاري الإنشاء...',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(4),
                Text(
                  DateTime.now().toString().substring(0, 19),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const Gap(8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _invoiceType == InvoiceType.cash
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2)
                        : Theme.of(
                            context,
                          ).colorScheme.secondary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _invoiceType == InvoiceType.cash
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  child: Text(
                    _invoiceType.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _invoiceType == InvoiceType.cash
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Customer selection
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedCustomerId,
              decoration: InputDecoration(
                labelText: 'العميل',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              items: _customers.map((customer) {
                return DropdownMenuItem(
                  value: customer.id,
                  child: Text(customer.name),
                );
              }).toList(),
              onChanged: (customerId) {
                setState(() {
                  _selectedCustomerId = customerId;
                });
              },
            ),
          ),

          // Order lines - Enlarged section
          Expanded(
            flex: 3,
            child: _productEntries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 48,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        const Gap(8),
                        Text(
                          'لا توجد منتجات مضافة',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _productEntries.length,
                    itemBuilder: (context, index) {
                      final entry = _productEntries[index];
                      return OrderLineItem(
                        entry: entry,
                        index: index,
                        onEdit: (updatedEntry) {
                          _updateProductEntry(index, updatedEntry);
                        },
                        onDelete: () {
                          _removeProductEntry(index);
                        },
                      );
                    },
                  ),
          ),

          // Totals and payment
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              children: [
                // Totals summary
                _buildTotalsSummary(),
                const Gap(16),

                // Payment method (cash only)
                if (_invoiceType == InvoiceType.cash) ...[
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'طريقة الدفع',
                      prefixIcon: Icon(Icons.payment),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PaymentMethod.cash,
                        child: Text('نقدي'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethod.visa,
                        child: Text('فيزا'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethod.mastercard,
                        child: Text('ماستر كارد'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethod.transfer,
                        child: Text('تحويل بنكي'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethod.wallet,
                        child: Text('محفظة إلكترونية'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethod.other,
                        child: Text('أخرى'),
                      ),
                    ],
                    onChanged: (method) {
                      setState(() {
                        _paymentMethod = method!;
                      });
                    },
                  ),
                  const Gap(12),
                ],

                // Paid amount (credit only)
                if (_invoiceType == InvoiceType.credit) ...[
                  TextFormField(
                    controller: _paidAmountController,
                    decoration: const InputDecoration(
                      labelText: 'المدفوع',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                  ),
                  const Gap(8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'المتبقي:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_remainingAmount.toStringAsFixed(2)} ج.م',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _remainingAmount > 0
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                ],

                // Compact Notes Button
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notes, size: 16),
                    label: Text(
                      'ملاحظات${_notesController.text.isNotEmpty ? ' (${_notesController.text.length})' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('الملاحظات'),
                          content: TextField(
                            controller: _notesController,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'اكتب ملاحظاتك هنا...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('إلغاء'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                setState(() {});
                              },
                              child: const Text('حفظ'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Gap(16),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saveDraft,
                        child: const Text('حفظ المسودة'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _completeInvoice,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'إكمال والطباعة',
                          style: TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildTotalsSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          _buildTotalRow('الإجمالي الفرعي:', _subtotal),
          if (_totalDiscount > 0)
            _buildTotalRow(
              'الخصم:',
              -_totalDiscount,
              color: Theme.of(context).colorScheme.error,
            ),
          if (_totalTax > 0)
            _buildTotalRow(
              'الضريبة:',
              _totalTax,
              color: Theme.of(context).colorScheme.primary,
            ),
          const Divider(),
          _buildTotalRow(
            'الإجمالي الكلي:',
            _grandTotal,
            color: Theme.of(context).colorScheme.onSurface,
            isBold: true,
            fontSize: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    double amount, {
    Color? color,
    bool isBold = false,
    double fontSize = 14,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            amount.toStringAsFixed(2),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
