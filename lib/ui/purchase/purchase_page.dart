import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/core/services/purchases_pdf_service.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:drift/drift.dart' as drift;
import 'package:gap/gap.dart';

class PurchasePage extends StatefulWidget {
  final AppDatabase db;
  const PurchasePage({super.key, required this.db});

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<Purchase> _recentPurchases = [];
  List<Supplier> _suppliers = [];
  Supplier? _selectedSupplier;
  bool _isLoading = true;
  double _todayTotal = 0;
  String _paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    final activeSuppliers = await widget.db.supplierDao.getActiveSuppliers();
    if (mounted) {
      setState(() {
        _suppliers = activeSuppliers;
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final todayPurchases = await widget.db.purchaseDao.getTodayPurchases();
      final allPurchases = await widget.db.purchaseDao.getPurchasesByDateRange(
        DateTime.now().subtract(const Duration(days: 30)),
        DateTime.now(),
      );

      _recentPurchases = allPurchases;
      _todayTotal = todayPurchases.fold(0, (sum, p) => sum + p.totalAmount);
    } catch (e) {
      debugPrint('Error loading purchases: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _savePurchase() async {
    if (!_formKey.currentState!.validate()) return;
    if (_paymentMethod == 'credit' && _selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار المورد للمشتريات الآجلة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final purchaseId = await widget.db.purchaseDao.insertPurchaseWithItems(
        supplierId: _selectedSupplier?.id,
        invoiceNumber: 'PUR-${DateTime.now().millisecondsSinceEpoch}',
        description: _descriptionController.text,
        totalAmount: double.parse(_amountController.text),
        paidAmount: _paymentMethod == 'cash'
            ? double.parse(_amountController.text)
            : 0.0,
        paymentMethod: _paymentMethod,
        status: 'completed',
        purchaseDate: DateTime.now(),
        notes: null,
        items: [],
      );

      if (_paymentMethod == 'credit' && _selectedSupplier != null) {
        final supplier = _selectedSupplier!;
        await widget.db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${purchaseId}_ledger',
            entityType: 'Supplier',
            refId: supplier.id,
            date: DateTime.now(),
            description: 'شراء آجل: ${_descriptionController.text}',
            debit: const drift.Value(0.0),
            credit: drift.Value(double.parse(_amountController.text)),
            origin: 'purchase',
          ),
        );
      }

      _descriptionController.clear();
      _amountController.clear();
      setState(() {
        _selectedSupplier = null;
        _paymentMethod = 'cash';
      });
      _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).expense_added_successfully),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving purchase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ العملية: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _createSampleData() async {
    try {
      await widget.db.purchaseDao.insertPurchaseWithItems(
        supplierId: null,
        invoiceNumber: 'SAMPLE-${DateTime.now().millisecondsSinceEpoch}',
        description: 'شراء خامات بلاستيك',
        totalAmount: 500.0,
        paidAmount: 500.0,
        paymentMethod: 'cash',
        status: 'completed',
        purchaseDate: DateTime.now().subtract(const Duration(days: 3)),
        notes: null,
        items: [],
      );

      await widget.db.purchaseDao.insertPurchaseWithItems(
        supplierId: 'sample_supplier_1',
        invoiceNumber: 'SAMPLE-${DateTime.now().millisecondsSinceEpoch + 1}',
        description: 'شراء أوراق وعبوات',
        totalAmount: 250.0,
        paidAmount: 0.0,
        paymentMethod: 'credit',
        status: 'completed',
        purchaseDate: DateTime.now().subtract(const Duration(days: 7)),
        notes: null,
        items: [],
      );

      await widget.db.purchaseDao.insertPurchaseWithItems(
        supplierId: null,
        invoiceNumber: 'SAMPLE-${DateTime.now().millisecondsSinceEpoch + 2}',
        description: 'شراء أدوات مكتبية',
        totalAmount: 150.0,
        paidAmount: 150.0,
        paymentMethod: 'cash',
        status: 'completed',
        purchaseDate: DateTime.now().subtract(const Duration(days: 15)),
        notes: null,
        items: [],
      );

      _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة 3 مشتريات تجريبية بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إضافة البيانات: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _printPurchases() async {
    if (_recentPurchases.isEmpty) return;
    try {
      await PurchasesPdfService.generatePurchasesPdf(_recentPurchases);
    } catch (e) {
      debugPrint('Error printing purchases: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في طباعة التقرير: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final goldColor = const Color(0xFFC9A84C);
    final borderColor = isDark ? const Color(0xFF30363D) : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        title: const Text('المشتريات والمدخلات'),
        actions: [
          IconButton(
            icon: Icon(Icons.print, color: goldColor),
            onPressed: _recentPurchases.isEmpty ? null : _printPurchases,
            tooltip: 'طباعة تقرير المشتريات',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Card(
                color: cardBg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إضافة عملية شراء جديدة',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: goldColor),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _descriptionController,
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  labelText: 'الوصف (مثلاً: خامات، بضاعة)',
                                  labelStyle: TextStyle(color: subTextColor),
                                  border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                  prefixIcon: Icon(Icons.description, color: goldColor),
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF0D1117) : Colors.grey.shade100,
                                ),
                                validator: (val) => val == null || val.isEmpty
                                    ? 'يرجى إدخال الوصف'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                controller: _amountController,
                                keyboardType: TextInputType.number,
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  labelText: 'المبلغ',
                                  labelStyle: TextStyle(color: subTextColor),
                                  border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                  prefixIcon: Icon(Icons.attach_money, color: goldColor),
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF0D1117) : Colors.grey.shade100,
                                ),
                                validator: (val) =>
                                    val == null || double.tryParse(val) == null
                                    ? 'يرجى إدخال السعر'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<Supplier>(
                                initialValue: _selectedSupplier,
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  labelText: 'المورد (اختياري)',
                                  labelStyle: TextStyle(color: subTextColor),
                                  border: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                                  prefixIcon: Icon(Icons.person, color: goldColor),
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF0D1117) : Colors.grey.shade100,
                                ),
                                dropdownColor: cardBg,
                                items: _suppliers.map((s) {
                                  return DropdownMenuItem(
                                    value: s,
                                    child: Text(s.name),
                                  );
                                }).toList(),
                                onChanged: (val) =>
                                    setState(() => _selectedSupplier = val),
                              ),
                            ),
                          ],
                        ),
                        const Gap(16),
                        Row(
                          children: [
                            Text(
                              'طريقة الدفع: ',
                              style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                            ),
                            ChoiceChip(
                              label: const Text('كاش'),
                              selected: _paymentMethod == 'cash',
                              selectedColor: goldColor.withValues(alpha: 0.3),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _paymentMethod = 'cash');
                                }
                              },
                            ),
                            const Gap(8),
                            ChoiceChip(
                              label: const Text('آجل (على الحساب)'),
                              selected: _paymentMethod == 'credit',
                              selectedColor: goldColor.withValues(alpha: 0.3),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _paymentMethod = 'credit');
                                }
                              },
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: _savePurchase,
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة العملية'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: goldColor,
                                foregroundColor: const Color(0xFF0D1117),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  _buildStatCard('إجمالي مشتريات اليوم', _todayTotal, goldColor, cardBg, textColor, borderColor),
                  const SizedBox(width: 16),
                  _buildStatCard('عمليات آخر 30 يوم', _recentPurchases.length.toDouble(), Colors.tealAccent, cardBg, textColor, borderColor, isCurrency: false),
                ],
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'آخر المشتريات',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: textColor),
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _createSampleData,
                        icon: const Icon(Icons.add_circle),
                        label: const Text('إضافة بيانات تجريبية'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const Gap(8),
                      TextButton.icon(
                        onPressed: _loadData,
                        icon: Icon(Icons.refresh, color: goldColor),
                        label: Text('تحديث', style: TextStyle(color: goldColor)),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 400,
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: goldColor))
                    : _recentPurchases.isEmpty
                    ? Center(child: Text('لا توجد مشتريات مسجلة', style: TextStyle(color: subTextColor)))
                    : ListView.builder(
                        itemCount: _recentPurchases.length,
                        itemBuilder: (context, index) {
                          final purchase = _recentPurchases[index];
                          final supplier = _suppliers
                              .where((s) => s.id == purchase.supplierId)
                              .firstOrNull;

                          return Card(
                            color: cardBg,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: borderColor.withValues(alpha: 0.3)),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: purchase.paymentMethod == 'credit'
                                    ? Colors.orange.withValues(alpha: 0.15)
                                    : goldColor.withValues(alpha: 0.15),
                                child: Icon(
                                  purchase.paymentMethod == 'credit'
                                      ? Icons.history
                                      : Icons.shopping_cart,
                                  color: purchase.paymentMethod == 'credit'
                                      ? Colors.orange
                                      : goldColor,
                                ),
                              ),
                              title: Text(purchase.description, style: TextStyle(color: textColor)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('yyyy/MM/dd HH:mm').format(purchase.purchaseDate),
                                    style: TextStyle(color: subTextColor),
                                  ),
                                  if (supplier != null)
                                    Text(
                                      'المورد: ${supplier.name}',
                                      style: TextStyle(color: subTextColor, fontSize: 12),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: (purchase.paymentMethod == 'credit' ? Colors.orange : Colors.green)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      purchase.paymentMethod == 'credit' ? 'آجل' : 'كاش',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: purchase.paymentMethod == 'credit' ? Colors.orange : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(Icons.print, size: 20, color: goldColor),
                                    tooltip: 'إعادة طباعة',
                                    onPressed: () async {
                                      final scaffoldMessenger = ScaffoldMessenger.of(context);

                                      final purchaseItems = [
                                        ups.InvoiceItem(
                                          id: 0,
                                          invoiceId: int.tryParse(purchase.id) ?? 0,
                                          description: purchase.description,
                                          unit: 'قطعة',
                                          quantity: 1,
                                          unitPrice: purchase.totalAmount,
                                          totalPrice: purchase.totalAmount,
                                        ),
                                      ];

                                      final storeInfo = ups.StoreInfo(
                                        storeName: 'المحل التجاري',
                                        phone: '01234567890',
                                        zipCode: '12345',
                                        state: 'القاهرة',
                                      );

                                      final purchaseInvoice = ups.Invoice(
                                        id: int.tryParse(purchase.id) ?? 0,
                                        invoiceNumber: 'PUR-${purchase.id}',
                                        customerName: supplier?.name ?? 'مورد غير محدد',
                                        customerPhone: '',
                                        customerZipCode: '',
                                        customerState: '',
                                        invoiceDate: purchase.purchaseDate,
                                        subtotal: purchase.totalAmount,
                                        isCreditAccount: purchase.paymentMethod.toLowerCase() != 'cash',
                                        previousBalance: 0.0,
                                        totalAmount: purchase.totalAmount,
                                      );

                                      final invoiceData = ups.InvoiceData(
                                        invoice: purchaseInvoice,
                                        items: purchaseItems,
                                        storeInfo: storeInfo,
                                      );

                                      await ups.UnifiedPrintService.printToThermalPrinter(
                                        documentType: ups.DocumentType.salesInvoice,
                                        data: invoiceData,
                                      );
                                    },
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
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    double value,
    Color color,
    Color cardBg,
    Color textColor,
    Color borderColor, {
    bool isCurrency = true,
  }) {
    return Expanded(
      child: Card(
        color: cardBg,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isCurrency
                    ? '${value.toStringAsFixed(2)} ج.م'
                    : value.toInt().toString(),
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
