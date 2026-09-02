import 'dart:async';
import 'dart:developer';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/accounting_service.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/ui/invoice/widgets/day_closed_dialog.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/product_card.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/product_selection_modal.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/order_line_item.dart';
import 'package:pos_offline_desktop/ui/invoice/models/product_entry.dart';
import 'product_quick_add_dialog.dart';

// Payment method enum
enum PaymentMethod { cash, visa, mastercard, transfer, wallet, other }

class EnhancedPurchaseInvoicePage extends StatefulHookConsumerWidget {
  final AppDatabase db;

  const EnhancedPurchaseInvoicePage({super.key, required this.db});

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
  final List<ProductEntry> _productEntries = [];

  // Products and search
  List<Product> _filteredProducts = [];
  List<Supplier> _suppliers = [];

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

      // Generate invoice number
      _invoiceNumber = 'PUR-${DateTime.now().millisecondsSinceEpoch}';

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
        forPurchase: true,
        onConfirm: (quantity, unit, unitPrice, discount, tax) {
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

    if (_productEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة منتج واحد على الأقل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await widget.db.transaction(() async {
        // Create purchase invoice
        final purchaseInvoice = PurchasesCompanion.insert(
          id: _invoiceNumber!,
          invoiceNumber: _invoiceNumber!,
          description: 'فاتورة مشتريات من ${_selectedSupplier!.name}',
          totalAmount: _grandTotal,
          purchaseDate: DateTime.now(),
          createdAt: DateTime.now(),
          supplierId: Value(_selectedSupplier!.id),
          paidAmount: Value(_paidAmount),
          paymentMethod: Value(_paymentMethod.name),
          status: Value('completed'),
        );

        await widget.db.into(widget.db.purchases).insert(purchaseInvoice);

        // Add purchase items + update inventory
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

          final currentProduct = entry.product!;
          final updatedProduct = currentProduct.copyWith(
            quantity: currentProduct.quantity + entry.quantity,
          );
          await widget.db.productDao.updateProduct(updatedProduct);
        }

        // Supplier subledger (unchanged)
        if (_paymentMethod != PaymentMethod.cash && _remainingAmount > 0) {
          await widget.db.ledgerDao.insertTransaction(
            LedgerTransactionsCompanion.insert(
              id: '${_invoiceNumber}_ledger',
              entityType: 'Supplier',
              refId: _selectedSupplier!.id,
              date: DateTime.now(),
              description: 'شراء آجل: فاتورة $_invoiceNumber',
              debit: const Value(0.0),
              credit: Value(_remainingAmount),
              origin: 'purchase',
            ),
          );
        }

        // ── Headless Accounting: Journal (Phase 3) ──
        final accounting = AccountingService(widget.db);
        Future<String> accId(String code) async {
          final a = await widget.db.accountsDao.getByCode(code);
          if (a == null) throw Exception('Account $code not found — v57 migration missing');
          return a.id;
        }

        final inventoryId = await accId('1200');
        final cashId = await accId('1000');
        final bankId = await accId('1010');
        final apId = await accId('2000');
        final isCash = _paymentMethod == PaymentMethod.cash;
        final cashOrBankId = isCash ? cashId : bankId;

        if (!isCash && _remainingAmount > 0 && _paidAmount > 0) {
          // Partial: Debit Inventory total, Credit AP remaining + Credit Cash/Bank paid
          await widget.db.journalDao.insertBalancedEntry(
            postingKey: 'purchase:PUR$_invoiceNumber',
            date: DateTime.now(),
            description: 'مشتريات فاتورة $_invoiceNumber من ${_selectedSupplier!.name}',
            sourceType: 'purchase',
            sourceId: _invoiceNumber!,
            lines: [
              JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: inventoryId, debit: Value(_grandTotal), credit: const Value(0)),
              JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: apId, debit: const Value(0), credit: Value(_remainingAmount)),
              JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: cashOrBankId, debit: const Value(0), credit: Value(_paidAmount)),
            ],
          );
        } else if (!isCash && _remainingAmount > 0) {
          // Fully credit
          await accounting.postPurchase(
            sourceId: _invoiceNumber!,
            date: DateTime.now(),
            totalAmount: _grandTotal,
            inventoryAccountId: inventoryId,
            creditAccountId: apId,
            description: 'مشتريات فاتورة $_invoiceNumber من ${_selectedSupplier!.name}',
          );
        } else {
          // Fully cash (or cash-like)
          await accounting.postPurchase(
            sourceId: _invoiceNumber!,
            date: DateTime.now(),
            totalAmount: _grandTotal,
            inventoryAccountId: inventoryId,
            creditAccountId: cashOrBankId,
            description: 'مشتريات فاتورة $_invoiceNumber من ${_selectedSupplier!.name}',
          );
        }
      });

      // Print invoice (outside transaction)
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
        invoiceDate: DateTime.now(),
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
      _productEntries.clear();
      _paidAmountController.clear();
      _notesController.clear();
      _paymentMethod = PaymentMethod.cash;
      _calculateTotals();
      _invoiceNumber = 'PUR-${DateTime.now().millisecondsSinceEpoch}';
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
      appBar: AppBar(
        title: Text('فاتورة مشتريات جديدة #$_invoiceNumber'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
          tooltip: 'رجوع',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _savePurchaseInvoice,
            tooltip: 'حفظ الفاتورة',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Row(
          children: [
            // Left side - Invoice details
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Invoice header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'فاتورة مشتريات',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const Gap(8),
                          Text(
                            'رقم الفاتورة: $_invoiceNumber',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                          ),
                          Text(
                            'التاريخ: ${DateTime.now().toString().split(' ')[0]}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                          ),
                        ],
                      ),
                    ),

                    const Gap(16),

                    // Supplier selection
                    DropdownButtonFormField<Supplier>(
                      initialValue: _selectedSupplier,
                      decoration: const InputDecoration(
                        labelText: 'اختر المورد',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      items: _suppliers.map((supplier) {
                        return DropdownMenuItem(
                          value: supplier,
                          child: Text(supplier.name),
                        );
                      }).toList(),
                      onChanged: (supplier) {
                        setState(() {
                          _selectedSupplier = supplier;
                        });
                      },
                    ),

                    const Gap(8),

                    // Add new supplier button
                    TextButton.icon(
                      onPressed: () {
                        // Navigate to add supplier page
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('سيتم إضافة صفحة إضافة مورد'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة مورد جديد'),
                    ),

                    const Gap(16),

                    // Product entries
                    Expanded(
                      child: _productEntries.isEmpty
                          ? const Center(
                              child: Text(
                                'لا توجد منتجات مضافة',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
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

                    // Totals
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildTotalRow(
                            'الإجمالي الفرعي:',
                            _subtotal.toStringAsFixed(2),
                          ),
                          _buildTotalRow(
                            'المدفوع:',
                            _paidAmountController.text.isEmpty
                                ? '0.00'
                                : _paidAmountController.text,
                          ),
                          _buildTotalRow(
                            'المتبقي:',
                            _remainingAmount.toStringAsFixed(2),
                            isBold: true,
                          ),
                        ],
                      ),
                    ),

                    const Gap(16),

                    // Payment method
                    DropdownButtonFormField<PaymentMethod>(
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الدفع',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: PaymentMethod.cash,
                          child: Text('كاش'),
                        ),
                        DropdownMenuItem(
                          value: PaymentMethod.visa,
                          child: Text('فيزا'),
                        ),
                        DropdownMenuItem(
                          value: PaymentMethod.transfer,
                          child: Text('تحويل بنكي'),
                        ),
                      ],
                      onChanged: (method) {
                        setState(() {
                          _paymentMethod = method!;
                        });
                      },
                    ),

                    const Gap(16),

                    // Paid amount field (only for non-cash)
                    if (_paymentMethod != PaymentMethod.cash) ...[
                      TextFormField(
                        controller: _paidAmountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'المدفوع',
                          border: OutlineInputBorder(),
                          prefixText: 'ج.م ',
                        ),
                      ),
                      const Gap(16),
                    ],

                    // Notes
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),

                    const Gap(16),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _savePurchaseInvoice,
                            icon: const Icon(Icons.save),
                            label: const Text('حفظ والطباعة'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const Gap(8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _resetForm,
                            icon: const Icon(Icons.clear),
                            label: const Text('مسح'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const VerticalDivider(width: 1),

            // Right side - Product selection
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search bar with quick add button
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              labelText: 'البحث عن المنتجات...',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                        const Gap(8),
                        ElevatedButton.icon(
                          onPressed: _showQuickAddProduct,
                          icon: const Icon(Icons.add),
                          label: const Text('منتج جديد'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Gap(16),

                    // Products grid
                    Expanded(
                      child: _filteredProducts.isEmpty
                          ? const Center(child: Text('لا توجد منتجات'))
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 0.8,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: _filteredProducts.length,
                              itemBuilder: (context, index) {
                                final product = _filteredProducts[index];
                                return ProductCard(
                                  product: product,
                                  onTap: () =>
                                      _showProductSelectionModal(product),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '$value ج.م',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
