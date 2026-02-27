import 'dart:developer';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/l10n/app_localizations.dart';

class AddInvoiceDialog extends StatefulHookConsumerWidget {
  final AppDatabase db;

  const AddInvoiceDialog({super.key, required this.db});
  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _AddInvoiceDialogState();
}

class _AddInvoiceDialogState extends ConsumerState<AddInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  double _totalAmount = 0.0;
  double _paidAmount = 0.0;

  List<Customer> _customers = [];
  List<Product> _products = [];
  List<Product> _filteredProducts = []; // For search

  Customer? _selectedCustomer;
  String _selectedInvoiceType = 'cash'; // 'cash' or 'credit'
  String _selectedPaymentMethod = 'cash'; // 'cash', 'visa', etc.

  final List<_SelectedProductEntry> _selectedEntries = [];
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String _notes = '';

  bool _isDayOpen = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkDayAndLoadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _paidAmountController.dispose();
    _notesController.dispose();
    super.dispose();
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

  Future<void> _checkDayAndLoadData() async {
    final db = widget.db;

    // Step 1c: Validate Day Status
    final isOpen = await db.dayDao.isDayOpen();

    if (!isOpen) {
      if (mounted) {
        setState(() {
          _isDayOpen = false;
          _isLoading = false;
        });
        // Step 1d: Show error UI for closed day
        return;
      }
    }

    // Step 1e & 1f: Load data only if day is open
    try {
      // Step 1e: Load customers for dropdown selection
      final customers = await db.customerDao.getAllCustomers();
      // Step 1f: Load products for the product grid display
      final products = await db.productDao.getAllProducts();

      if (mounted) {
        setState(() {
          _isDayOpen = true;
          _customers = customers; // Customer dropdown populated
          _products = products; // Product grid populated
          _filteredProducts = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Handle data loading errors
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في تحميل البيانات: $e')));
      }
    }
  }

  void _calculateTotalAmount() {
    double total = 0;
    for (final entry in _selectedEntries) {
      if (entry.product != null) {
        total += (entry.customPrice ?? entry.product!.price) * entry.quantity;
      }
    }
    setState(() {
      _totalAmount = total;
      // Auto-update paid amount if Cash
      if (_selectedInvoiceType == 'cash') {
        _paidAmount = total;
        _paidAmountController.text = total.toStringAsFixed(2);
      }
    });
  }

  void _addProductToCart(Product product) {
    setState(() {
      final existingIndex = _selectedEntries.indexWhere(
        (e) => e.product?.id == product.id,
      );
      if (existingIndex != -1) {
        _selectedEntries[existingIndex].quantity++;
      } else {
        _selectedEntries.add(
          _SelectedProductEntry()
            ..product = product
            ..quantity = 1
            ..customPrice = product.price,
        );
      }
      _calculateTotalAmount();
    });
  }

  void _removeProductFromCart(int index) {
    setState(() {
      _selectedEntries.removeAt(index);
      _calculateTotalAmount();
    });
  }

  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);

    // Check if customer is selected for all invoice types
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار العميل أولاً'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار منتج واحد على الأقل')),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('جاري حفظ الفاتورة...'),
          ],
        ),
      ),
    );

    final db = widget.db;

    try {
      // Customer Info
      String customerName;
      String customerId;
      String? customerContact;
      String? customerAddress;

      if (_selectedCustomer != null) {
        customerName = _selectedCustomer!.name;
        customerId = _selectedCustomer!.id;
        customerContact = _selectedCustomer!.phone;
        customerAddress = _selectedCustomer!.address;
      } else {
        // Fallback for Cash if no customer selected
        customerName = l10n.walk_in_customer;
        customerId = 'walkin';
        // Try to find if exists
        try {
          final walkin = _customers.firstWhere(
            (c) => c.name == l10n.walk_in_customer,
          );
          customerId = walkin.id;
          customerContact = walkin.phone;
          customerAddress = walkin.address;
        } catch (_) {}
        customerContact = customerContact?.isEmpty ?? true
            ? ''
            : customerContact;
      }

      // Calculate paid and status
      double paid = _selectedInvoiceType == 'cash' ? _totalAmount : _paidAmount;
      String status = 'معلق';
      if ((_totalAmount - paid).abs() < 0.01) {
        status = 'مدفوع';
      } else if (paid > 0) {
        status = 'مدفوع جزئياً';
      }

      final invoiceNumber = 'INV${DateTime.now().millisecondsSinceEpoch}';
      final invoiceId = await db.invoiceDao.insertInvoice(
        InvoicesCompanion(
          customerName: Value(customerName),
          customerContact: Value(customerContact ?? ''),
          customerAddress: Value(customerAddress ?? ''),
          customerId: Value(customerId),
          paymentMethod: Value(
            _selectedInvoiceType == 'cash' ? _selectedPaymentMethod : 'credit',
          ),
          totalAmount: Value(_totalAmount),
          paidAmount: Value(paid),
          status: Value(status),
          invoiceNumber: Value(invoiceNumber),
          date: Value(DateTime.now()),
        ),
      );

      // Items
      for (final entry in _selectedEntries) {
        if (entry.product == null || entry.quantity <= 0) continue;

        final updatedQuantity = entry.product!.quantity - entry.quantity;
        if (updatedQuantity < 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${l10n.exceeds_available_stock}: ${entry.product!.name}',
                ),
              ),
            );
          }
          // Should we rollback? For now just continue or throw?
          // The previous code threw exception.
          throw Exception(
            '${l10n.exceeds_available_stock}: ${entry.product!.name}',
          );
        }

        await db.productDao.updateProduct(
          entry.product!.copyWith(quantity: updatedQuantity),
        );

        await db.invoiceDao.insertInvoiceItem(
          InvoiceItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(entry.product!.id),
            quantity: Value(entry.quantity),
            ctn: Value(entry.ctn ?? 0),
            price: Value(entry.customPrice ?? entry.product!.price),
          ),
        );
      }

      // Ledger Transactions
      final productSummary = _selectedEntries
          .where((e) => e.product != null)
          .map((e) => '${e.product!.name} (${e.quantity})')
          .join(', ');

      // 1. Record Sale (Debit)
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_sale',
          entityType: 'Customer',
          refId: customerId,
          date: DateTime.now(),
          description: 'فاتورة مبيعات #$invoiceId: $productSummary',
          debit: Value(_totalAmount), // Customer owes this
          credit: const Value(0.0),
          origin: 'sale',
          paymentMethod: Value('credit'), // The SALE is credit based until paid
          receiptNumber: Value(invoiceNumber),
        ),
      );

      // 2. Record Payment (Credit) if paid > 0
      if (paid > 0) {
        await db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${DateTime.now().millisecondsSinceEpoch}_payment',
            entityType: 'Customer',
            refId: customerId,
            date: DateTime.now(),
            description: 'دفعة فاتورة #$invoiceId',
            debit: const Value(0.0),
            credit: Value(paid), // Customer pays this
            origin: 'payment',
            paymentMethod: Value(
              _selectedInvoiceType == 'cash'
                  ? _selectedPaymentMethod
                  : 'credit_partial_payment', // تمييز دفعات الآجل عن الكاش
            ),
            receiptNumber: Value(invoiceNumber),
          ),
        );
      }

      // Printing
      final invoiceData = {
        'id': invoiceId,
        'customerName': customerName,
        'customerId': customerId,
        'totalAmount': _totalAmount,
        'paidAmount': paid,
        'remainingAmount': _totalAmount - paid,
        'date': DateTime.now(),
        'paymentMethod': _selectedInvoiceType == 'cash'
            ? _selectedPaymentMethod
            : 'credit',
      };

      final itemsData = _selectedEntries
          .where((e) => e.product != null)
          .map(
            (entry) => {
              'name': entry.product!.name,
              'quantity': entry.quantity,
              'price': entry.customPrice ?? entry.product!.price,
              'total':
                  (entry.customPrice ?? entry.product!.price) * entry.quantity,
            },
          )
          .toList();

      // Print using new SOP 4.0 format
      final itemsWithProducts = await db.invoiceDao
          .getItemsWithProductsByInvoice(invoiceId);

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

      final storeInfo = ups.StoreInfo(
        storeName: 'المحل التجاري',
        phone: '01234567890',
        zipCode: '12345',
        state: 'القاهرة',
      );

      final invoiceModel = ups.Invoice(
        id: invoiceId,
        invoiceNumber: 'INV$invoiceId',
        customerName: customerName,
        customerPhone: 'N/A',
        customerZipCode: '',
        customerState: '',
        invoiceDate: DateTime.now(),
        subtotal: _totalAmount,
        isCreditAccount: _selectedInvoiceType == 'credit',
        previousBalance: 0.0,
        totalAmount: _totalAmount,
      );

      final unifiedInvoiceData = ups.InvoiceData(
        invoice: invoiceModel,
        items: invoiceItems,
        storeInfo: storeInfo,
      );

      await ups.UnifiedPrintService.printToThermalPrinter(
        documentType: ups.DocumentType.salesInvoice,
        data: unifiedInvoiceData,
      );

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        Navigator.of(context).pop(); // Close invoice dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.invoice_saved_successfully)),
        );
      }
    } catch (e) {
      log('Error saving invoice: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${l10n.error}: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (!_isDayOpen && !_isLoading) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, color: Colors.red, size: 50),
              const Gap(10),
              Text(l10n.day_is_closed, style: const TextStyle(fontSize: 20)),
              const Gap(20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.close),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // New Split Layout: RTL Friendly
    // Row(children: [DetailsPanel (1/3), ProductsPanel (2/3)])
    // Wait, in RTL: Start is Right.
    // If we want Details on Right (Start), it should be first in Row children?
    // Flutter Row: children are [Start, ..., End].
    // RTL: Start is Right.
    // So [DetailsPanel, ProductsPanel] => Details on Right, Products on Left.
    // This matches user Request: "Details... on the right".

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(l10n.new_invoice),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Row(
        children: [
          // DETAILS PANEL (Right side in RTL) - Enlarged
          Expanded(flex: 4, child: _buildDetailsPanel(l10n)),
          const VerticalDivider(width: 1),
          // PRODUCTS PANEL (Left side in RTL) - Smaller
          Expanded(flex: 2, child: _buildProductsPanel(l10n)),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel(AppLocalizations l10n) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // 1. Invoice Type & Customer
            Card(
              elevation: 0,
              color: Colors.grey.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    // Payment Type Selection - Enhanced UI
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'نوع الدفع',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const Gap(8),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedInvoiceType = 'cash';
                                      _calculateTotalAmount(); // Auto-set paid amount
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedInvoiceType == 'cash'
                                          ? Colors.green.shade100
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _selectedInvoiceType == 'cash'
                                            ? Colors.green
                                            : Colors.grey.shade300,
                                        width: _selectedInvoiceType == 'cash'
                                            ? 2
                                            : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.attach_money,
                                          color: _selectedInvoiceType == 'cash'
                                              ? Colors.green
                                              : Colors.grey.shade600,
                                        ),
                                        const Gap(8),
                                        Text(
                                          l10n.cash,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                _selectedInvoiceType == 'cash'
                                                ? Colors.green
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const Gap(10),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedInvoiceType = 'credit';
                                      _paidAmount = 0; // Reset for credit
                                      _paidAmountController.text = '0';
                                      _calculateTotalAmount(); // Ensure consistency
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedInvoiceType == 'credit'
                                          ? Colors.orange.shade100
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _selectedInvoiceType == 'credit'
                                            ? Colors.orange
                                            : Colors.grey.shade300,
                                        width: _selectedInvoiceType == 'credit'
                                            ? 2
                                            : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.credit_card,
                                          color:
                                              _selectedInvoiceType == 'credit'
                                              ? Colors.orange
                                              : Colors.grey.shade600,
                                        ),
                                        const Gap(8),
                                        Text(
                                          l10n.credit,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                _selectedInvoiceType == 'credit'
                                                ? Colors.orange
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Gap(5),
                    DropdownButtonFormField<Customer>(
                      initialValue: _selectedCustomer,
                      decoration: InputDecoration(
                        labelText: l10n.customer,
                        prefixIcon: const Icon(Icons.person),
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: _customers
                          .map(
                            (c) =>
                                DropdownMenuItem(value: c, child: Text(c.name)),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedCustomer = val),
                      validator: (val) {
                        if (val == null) {
                          return 'يرجى اختيار العميل أولاً';
                        }
                        return null;
                      },
                    ),
                    // Payment Method Dropdown for Cash
                    if (_selectedInvoiceType == 'cash') ...[
                      const Gap(5),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedPaymentMethod,
                        decoration: InputDecoration(
                          labelText: 'طريقة الدفع',
                          prefixIcon: const Icon(Icons.payment),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                          DropdownMenuItem(value: 'visa', child: Text('فيزا')),
                          DropdownMenuItem(
                            value: 'mastercard',
                            child: Text('ماستر كارد'),
                          ),
                          DropdownMenuItem(
                            value: 'bankTransfer',
                            child: Text('تحويل بنكي'),
                          ),
                          DropdownMenuItem(
                            value: 'wallet',
                            child: Text('محفظة إلكترونية'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedPaymentMethod = val;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Gap(10),

            // 2. Cart List
            Expanded(
              child: _selectedEntries.isEmpty
                  ? Center(
                      child: Text(
                        l10n.no_products_available,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _selectedEntries.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final entry = _selectedEntries[index];
                        return ListTile(
                          title: Text(
                            entry.product?.name ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Row(
                            children: [
                              // Quantity
                              SizedBox(
                                width: 80,
                                child: TextFormField(
                                  initialValue: entry.quantity.toString(),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: InputDecoration(
                                    labelText: l10n.quantity,
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                  onChanged: (val) {
                                    final q = int.tryParse(val) ?? 0;
                                    setState(() {
                                      entry.quantity = q;
                                      _calculateTotalAmount();
                                    });
                                  },
                                ),
                              ),
                              const Gap(10),
                              // Price
                              SizedBox(
                                width: 100,
                                child: TextFormField(
                                  initialValue:
                                      (entry.customPrice ??
                                              entry.product!.price)
                                          .toString(),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: l10n.price,
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                  onChanged: (val) {
                                    final p =
                                        double.tryParse(val) ??
                                        entry.product!.price;
                                    setState(() {
                                      // Only set customPrice if it differs from default price
                                      if (p != entry.product!.price) {
                                        entry.customPrice = p;
                                      } else {
                                        entry.customPrice =
                                            null; // Reset to default
                                      }
                                      _calculateTotalAmount();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeProductFromCart(index),
                          ),
                        );
                      },
                    ),
            ),

            const Divider(),

            // 3. Totals & Payment
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.total,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_totalAmount.toStringAsFixed(2)} ${l10n.currency}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                if (_selectedInvoiceType == 'credit') ...[
                  const Gap(10),
                  TextFormField(
                    controller: _paidAmountController,
                    decoration: InputDecoration(
                      labelText: l10n.paid, // "Paid Amount"
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.payment),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _paidAmount = double.tryParse(val) ?? 0.0;
                      });
                    },
                  ),
                  const Gap(5),
                  Text(
                    '${l10n.remaining}: ${(_totalAmount - _paidAmount).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const Gap(10),
                // Compact Notes Button
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notes, size: 16),
                    label: Text(
                      'ملاحظات${_notes.isNotEmpty ? ' (${_notes.length})' : ''}',
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
                                _notes = _notesController.text;
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
                const Gap(10),
                ElevatedButton.icon(
                  onPressed: _saveInvoice,
                  icon: const Icon(Icons.print),
                  label: Text(
                    l10n.save_and_print,
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsPanel(AppLocalizations l10n) {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: l10n.search_product,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),

        // Products Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:
                  3, // Adjust based on screen size? 3 is okay for desktop dialog
              childAspectRatio: 1.0,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _filteredProducts.length,
            itemBuilder: (context, index) {
              final product = _filteredProducts[index];
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: () => _addProductToCart(product),
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Center(
                            child: Text(
                              product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        color: Colors.blue.withValues(alpha: 0.1),
                        child: Column(
                          children: [
                            Text(
                              '${product.price} ${l10n.currency_symbol}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            if (product.quantity > 0)
                              Text(
                                '${l10n.quantity}: ${product.quantity}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                          ],
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
    );
  }
}

class _SelectedProductEntry {
  Product? product;
  int quantity = 1;
  int? ctn;
  double? customPrice;
}
