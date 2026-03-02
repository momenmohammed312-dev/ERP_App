import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;

enum InvoiceType { cash, credit }

enum InvoiceStatus { draft, completed }

class ProductSelection {
  final Product product;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double discount;
  double get lineTotal => ((quantity * unitPrice) * (1 - discount / 100));

  ProductSelection({
    required this.product,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.discount = 0.0,
  });
}

class EnhancedInvoicePage extends ConsumerStatefulWidget {
  final AppDatabase db;

  const EnhancedInvoicePage({super.key, required this.db});

  @override
  ConsumerState<EnhancedInvoicePage> createState() =>
      _EnhancedInvoicePageState();
}

class _EnhancedInvoicePageState extends ConsumerState<EnhancedInvoicePage> {
  final _searchController = TextEditingController();
  final _paidAmountController = TextEditingController();
  final _notesController = TextEditingController();

  InvoiceType _selectedInvoiceType = InvoiceType.cash;
  InvoiceStatus _invoiceStatus = InvoiceStatus.draft;

  Customer? _selectedCustomer;
  List<Customer> _customers = [];
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  final List<ProductSelection> _selectedEntries = [];

  String _selectedPaymentMethod = 'cash';
  double _subtotal = 0.0;
  double _taxAmount = 0.0;
  double _grandTotal = 0.0;
  double _paidAmount = 0.0;
  double _remainingAmount = 0.0;

  bool _isLoading = true;
  bool _isProcessingPayment = false;

