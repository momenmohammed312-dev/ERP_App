import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/invoice/models/invoice_models.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/invoice_type_selection_modal.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/product_selection_modal.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/order_line_item.dart';
import 'package:pos_offline_desktop/ui/invoice/models/product_entry.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/ui/invoice/widgets/day_closed_dialog.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/product_card.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/day_opening_page.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';

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

  void _showBusinessSetupRequired(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(children: [
            Icon(Icons.business, color: Color(0xFFC9A84C)),
            SizedBox(width: 8),
            Text('بيانات المنشأة مطلوبة'),
          ]),
          content: const Text(
            'يرجى إدخال بيانات المنشأة أولاً من شاشة الإعدادات قبل إنشاء الفواتير.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );
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
      // Check business info first
      final bizName = await SettingsService.getBusinessName();
      if (bizName == 'المحل التجاري' || bizName.isEmpty) {
        if (mounted) {
          _showBusinessSetupRequired(context);
        }
        return;
      }

      // Check day status first
      bool isOpen = await widget.db.dayDao.isDayOpen();

      if (!isOpen) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'يجب فتح اليوم أولاً من تبويب الكاشير',
              ),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
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
    final needsPriceOverride = unitPrice != product.price;
    if (needsPriceOverride) {
      final currentUser = ref.read(authProvider);
      if (currentUser == null || !currentUser.hasPermission(Permission.editSale)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'لا تملك صلاحية تعديل السعر. تم استخدام السعر الافتراضي.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        unitPrice = product.price;
      }
    }

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
    if (_productEntries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى إضافة منتج واحد على الأقل لحفظ المسودة'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      final db = widget.db;
      final now = DateTime.now();
      final draftNumber = _invoiceNumber ?? 'DRAFT_${now.millisecondsSinceEpoch}';
      final customerName = _selectedCustomer?.name ?? 'عميل نقدي';

      final invoiceId = await db.invoiceDao.insertInvoice(
        InvoicesCompanion(
          invoiceNumber: Value(draftNumber),
          customerId: Value(_selectedCustomerId),
          customerName: Value(customerName),
          customerContact: Value(_selectedCustomer?.phone ?? ''),
          customerAddress: Value(_selectedCustomer?.address ?? ''),
          paymentMethod: Value(_invoiceType == InvoiceType.credit ? 'credit' : _paymentMethod.name),
          totalAmount: Value(_grandTotal),
          paidAmount: Value(_paidAmount),
          date: Value(now),
          status: const Value('draft'),
        ),
      );

      for (final entry in _productEntries) {
        if (entry.product == null) continue;
        await db.invoiceDao.insertInvoiceItem(
          InvoiceItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(entry.product!.id),
            quantity: Value(entry.quantity),
            price: Value(entry.unitPrice),
            discount: Value(entry.discount),
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم حفظ المسودة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ المسودة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAddExpenseDialog() {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String category = 'other_expenses';
    String paymentMethod = 'cash';
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('مصروف جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'البيان *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'المبلغ *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'rent', child: Text('إيجار')),
                    DropdownMenuItem(value: 'electricity', child: Text('كهرباء')),
                    DropdownMenuItem(value: 'water', child: Text('مياه')),
                    DropdownMenuItem(value: 'internet', child: Text('نت')),
                    DropdownMenuItem(value: 'salaries', child: Text('مرتبات')),
                    DropdownMenuItem(value: 'maintenance', child: Text('صيانة')),
                    DropdownMenuItem(value: 'marketing', child: Text('تسويق')),
                    DropdownMenuItem(value: 'other_expenses', child: Text('أخرى')),
                  ],
                  onChanged: (v) => setDialogState(() => category = v ?? 'other_expenses'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(labelText: 'طريقة الدفع', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                    DropdownMenuItem(value: 'card', child: Text('بطاقة')),
                    DropdownMenuItem(value: 'bank', child: Text('تحويل بنكي')),
                  ],
                  onChanged: (v) => setDialogState(() => paymentMethod = v ?? 'cash'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (descCtrl.text.isEmpty || amountCtrl.text.isEmpty) return;
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) return;

                try {
                  final db = widget.db;
                  final isOpen = await db.dayDao.isDayOpen();
                  if (!isOpen) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('يجب فتح اليوم أولاً'), backgroundColor: Colors.red),
                      );
                    }
                    return;
                  }
                  final now = DateTime.now();
                  final expenseId = '${now.millisecondsSinceEpoch}_expense';
                  await db.expenseDao.insertExpense(
                    ExpensesCompanion.insert(
                      id: expenseId,
                      description: descCtrl.text,
                      amount: amount,
                      category: category,
                      date: Value(now),
                      paymentMethod: Value(paymentMethod),
                    ),
                  );
                  await db.ledgerDao.insertTransaction(
                    LedgerTransactionsCompanion.insert(
                      id: '${now.millisecondsSinceEpoch}_ledger_expense',
                      entityType: 'Expense',
                      refId: 'general_expense',
                      date: now,
                      description: '$category: ${descCtrl.text}',
                      debit: const Value(0.0),
                      credit: Value(amount),
                      origin: 'expense',
                      paymentMethod: Value(paymentMethod),
                    ),
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم إضافة المصروف'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
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

    // Build invoice items for service
    final items = _productEntries
        .where((e) => e.product != null)
        .map((e) {
          int? ctn;
          if (e.product!.cartonQuantity != null &&
              e.product!.cartonQuantity! > 0) {
            ctn = e.quantity ~/ e.product!.cartonQuantity!;
          }
          return InvoiceItemParams(
            productId: e.product!.id,
            quantity: e.quantity,
            price: e.unitPrice,
            ctn: ctn,
            discount: e.discount,
          );
        }).toList();

    final productSummary = _productEntries
        .map((e) => e.product?.name ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    final ledgerDescription = 'بيع #$_invoiceNumber ($productSummary)';

    final result = await InvoiceService(db).createInvoice(
      customerId: customerId == 'cash' ? null : customerId,
      customerName: customerName,
      customerContact: customerContact,
      customerAddress: customerAddress,
      paymentMethod: paymentMethodStr,
      totalAmount: _grandTotal,
      paidAmount: _paidAmount,
      status: status,
      invoiceNumber: _invoiceNumber,
      items: items,
      ledgerDescription: ledgerDescription,
    );

    final invoiceId = result.invoiceId;

    // Build print data
    final invoiceItems = _productEntries
        .where((e) => e.product != null)
        .map((e) => ups.InvoiceItem(
              id: e.product!.id,
              invoiceId: invoiceId,
              description: e.product!.name,
              unit: e.unit,
              quantity: e.quantity,
              unitPrice: e.unitPrice,
              totalPrice: e.lineTotal,
            ))
        .toList();

    final storeInfo = ups.StoreInfo(
      storeName: await SettingsService.getBusinessName(),
      phone: await SettingsService.getBusinessPhone(),
      zipCode: '',
      state: await SettingsService.getBusinessAddress(),
      taxNumber: await SettingsService.getTaxNumber(),
      logoPath: await SettingsService.getBusinessLogoPath(),
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
      paidAmount: _paidAmount,
    );

    final invoiceData = ups.InvoiceData(
      invoice: invoiceModel,
      items: invoiceItems,
      storeInfo: storeInfo,
    );

    final Map<String, dynamic>? additionalData = (_paidAmount > 0)
        ? {
            'paidAmount': _paidAmount,
            'creditAmount': _grandTotal - _paidAmount,
          }
        : null;

    await ups.UnifiedPrintService.printToThermalPrinter(
      documentType: ups.DocumentType.salesInvoice,
      data: invoiceData,
      additionalData: additionalData,
    );
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

                // Quick expense button
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _showAddExpenseDialog,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('إضافة مصروف جديد'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[700],
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                  ),
                ),
                const Gap(12),

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
