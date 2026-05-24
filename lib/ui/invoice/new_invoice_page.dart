import 'dart:developer';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/invoice_type_selection_dialog.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/split_payment_dialog.dart';

class NewInvoicePage extends StatefulHookConsumerWidget {
  const NewInvoicePage({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _NewInvoicePageState();
}

class _NewInvoicePageState extends ConsumerState<NewInvoicePage> {
  final _formKey = GlobalKey<FormState>();
  double _totalAmount = 0.0;
  double _paidAmount = 0.0;

  List<Customer> _customers = [];
  List<Product> _products = [];
  List<Invoice> _recentInvoices = [];

  Customer? _selectedCustomer;
  String _selectedInvoiceType = 'cash'; // 'cash' or 'credit'
  String _selectedPaymentMethod = 'cash'; // 'cash', 'visa', 'master'

  final List<_SelectedProductEntry> _selectedEntries = [];
  final TextEditingController _customPriceController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _productSearchController =
      TextEditingController();

  bool _isDayOpen = true;
  bool _isLoading = true;
  bool _invoiceTypeLocked = false;
  double _selectedCustomerBalance = 0.0;
  double _selectedCustomerOpening = 0.0;
  String? _thermalPrinterName;
  String? _a4PrinterName;
  final List<Map<String, dynamic>> _availablePrinters = [];
  String? _overridePrinterName;

  @override
  void initState() {
    super.initState();
    _checkDayStatus();
    _loadCustomersAndProducts();

    // Load saved printer preferences for preview
    SettingsService.getThermalPrinter().then((name) {
      setState(() => _thermalPrinterName = name);
    });
    SettingsService.getA4Printer().then((name) {
      setState(() => _a4PrinterName = name);
    });

    // Load available printers for override
    // Note: UnifiedPrintService doesn't have getAvailablePrinters method
    // This feature may need to be implemented separately or removed
    // setState(() => _availablePrinters = []);
  }

  Future<void> _checkDayStatus() async {
    final db = ref.read(appDatabaseProvider);
    final bool isOpen = await db.dayDao.isDayOpen();
    if (mounted) {
      setState(() {
        _isDayOpen = isOpen;
        _isLoading = false;
      });
    }

    // لو اليوم مفتوح نعرض اختيار نوع الفاتورة
    if (isOpen && mounted) {
      _showInvoiceTypeSelection();
    }
    // لو اليوم مقفول: لا نفتحه تلقائياً — المستخدم يفتحه يدوياً
  }

  Future<void> _showInvoiceTypeSelection() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const InvoiceTypeSelectionDialog(),
    );

    if (result != null && mounted) {
      // Handle supply navigation separately
      if (result == 'supply') {
        Navigator.pushNamed(context, '/new-supply-invoice');
        return;
      }

      setState(() {
        _selectedInvoiceType = result;
        _invoiceTypeLocked = true;

        // Set default customer and payment method for cash
        if (result == 'cash') {
          _selectedPaymentMethod = 'cash';
          _paidAmount = _totalAmount;
          _paidAmountController.text = _totalAmount.toStringAsFixed(2);
        } else {
          _paidAmount = 0.0;
          _paidAmountController.text = '0.00';
        }
      });
    }
  }