  @override
  void initState() {
    super.initState();
    _checkDayAndLoadData();
    _searchController.addListener(_onSearchChanged);
    _paidAmountController.addListener(_onPaidAmountChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _paidAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _checkDayAndLoadData() async {
    final isOpen = await widget.db.dayDao.isDayOpen();

    if (!isOpen) {
      _showDayClosedDialog();
      return;
    }

    try {
      final customers = await widget.db.customerDao.getAllCustomers();
      final products = await widget.db.productDao.getAllProducts();

      if (mounted) {
        setState(() {
          _customers = customers;
          _products = products;
          _filteredProducts = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = List.from(_products);
      } else {
        _filteredProducts = _products
            .where((p) => p.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  void _onPaidAmountChanged() {
    final paidText = _paidAmountController.text;
    final paid = double.tryParse(paidText) ?? 0.0;
    setState(() {
      _paidAmount = paid;
      _remainingAmount = _grandTotal - paid;
    });
  }

  void _showDayClosedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Day Closed'),
        content: const Text(
          'The business day is closed. Please open the day first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(onPressed: _openDay, child: const Text('Open Day')),
        ],
      ),
    );
  }

  Future<void> _openDay() async {
    try {
      await widget.db.dayDao.openDay(openingBalance: 0.0);
      if (mounted) {
        Navigator.of(context).pop();
        _checkDayAndLoadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening day: $e')));
      }
    }
  }

  void _onInvoiceTypeChanged(InvoiceType type) {
    setState(() {
      _selectedInvoiceType = type;
      if (type == InvoiceType.cash) {
        _selectedCustomer = Customer(
          id: 'cash_customer',
          name: 'Cash Customer',
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
        );
        _paidAmount = _grandTotal;
        _paidAmountController.text = _grandTotal.toStringAsFixed(2);
      } else {
        _selectedCustomer = null;
        _paidAmount = 0.0;
        _paidAmountController.text = '';
      }
      _remainingAmount = _grandTotal - _paidAmount;
    });
  }

  void _onCustomerChanged(Customer? customer) {
    setState(() {
      _selectedCustomer = customer;
    });
  }

  void _onPaymentMethodChanged(String method) {
    setState(() {
      _selectedPaymentMethod = method;
    });
  }

  void _addProduct(Product product) {
    showDialog(
      context: context,
      builder: (context) => _ProductSelectionDialog(
        product: product,
        onAdd: (quantity, unit, unitPrice, discount) {
          final entry = ProductSelection(
            product: product,
            quantity: quantity,
            unit: unit,
            unitPrice: unitPrice,
            discount: discount,
          );
          setState(() {
            _selectedEntries.add(entry);
            _calculateTotals();
          });
        },
      ),
    );
  }

  void _removeProductEntry(int index) {
    setState(() {
      _selectedEntries.removeAt(index);
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    setState(() {
      _subtotal = _selectedEntries.fold(
        0.0,
        (sum, entry) => sum + entry.lineTotal,
      );
      _taxAmount = _subtotal * 0.14; // 14% tax
      _grandTotal = _subtotal + _taxAmount;
      _remainingAmount = _grandTotal - _paidAmount;
    });
  }

  Future<void> _saveDraft() async {
    if (_selectedEntries.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add at least one product')));
      return;
    }

    setState(() => _invoiceStatus = InvoiceStatus.draft);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Draft saved')));
  }

  Future<void> _completePayment() async {
    if (_selectedInvoiceType == InvoiceType.cash && _paidAmount < _grandTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Full payment required for cash invoices'),
        ),
      );
      return;
    }

    if (_selectedInvoiceType == InvoiceType.credit &&
        _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer selection required for credit invoices'),
        ),
      );
      return;
    }

    setState(() => _isProcessingPayment = true);

    try {
      int insertedId = 0;
      await widget.db.transaction(() async {
        // Create invoice record
        final invoice = InvoicesCompanion.insert(
          invoiceNumber: Value('INV-${DateTime.now().millisecondsSinceEpoch}'),
          customerName: Value(_selectedCustomer?.name ?? 'Cash Customer'),
          customerContact: Value(
            (_selectedCustomer?.phone != null &&
                    _selectedCustomer!.phone!.isNotEmpty)
                ? _selectedCustomer!.phone!
                : 'N/A',
          ),
          customerId: Value(_selectedCustomer?.id),
          totalAmount: Value(_grandTotal),
          paidAmount: Value(_paidAmount),
          date: Value(DateTime.now()),
          status: Value(
            _selectedInvoiceType == InvoiceType.cash ? 'paid' : 'credit',
          ),
          paymentMethod: Value(_selectedPaymentMethod),
        );

        insertedId = await widget.db.into(widget.db.invoices).insert(invoice);

        // Create invoice items
        for (final entry in _selectedEntries) {
          final item = InvoiceItemsCompanion.insert(
            invoiceId: insertedId,
            productId: entry.product.id,
            quantity: Value(entry.quantity.toInt()),
            price: entry.unitPrice,
          );
          await widget.db.into(widget.db.invoiceItems).insert(item);
        }

        // Update stock
        for (final entry in _selectedEntries) {
          final currentProduct = await (widget.db.select(
            widget.db.products,
          )..where((p) => p.id.equals(entry.product.id))).getSingleOrNull();
          if (currentProduct != null) {
            final newQuantity = (currentProduct.quantity - entry.quantity)
                .toInt();
            await widget.db.productDao.updateProduct(
              ProductsCompanion(
                id: Value(currentProduct.id),
                name: Value(currentProduct.name),
                quantity: Value(newQuantity),
                price: Value(currentProduct.price),
                unit: Value(currentProduct.unit),
                status: Value(currentProduct.status),
              ),
            );
          }
        }

        // Record Sales Ledger Transactions
        final productSummary = _selectedEntries
            .map((e) => '${e.product.name} (${e.quantity})')
            .join(', ');
        final customerIdForLedger = _selectedCustomer?.id ?? 'walk-in';

        // 1. Record the Sale (Debt)
        await widget.db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${DateTime.now().millisecondsSinceEpoch}_sale',
            entityType: 'Customer',
            refId: customerIdForLedger,
            date: DateTime.now(),
            description: 'فاتورة مبيعات #$insertedId: $productSummary',
            debit: Value(_grandTotal),
            credit: const Value(0.0),
            origin: 'sale',
            paymentMethod: Value(_selectedPaymentMethod),
            receiptNumber: Value(insertedId.toString()),
          ),
        );

        // 2. Record Payment (Credit) if paid > 0
        if (_paidAmount > 0) {
          await widget.db.ledgerDao.insertTransaction(
            LedgerTransactionsCompanion.insert(
              id: '${DateTime.now().millisecondsSinceEpoch}_pay',
              entityType: 'Customer',
              refId: customerIdForLedger,
              date: DateTime.now(),
              description: 'دفعة فاتورة #$insertedId',
              debit: const Value(0.0),
              credit: Value(_paidAmount),
              origin: 'payment',
              paymentMethod: Value(_selectedPaymentMethod),
              receiptNumber: Value(insertedId.toString()),
            ),
          );
        }
      });

      setState(() => _invoiceStatus = InvoiceStatus.completed);

      // Print based on invoice type
      if (_selectedInvoiceType == InvoiceType.cash) {
        await _printThermalReceipt(insertedId);
      } else {
        await _printA4Invoice(insertedId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invoice completed successfully')),
        );

        _resetForm();
      }
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error completing payment: $e')));
      }
    }
  }

  Future<void> _printThermalReceipt(int invoiceId) async {
    try {
      // Get invoice items with product details
      final itemsWithProducts = await widget.db.invoiceDao
          .getItemsWithProductsByInvoice(invoiceId);

      // Convert to InvoiceItem models
      final invoiceItems = itemsWithProducts.map((itemWithProduct) {
        final item = itemWithProduct.$1;
        final product = itemWithProduct.$2;
        return ups.InvoiceItem(
          id: item.id,
          invoiceId: item.invoiceId,
          description: product?.name ?? 'Product ${item.productId}',
          unit: 'قطعة',
          quantity: item.quantity,
          unitPrice: item.price,
          totalPrice: item.quantity * item.price,
        );
      }).toList();

      // Create store info
      final storeInfo = ups.StoreInfo(
        storeName: 'المحل التجاري',
        phone: '01234567890',
        zipCode: '12345',
        state: 'القاهرة',
      );

      // Get customer's actual previous balance
      double previousBalance = 0.0;
      if (_selectedCustomer != null &&
          _selectedCustomer!.id != 'cash_customer') {
        previousBalance = await widget.db.ledgerDao.getCustomerBalance(
          _selectedCustomer!.id,
        );
      }

      // Create invoice model
      final invoiceModel = ups.Invoice(
        id: invoiceId,
        invoiceNumber: 'INV$invoiceId',
        customerName: _selectedCustomer?.name ?? 'عميل غير محدد',
        customerPhone: _selectedCustomer?.phone ?? 'N/A',
        customerZipCode: '',
        customerState: '',
        invoiceDate: DateTime.now(),
        subtotal: _grandTotal,
        isCreditAccount: _selectedInvoiceType == InvoiceType.credit,
        previousBalance: previousBalance,
        totalAmount: _grandTotal,
      );

      // Create InvoiceData
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error printing receipt: $e')));
      }
    }
  }

  Future<void> _printA4Invoice(int invoiceId) async {
    try {
      // Get invoice items with product details
      final itemsWithProducts = await widget.db.invoiceDao
          .getItemsWithProductsByInvoice(invoiceId);

      // Convert to InvoiceItem models
      final invoiceItems = itemsWithProducts.map((itemWithProduct) {
        final item = itemWithProduct.$1;
        final product = itemWithProduct.$2;
        return ups.InvoiceItem(
          id: item.id,
          invoiceId: item.invoiceId,
          description: product?.name ?? 'Product ${item.productId}',
          unit: 'قطعة',
          quantity: item.quantity,
          unitPrice: item.price,
          totalPrice: item.quantity * item.price,
        );
      }).toList();

      // Create store info
      final storeInfo = ups.StoreInfo(
        storeName: 'المحل التجاري',
        phone: '01234567890',
        zipCode: '12345',
        state: 'القاهرة',
      );

      // Get customer's actual previous balance
      double previousBalance = 0.0;
      if (_selectedCustomer != null &&
          _selectedCustomer!.id != 'cash_customer') {
        previousBalance = await widget.db.ledgerDao.getCustomerBalance(
          _selectedCustomer!.id,
        );
      }

      // Create invoice model
      final invoiceModel = ups.Invoice(
        id: invoiceId,
        invoiceNumber: 'INV$invoiceId',
        customerName: _selectedCustomer?.name ?? 'عميل غير محدد',
        customerPhone: _selectedCustomer?.phone ?? 'N/A',
        customerZipCode: '',
        customerState: '',
        invoiceDate: DateTime.now(),
        subtotal: _grandTotal,
        isCreditAccount: _selectedInvoiceType == InvoiceType.credit,
        previousBalance: previousBalance,
        totalAmount: _grandTotal,
      );

      // Create InvoiceData
      final invoiceData = ups.InvoiceData(
        invoice: invoiceModel,
        items: invoiceItems,
        storeInfo: storeInfo,
      );

      // Print using new SOP 4.0 format (A4)
      // Only pass paidAmount if customer has actually paid something
      final Map<String, dynamic>? additionalData = (_paidAmount > 0)
          ? {'paidAmount': _paidAmount}
          : null;

      await ups.UnifiedPrintService.printToThermalPrinter(
        documentType: ups.DocumentType.salesInvoice,
        data: invoiceData,
        additionalData: additionalData,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error printing invoice: $e')));
      }
    }
  }

  void _resetForm() {
    setState(() {
      _selectedEntries.clear();
      _selectedCustomer = _selectedInvoiceType == InvoiceType.cash
          ? Customer(
              id: 'cash_customer',
              name: 'Cash Customer',
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
            )
          : null;
      _paidAmount = _selectedInvoiceType == InvoiceType.cash
          ? _grandTotal
          : 0.0;
      _paidAmountController.text = _selectedInvoiceType == InvoiceType.cash
          ? _grandTotal.toStringAsFixed(2)
          : '';
      _notesController.clear();
      _subtotal = 0.0;
      _taxAmount = 0.0;
      _grandTotal = 0.0;
      _remainingAmount = 0.0;
      _invoiceStatus = InvoiceStatus.draft;
      _isProcessingPayment = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _invoiceStatus == InvoiceStatus.draft
              ? 'New Invoice'
              : 'Invoice Complete',
        ),
        backgroundColor: _invoiceStatus == InvoiceStatus.completed
            ? Colors.green
            : null,
        actions: [
          IconButton(
            onPressed: _resetForm,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset',
          ),
        ],
      ),
      body: Row(
        children: [
          // Left side - Products & Search (2/3 width)
          Expanded(
            flex: 2,
            child: Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Gap(8),
                // Product grid
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 2.5,
                        ),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      return Card(
                        child: InkWell(
                          onTap: () => _addProduct(product),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                ),
                                const Gap(4),
                                Text(
                                  'Stock: ${product.quantity}',
                                  style: TextStyle(
                                    color: product.quantity > 10
                                        ? Colors.green
                                        : Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '${product.price.toStringAsFixed(2)} SAR',
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w600,
                                  ),
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
          const VerticalDivider(width: 1),
          // Right side - Invoice Details (1/3 width)
          Expanded(
            flex: 1,
            child: Column(
              children: [
                // Invoice header
                _buildInvoiceHeader(),
                const Gap(16),
                // Invoice type selector
                _buildInvoiceTypeSelector(),
                const Gap(16),
                // Customer selection (for credit)
                if (_selectedInvoiceType == InvoiceType.credit) ...[
                  _buildCustomerSelector(),
                  const Gap(16),
                ],
                // Order lines
                Expanded(child: _buildOrderLines()),
                const Gap(16),
                // Payment block
                _buildPaymentBlock(),
                const Gap(16),
                // Notes
                _buildNotesSection(),
                const Gap(16),
                // Action buttons
                _buildActionButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Invoice Number: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'INV-${DateTime.now().millisecondsSinceEpoch}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Text(
            'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _selectedInvoiceType == InvoiceType.cash
                  ? Colors.green
                  : Colors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _selectedInvoiceType == InvoiceType.cash ? 'CASH' : 'CREDIT',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Invoice Type:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Gap(8),
          ToggleButtons(
            isSelected: [
              _selectedInvoiceType == InvoiceType.cash,
              _selectedInvoiceType == InvoiceType.credit,
            ],
            onPressed: (int index) {
              final newType = index == 0
                  ? InvoiceType.cash
                  : InvoiceType.credit;
              _onInvoiceTypeChanged(newType);
            },
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Cash'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Credit'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customer:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Gap(8),
          DropdownButtonFormField<Customer>(
            initialValue: _selectedCustomer,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Select customer',
            ),
            items: _customers.map((customer) {
              return DropdownMenuItem(
                value: customer,
                child: Text(customer.name),
              );
            }).toList(),
            onChanged: _onCustomerChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderLines() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Order Lines',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                onPressed: _resetForm,
                icon: const Icon(Icons.clear),
                tooltip: 'Clear all',
              ),
            ],
          ),
          const Gap(8),
          if (_selectedEntries.isEmpty)
            const Center(child: Text('No products added yet'))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _selectedEntries.length,
                itemBuilder: (context, index) {
                  final entry = _selectedEntries[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  entry.product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${entry.quantity} ${entry.unit}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${entry.unitPrice.toStringAsFixed(2)} SAR',
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${entry.lineTotal.toStringAsFixed(2)} SAR',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _removeProductEntry(index),
                                icon: const Icon(Icons.delete),
                                tooltip: 'Remove',
                              ),
                            ],
                          ),
                          if (entry.discount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Discount: ${entry.discount}% OFF',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentBlock() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Details',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Gap(12),

          // Payment method selector
          if (_selectedInvoiceType == InvoiceType.cash) ...[
            const Text('Payment Method:'),
            const Gap(8),
            DropdownButtonFormField<String>(
              initialValue: _selectedPaymentMethod,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Select payment method',
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'visa', child: Text('Visa')),
                DropdownMenuItem(
                  value: 'mastercard',
                  child: Text('Mastercard'),
                ),
                DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  _onPaymentMethodChanged(value);
                }
              },
            ),
            const Gap(16),
          ],

          // Paid amount input
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _paidAmountController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Paid Amount',
                    prefixText: 'SAR ',
                    enabled: _selectedInvoiceType == InvoiceType.cash,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Grand Total: ${_grandTotal.toStringAsFixed(2)} SAR',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Gap(8),
                    Text(
                      'Remaining: ${_remainingAmount.toStringAsFixed(2)} SAR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _remainingAmount > 0 ? Colors.red : Colors.green,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
          const Gap(8),
          TextField(
            controller: _notesController,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Add notes...',
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveDraft,
                  child: const Text('Save Draft'),
                ),
              ),
              const Gap(8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isProcessingPayment ? null : _completePayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: _isProcessingPayment
                      ? const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        )
                      : const Text('Complete Payment'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductSelectionDialog extends StatefulWidget {
  final Product product;
  final Function(
    double quantity,
    String unit,
    double unitPrice,
    double discount,
  )
  onAdd;

  const _ProductSelectionDialog({required this.product, required this.onAdd});

  @override
  State<_ProductSelectionDialog> createState() =>
      _ProductSelectionDialogState();
}

class _ProductSelectionDialogState extends State<_ProductSelectionDialog> {
  final _quantityController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _discountController = TextEditingController();

  String _selectedUnit = 'piece';

  @override
  void initState() {
    super.initState();
    _quantityController.text = '1';
    _unitPriceController.text = widget.product.price.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _unitPriceController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product.name),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Available Stock: ${widget.product.quantity} ${widget.product.unit ?? 'pieces'}',
            ),
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedUnit,
                    decoration: InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'piece', child: Text('Piece')),
                      DropdownMenuItem(value: 'kg', child: Text('Kg')),
                      DropdownMenuItem(value: 'ton', child: Text('Ton')),
                      DropdownMenuItem(value: 'box', child: Text('Box')),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedUnit = value ?? 'piece'),
                  ),
                ),
              ],
            ),
            const Gap(8),
            TextField(
              controller: _unitPriceController,
              decoration: InputDecoration(
                labelText: 'Unit Price (SAR)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const Gap(8),
            TextField(
              controller: _discountController,
              decoration: InputDecoration(
                labelText: 'Discount (%)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final quantity = double.tryParse(_quantityController.text) ?? 1.0;
            final unitPrice =
                double.tryParse(_unitPriceController.text) ??
                widget.product.price;
            final discount = double.tryParse(_discountController.text) ?? 0.0;

            widget.onAdd(quantity, _selectedUnit, unitPrice, discount);
            Navigator.of(context).pop();
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