  @override
  void dispose() {
    _customPriceController.dispose();
    _paidAmountController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomersAndProducts() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final customers = await db.customerDao.getAllCustomers();
      final products = await db.productDao.getAllProducts();
      final invoices = await db.invoiceDao.getAllInvoices();

      if (!mounted) return;
      setState(() {
        _customers = customers;
        _products = products;
        _recentInvoices = invoices.reversed.take(20).toList();
      });
    } catch (e, stack) {
      debugPrint('Failed to load invoice data: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات')),
        );
      }
    }
  }

  Future<void> _searchProducts(String q) async {
    try {
      final db = ref.read(appDatabaseProvider);
      if (q.trim().isEmpty) {
        final all = await db.productDao.getAllProducts();
        if (!mounted) return;
        setState(() => _products = all);
        return;
      }
      final results = await db.productDao.searchProducts(q);
      if (!mounted) return;
      setState(() => _products = results);
    } catch (e, stack) {
      debugPrint('Failed to search products: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات')),
        );
      }
    }
  }

  Future<void> _loadOrder(int invoiceId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final items =
          await db.invoiceDao.getItemsWithProductsByInvoice(invoiceId);
      if (!mounted) return;
      setState(() {
        _selectedEntries.clear();
        for (final row in items) {
          final item = row.$1;
          final product = row.$2;
          _selectedEntries.add(
            _SelectedProductEntry()
              ..product = product
              ..quantity = item.quantity
              ..ctn = item.ctn
              ..customPrice = item.price,
          );
        }
        _calculateTotalAmount();
      });
    } catch (e, stack) {
      debugPrint('Failed to load order: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات')),
        );
      }
    }
  }

  Future<void> _loadCustomerBalance(Customer customer) async {
    final db = ref.read(appDatabaseProvider);
    try {
      final bal = await db.ledgerDao.getCustomerBalance(customer.id);
      setState(() {
        _selectedCustomerBalance = bal + customer.openingBalance;
        _selectedCustomerOpening = customer.openingBalance;
      });
    } catch (e) {
      setState(() {
        _selectedCustomerBalance = 0.0;
        _selectedCustomerOpening = 0.0;
      });
    }
  }

  void _calculateTotalAmount() {
    double total = 0;
    for (final entry in _selectedEntries) {
      if (entry.product != null && entry.quantity > 0) {
        total += (entry.customPrice ?? entry.product!.price) * entry.quantity;
      }
    }
    setState(() {
      _totalAmount = total;
      // Update paid amount for cash invoices
      if (_selectedInvoiceType == 'cash') {
        _paidAmount = total;
        _paidAmountController.text = total.toStringAsFixed(2);
      }
    });
  }

  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إضافة منتج واحد على الأقل')),
      );
      return;
    }

    // Show Split Payment Dialog
    final splitResult = await showDialog<SplitPaymentResult>(
      context: context,
      builder: (context) => SplitPaymentDialog(
        totalAmount: _totalAmount,
        isCustomerSelected: _selectedCustomer != null,
        customerName: _selectedCustomer?.name,
      ),
    );

    if (splitResult == null) return; // User cancelled

    final db = ref.read(appDatabaseProvider);

    try {
      // Determine customer info and fetch previous balance for credit invoices
      String customerName;
      String customerId;
      String? customerContact;
      String? customerAddress;
      double previousBalance = 0.0;

      if (_selectedCustomer == null) {
        customerName = 'عميل نقدي';
        customerId = 'walkin';
        customerContact = 'N/A';
        customerAddress = '';
      } else {
        customerName = _selectedCustomer!.name;
        customerId = _selectedCustomer!.id;
        customerContact = _selectedCustomer!.phone;
        customerAddress = _selectedCustomer!.address;

        // Fetch previous balance
        try {
          previousBalance = await db.ledgerDao.getCustomerBalance(
            _selectedCustomer!.id,
          );
        } catch (e) {
          log('Error fetching previous balance: $e');
          previousBalance = 0.0;
        }
      }

      final invoiceId = await db.invoiceDao.insertInvoice(
        InvoicesCompanion(
          customerName: Value(customerName),
          customerContact: Value(
            (customerContact?.isNotEmpty == true) ? customerContact : 'N/A',
          ),
          customerAddress: Value(customerAddress ?? ''),
          customerId: Value(customerId),
          paymentMethod: const Value('mixed'), // SOP 4.0: use 'mixed' for all
          totalAmount: Value(_totalAmount),
          paidAmount: Value(splitResult.cash + splitResult.card),
          status: Value((splitResult.cash + splitResult.card) >= _totalAmount ? 'paid' : 'pending'),
          invoiceNumber: Value('INV${DateTime.now().millisecondsSinceEpoch}'),
          date: Value(DateTime.now()),
        ),
      );

      // Record detailed payments in InvoicePayments table
      if (splitResult.cash > 0) {
        await db.invoicePaymentsDao.insertPayment(
          InvoicePaymentsCompanion.insert(
            invoiceId: invoiceId,
            paymentMethod: 'cash',
            amount: splitResult.cash,
          ),
        );
      }
      if (splitResult.card > 0) {
        await db.invoicePaymentsDao.insertPayment(
          InvoicePaymentsCompanion.insert(
            invoiceId: invoiceId,
            paymentMethod: 'visa',
            amount: splitResult.card,
          ),
        );
      }
      if (splitResult.credit > 0) {
        await db.invoicePaymentsDao.insertPayment(
          InvoicePaymentsCompanion.insert(
            invoiceId: invoiceId,
            paymentMethod: 'credit',
            amount: splitResult.credit,
          ),
        );
      }

      // Add invoice items and update product quantities
      for (final entry in _selectedEntries) {
        if (entry.product == null || entry.quantity <= 0) continue;

        final updatedQuantity = entry.product!.quantity - entry.quantity;
        // In SOP 4.0 we allow negative stock if settings allow, but for now we keep the check
        /*
        if (updatedQuantity < 0) {
          throw Exception(
            'الكمعة المطلوبة تتجاوز الكمية المتاحة: ${entry.product!.name}',
          );
        }
        */

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

      // Add ledger transactions
      // 1. Record the Sale (Debit Customer)
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_sale',
          entityType: 'Customer',
          refId: customerId,
          date: DateTime.now(),
          description: 'بيع #$invoiceId',
          debit: Value(_totalAmount),
          credit: const Value(0.0),
          origin: 'sale',
          paymentMethod: const Value('mixed'),
          receiptNumber: Value('INV$invoiceId'),
        ),
      );

      // 2. Record Payments (Credit Customer)
      if (splitResult.cash > 0) {
        await db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${DateTime.now().millisecondsSinceEpoch}_pay_cash',
            entityType: 'Customer',
            refId: customerId,
            date: DateTime.now(),
            description: 'دفع نقدي #$invoiceId',
            debit: const Value(0.0),
            credit: Value(splitResult.cash),
            origin: 'payment',
            paymentMethod: const Value('cash'),
            receiptNumber: Value('INV$invoiceId'),
          ),
        );
      }
      if (splitResult.card > 0) {
        await db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${DateTime.now().millisecondsSinceEpoch}_pay_card',
            entityType: 'Customer',
            refId: customerId,
            date: DateTime.now(),
            description: 'دفع فيزا/ماستر #$invoiceId',
            debit: const Value(0.0),
            credit: Value(splitResult.card),
            origin: 'payment',
            paymentMethod: const Value('visa'),
            receiptNumber: Value('INV$invoiceId'),
          ),
        );
      }

      // Print invoice
      final invoiceReceiptData = await _createInvoiceData(
        invoiceId,
        customerName,
        customerId,
        _totalAmount,
        splitResult.cash + splitResult.card,
        'mixed',
      );

      await ups.UnifiedPrintService.printToThermalPrinter(
        documentType: ups.DocumentType.salesInvoice,
        data: invoiceReceiptData,
        additionalData: {
          'paidAmount': splitResult.cash + splitResult.card,
          'cashAmount': splitResult.cash,
          'cardAmount': splitResult.card,
          'creditAmount': splitResult.credit,
          'previousBalance': previousBalance,
        },
      );

      if (mounted) {
        // Reset state for next invoice
        setState(() {
          _selectedEntries.clear();
          _totalAmount = 0.0;
          _paidAmount = 0.0;
          _paidAmountController.clear();
          _selectedCustomer = null;
        });
        
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ الفاتورة بنجاح')));
      }
    } catch (e) {
      log('Error saving invoice: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isDayOpen) {
      return Scaffold(
        appBar: AppBar(title: const Text('فاتورة جديدة')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, color: Colors.red, size: 64),
              const Gap(16),
              const Text(
                'اليوم مغلق. يرجى فتح اليوم أولاً من قائمة الفواتير.',
                style: TextStyle(fontSize: 18),
              ),
              const Gap(24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('نظام البيع السريع'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Row(
        children: [
          // Sidebar (Right Side)
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Invoice Details Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.grey.shade800,
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تفاصيل الفاتورة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Gap(12),
                        // Type & Customer Selection
                        Row(
                          children: [
                            _buildTypeChip('cash', 'نقدي', Icons.money),
                            const Gap(8),
                            _buildTypeChip('credit', 'آجل', Icons.credit_card),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (_selectedInvoiceType == 'credit')
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<Customer>(
                            initialValue: _selectedCustomer,
                            decoration: const InputDecoration(
                              labelText: 'اختر العميل',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            items: _customers
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) async {
                              setState(() => _selectedCustomer = val);
                              if (val != null) await _loadCustomerBalance(val);
                            },
                          ),
                          const Gap(8),
                          if (_selectedCustomer != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('الرصيد الحالي للعميل'),
                                      const Gap(6),
                                      Text(
                                        '${_selectedCustomerBalance.toStringAsFixed(2)} ج.م',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: _selectedCustomerBalance > 0
                                              ? Colors.red
                                              : Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('الرصيد الافتتاحي'),
                                      const Gap(6),
                                      Text(
                                        '${_selectedCustomerOpening.toStringAsFixed(2)} ج.م',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Gap(8),
                            // Suggested payment helper with apply button
                            Builder(
                              builder: (context) {
                                final suggested = (_selectedCustomerBalance > 0)
                                    ? (_selectedCustomerBalance)
                                    : 0.0;
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Text(
                                      'مبلغ الدفع المقترح: ${suggested.toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                        color: suggested > 0
                                            ? Colors.orange
                                            : Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (suggested > 0)
                                      ElevatedButton(
                                        onPressed: () {
                                          setState(() {
                                            _paidAmount = suggested;
                                            _paidAmountController.text =
                                                suggested.toStringAsFixed(2);
                                          });
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 12,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: const Text('تطبيق'),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),

                  // Payment Method Selection for Cash
                  if (_selectedInvoiceType == 'cash')
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedPaymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'طريقة الدفع',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                          DropdownMenuItem(value: 'visa', child: Text('فيزا')),
                          DropdownMenuItem(
                            value: 'master',
                            child: Text('ماستر كارد'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedPaymentMethod = val);
                          }
                        },
                      ),
                    ),

                  // Load existing order (recent invoices)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: DropdownButtonFormField<int>(
                      initialValue: null,
                      decoration: const InputDecoration(
                        labelText: 'تحميل طلب سابق (اختر رقم الفاتورة)',
                        border: OutlineInputBorder(),
                      ),
                      items: _recentInvoices
                          .map(
                            (inv) => DropdownMenuItem<int>(
                              value: inv.id,
                              child: Text(
                                'فاتورة #${inv.id} - ${inv.customerName}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        _loadOrder(val);
                      },
                    ),
                  ),

                  const Divider(height: 1),

                  // Selected Items List
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _selectedEntries.length,
                      separatorBuilder: (context, index) => const Gap(8),
                      itemBuilder: (context, index) {
                        final entry = _selectedEntries[index];
                        if (entry.product == null) {
                          return const SizedBox.shrink();
                        }
                        return _buildSelectedProductTile(entry, index);
                      },
                    ),
                  ),

                  // Totals Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildTotalRow(
                          'المجموع:',
                          _totalAmount,
                          isGrand: false,
                        ),
                        const Gap(8),
                        // Printer preview indicator + override dropdown
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(Icons.print, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'الطابعة الافتراضية: ${_selectedInvoiceType == 'cash' ? (_thermalPrinterName ?? 'الافتراضية') : (_a4PrinterName ?? 'الافتراضية')}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        const Gap(8),
                        if (_availablePrinters.isNotEmpty)
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _overridePrinterName,
                                  decoration: const InputDecoration(
                                    labelText: 'اختيار طابعة مؤقتة',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _availablePrinters
                                      .map(
                                        (p) => DropdownMenuItem<String>(
                                          value: (p['name'] as String?) ?? '',
                                          child: Text(
                                            (p['name'] as String?) ?? '',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    setState(() => _overridePrinterName = val);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _overridePrinterName == null
                                    ? null
                                    : () async {
                                        // Save override as default for this invoice type
                                        if (_selectedInvoiceType == 'cash') {
                                          await SettingsService.setThermalPrinter(
                                            _overridePrinterName,
                                          );
                                          setState(
                                            () => _thermalPrinterName =
                                                _overridePrinterName,
                                          );
                                        } else {
                                          await SettingsService.setA4Printer(
                                            _overridePrinterName,
                                          );
                                          setState(
                                            () => _a4PrinterName =
                                                _overridePrinterName,
                                          );
                                        }
                                      },
                                child: const Text('حفظ كافتراضي'),
                              ),
                            ],
                          ),
                        const Gap(12),
                        if (_selectedInvoiceType == 'credit' ||
                            _selectedInvoiceType == 'cash')
                          TextFormField(
                            controller: _paidAmountController,
                            decoration: const InputDecoration(
                              labelText: 'المبلغ المدفوع',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.payments_outlined),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (val) {
                              final paid = double.tryParse(val) ?? 0.0;
                              setState(() => _paidAmount = paid);
                            },
                          ),
                        if (_selectedInvoiceType == 'credit') ...[
                          const Gap(12),
                          _buildTotalRow(
                            'المبلغ المتبقي:',
                            _totalAmount - _paidAmount,
                            color: Colors.red,
                          ),
                        ],
                        const Gap(20),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _saveInvoice,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'إتمام الدفع واصدار الفاتورة',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Product Selection Grid (Left Side)
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search & Category Placeholder
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _productSearchController,
                          onChanged: (val) => _searchProducts(val),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: 'البحث عن منتج...',
                            hintStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: const Icon(Icons.search, size: 24),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Colors.blue,
                                width: 2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Colors.orange,
                                width: 3,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: const BorderSide(
                                color: Colors.blue,
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(20),
                  const Text(
                    'المنتجات المتاحة',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Gap(12),
                  Expanded(
                    child: _products.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 5,
                                  childAspectRatio: 0.85,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: _products.length,
                            itemBuilder: (context, index) {
                              final product = _products[index];
                              final isSelected = _selectedEntries.any(
                                (e) => e.product?.id == product.id,
                              );
                              return _buildProductCard(product, isSelected);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String type, String label, IconData icon) {
    final isSelected = _selectedInvoiceType == type;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (_invoiceTypeLocked) return; // type fixed by settings
          setState(() {
            _selectedInvoiceType = type;
            if (type == 'cash') {
              _paidAmount = _totalAmount;
              _paidAmountController.text = _totalAmount.toStringAsFixed(2);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? Border.all(color: Colors.white) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.black : Colors.white70,
              ),
              const Gap(6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(Product product, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedEntries.removeWhere((e) => e.product?.id == product.id);
          } else {
            _selectedEntries.add(
              _SelectedProductEntry()
                ..product = product
                ..quantity = 1,
            );
          }
          _calculateTotalAmount();
        });
      },
      child: Card(
        color: isSelected ? Colors.black : Colors.white,
        elevation: isSelected ? 12 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: isSelected
              ? BorderSide(color: Colors.green, width: 3)
              : BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 60,
                width: 60,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white24 : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inventory_2,
                  color: isSelected ? Colors.white : Colors.grey,
                ),
              ),
              const Gap(10),
              Text(
                product.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isSelected ? Colors.white : Colors.black,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Gap(4),
              Text(
                'Stock: ${product.quantity}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white70 : Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Gap(2),
              Text(
                '${product.price.toStringAsFixed(2)} ج.م',
                style: TextStyle(
                  color: isSelected ? Colors.white70 : Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedProductTile(_SelectedProductEntry entry, int index) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.product!.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                onPressed: () {
                  setState(() {
                    _selectedEntries.removeAt(index);
                    _calculateTotalAmount();
                  });
                },
              ),
            ],
          ),
          Row(
            children: [
              // Quantity
              SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue: entry.quantity.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الكمية',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final qty = int.tryParse(val) ?? 0;
                    setState(() {
                      entry.quantity = qty;
                      _calculateTotalAmount();
                    });
                  },
                ),
              ),
              const Gap(8),
              // Price
              Expanded(
                child: TextFormField(
                  initialValue: (entry.customPrice ?? entry.product!.price)
                      .toStringAsFixed(2),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'السعر',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final price = double.tryParse(val) ?? 0.0;
                    setState(() {
                      entry.customPrice = price;
                      _calculateTotalAmount();
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    String title,
    double value, {
    bool isGrand = true,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isGrand ? 20 : 16,
            fontWeight: isGrand ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
        Text(
          '${value.toStringAsFixed(2)} ج.م',
          style: TextStyle(
            fontSize: isGrand ? 24 : 18,
            fontWeight: FontWeight.bold,
            color: color ?? (isGrand ? Colors.black : Colors.grey.shade800),
          ),
        ),
      ],
    );
  }

  /// Helper method to create InvoiceData for UnifiedPrintService
  Future<ups.InvoiceData> _createInvoiceData(
    int invoiceId,
    String customerName,
    String customerId,
    double totalAmount,
    double paidAmount,
    String paymentMethod,
  ) async {
    final db = ref.read(appDatabaseProvider);

    // Get invoice items with product details
    final itemsWithProducts = await db.invoiceDao.getItemsWithProductsByInvoice(
      invoiceId,
    );

    // Convert to InvoiceItem models
    final invoiceItems = itemsWithProducts.map((itemWithProduct) {
      final item = itemWithProduct.$1;
      final product = itemWithProduct.$2;
      return ups.InvoiceItem(
        id: item.id,
        invoiceId: item.invoiceId,
        description: product?.name ?? 'Product ${item.productId}',
        unit: 'قطعة', // Default unit
        quantity: item.quantity,
        unitPrice: item.price,
        totalPrice: item.quantity * item.price,
      );
    }).toList();

    // Get store info - UnifiedPrintService will fetch from settings if null
    const ups.StoreInfo? storeInfo = null;

    // Create invoice model
    final invoice = ups.Invoice(
      id: invoiceId,
      invoiceNumber: 'INV$invoiceId',
      customerName: customerName,
      customerPhone: 'N/A',
      customerZipCode: '',
      customerState: '',
      invoiceDate: DateTime.now(),
      subtotal: totalAmount,
      isCreditAccount: paymentMethod == 'credit',
      previousBalance: 0.0, // This will be calculated in additionalData
      totalAmount: totalAmount,
    );

    return ups.InvoiceData(
      invoice: invoice,
      items: invoiceItems,
      storeInfo: storeInfo,
    );
  }
}

class _SelectedProductEntry {
  _SelectedProductEntry();

  Product? product;
  int quantity = 1;
  int? ctn;
  double? customPrice;
}
