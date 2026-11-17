import 'dart:math' as math;
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/business_date_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/shipment_allocation_service.dart';
import 'package:pos_offline_desktop/core/services/shipment_pricing_service.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/core/utils/arabic_name_normalizer.dart';

enum _QuickPaymentMode { fullCash, fullCredit, partial }

/// شاشة البيع السريع للموبايل (سوق الخضار - FEAT-038):
/// عميل ← شحنة مفتوحة ← عدد (مع منع البيع الزائد) ← سعر بيع يدوي (بدون سعر افتراضي)
/// ← مدفوع / خصم / آجل ← عهدة البرانيك الفارغة والمستلم منها في نفس العملية.
class QuickSaleScreen extends StatefulWidget {
  final AppDatabase db;

  const QuickSaleScreen({super.key, required this.db});

  @override
  State<QuickSaleScreen> createState() => _QuickSaleScreenState();
}

class _QuickSaleScreenState extends State<QuickSaleScreen> {
  final _formKey = GlobalKey<FormState>();

  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController(); // ALWAYS empty — no default price
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '0');
  final _barnikaOutCtrl = TextEditingController(text: '1');
  final _barnikaReturnedCtrl = TextEditingController(text: '0');

  bool _loading = true;
  bool _submitting = false;
  bool _isDayOpen = true;

  bool _isWalkInCash = false;
  Customer? _selectedCustomer;
  double _customerMoneyBalance = 0.0;
  int _customerBarnikaBalance = 0;

  List<Customer> _customers = [];
  List<VegetableShipment> _openShipments = [];
  Map<String, Supplier> _supplierMap = {};
  VegetableShipment? _selectedShipment;

  _QuickPaymentMode _paymentMode = _QuickPaymentMode.fullCash;
  String _paymentChannel = 'cash'; // cash | bank | card
  bool _customBarnikaOut = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _qtyCtrl.addListener(_onQtyOrPriceChanged);
    _priceCtrl.addListener(_onQtyOrPriceChanged);
    _discountCtrl.addListener(_onQtyOrPriceChanged);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    _barnikaOutCtrl.dispose();
    _barnikaReturnedCtrl.dispose();
    super.dispose();
  }

  int get _qty => int.tryParse(_qtyCtrl.text.trim()) ?? 0;
  double get _unitPrice => double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
  double get _grossTotal => math.max(0.0, _qty * _unitPrice);
  double get _netTotal => math.max(0.0, _grossTotal - _discount);

  int get _maxAvailable => _selectedShipment == null
      ? 0
      : ShipmentAllocationService.effectiveRemaining(_selectedShipment!);

  double get _paidAmount {
    switch (_paymentMode) {
      case _QuickPaymentMode.fullCash:
        return _netTotal;
      case _QuickPaymentMode.fullCredit:
        return 0.0;
      case _QuickPaymentMode.partial:
        return (double.tryParse(_paidCtrl.text.trim()) ?? 0.0)
            .clamp(0.0, _netTotal);
    }
  }

  double get _creditAmount => math.max(0.0, _netTotal - _paidAmount);

  void _onQtyOrPriceChanged() {
    if (!_customBarnikaOut) {
      final q = _qty;
      final nextOut = q > 0 ? q.toString() : '0';
      if (_barnikaOutCtrl.text != nextOut) {
        _barnikaOutCtrl.text = nextOut;
      }
    }
    if (_paymentMode == _QuickPaymentMode.fullCash) {
      _paidCtrl.text = _netTotal.toStringAsFixed(2);
    } else if (_paymentMode == _QuickPaymentMode.fullCredit) {
      _paidCtrl.text = '0';
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    try {
      final isDayOpen = await widget.db.dayDao.isDayOpen();
      final customers = await widget.db.customerDao.getAllActiveCustomers();
      final shipments = await widget.db.vegetableShipmentDao.getOpenShipmentsFifo();
      final suppliers = await widget.db.supplierDao.getAllSuppliers();

      final openAvailable = shipments
          .where((s) => ShipmentAllocationService.effectiveRemaining(s) > 0)
          .toList();

      VegetableShipment? nextSelected;
      if (_selectedShipment != null) {
        final match = openAvailable.where((s) => s.id == _selectedShipment!.id);
        if (match.isNotEmpty) nextSelected = match.first;
      }
      nextSelected ??= openAvailable.isNotEmpty ? openAvailable.first : null;

      if (!mounted) return;
      setState(() {
        _isDayOpen = isDayOpen;
        _customers = customers;
        _openShipments = openAvailable;
        _supplierMap = {for (final s in suppliers) s.id: s};
        _selectedShipment = nextSelected;
        _loading = false;
      });

      if (_selectedCustomer != null) {
        await _refreshCustomerStats(_selectedCustomer!.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل البيانات: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _refreshCustomerStats(String customerId) async {
    final money = await widget.db.ledgerDao.getCustomerBalance(customerId);
    final barnikas = await widget.db.emptyBarnikaTrackingDao
        .getCustomerOutstandingBalance(customerId);
    if (!mounted) return;
    setState(() {
      _customerMoneyBalance = money;
      _customerBarnikaBalance = barnikas;
    });
  }

  Future<void> _openDayQuickDialog() async {
    final ctrl = TextEditingController(text: '0');
    final opening = await showDialog<double>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('فتح يوم جديد'),
          content: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'رصيد الخزينة الافتتاحي',
              prefixText: 'ج.م ',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text.trim()) ?? 0.0;
                if (v < 0) return;
                Navigator.pop(ctx, v);
              },
              child: const Text('فتح اليوم'),
            ),
          ],
        ),
      ),
    );
    if (opening == null || !mounted) return;
    try {
      await BusinessDateService(widget.db).openSession(
        openedBy: 'موظف السوق',
        openingBalance: opening,
      );
      await _loadInitialData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم فتح اليوم بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل فتح اليوم: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _pickCustomerSheet() async {
    final searchCtrl = TextEditingController();
    final picked = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            final q = searchCtrl.text.trim();
            final filtered = q.isEmpty
                ? _customers
                : _customers
                    .where(
                      (c) => ArabicNameNormalizer.matchesQuery(
                        candidate: c.name,
                        query: q,
                        candidatePhone: c.phone,
                      ),
                    )
                    .toList();

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (_, scrollCtrl) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'اختيار الزبون',
                            style: TextStyle(
                              fontFamily: 'NotoSansArabic',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () async {
                            final created = await _showQuickAddCustomerDialog(
                              ctx,
                              initialName: searchCtrl.text.trim(),
                            );
                            if (created != null && ctx.mounted) {
                              Navigator.pop(sheetCtx, created);
                            }
                          },
                          icon: const Icon(Icons.person_add, size: 18),
                          label: const Text('جديد'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'ابحث بالاسم أو الهاتف (تطبيع تلقائي للعربي)...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        suffixIcon: q.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setSheetState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('لا يوجد زبون مطابق'),
                                if (q.isNotEmpty) ...[
                                  const Gap(10),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final created = await _showQuickAddCustomerDialog(
                                        ctx,
                                        initialName: q,
                                      );
                                      if (created != null && ctx.mounted) {
                                        Navigator.pop(sheetCtx, created);
                                      }
                                    },
                                    icon: const Icon(Icons.person_add),
                                    label: Text('إضافة «$q» كزبون جديد'),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollCtrl,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final c = filtered[idx];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      MadarColors.gold.withValues(alpha: 0.15),
                                  child: Text(
                                    c.name.isNotEmpty ? c.name[0] : '؟',
                                    style: const TextStyle(
                                      color: MadarColors.gold,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(c.name),
                                subtitle: c.phone != null && c.phone!.isNotEmpty
                                    ? Text(c.phone!)
                                    : null,
                                onTap: () => Navigator.pop(sheetCtx, c),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        _isWalkInCash = false;
        _selectedCustomer = picked;
      });
      await _refreshCustomerStats(picked.id);
    }
  }

  Future<Customer?> _showQuickAddCustomerDialog(
    BuildContext dialogParentContext, {
    String initialName = '',
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    return showDialog<Customer>(
      context: dialogParentContext,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة زبون جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم الزبون *',
                  border: OutlineInputBorder(),
                ),
              ),
              const Gap(12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'الهاتف (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const Gap(12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'العنوان (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.length < 2) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('أدخل اسم زبون صحيح')),
                  );
                  return;
                }

                // Normalized Arabic duplicate check
                final similar = await widget.db.customerDao.findSimilarCustomers(
                  name: name,
                );
                if (similar.isNotEmpty && ctx.mounted) {
                  final existing = similar.first;
                  final action = await showDialog<String>(
                    context: ctx,
                    builder: (warnCtx) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: AlertDialog(
                        title: const Text('تنبيه تشابه اسم'),
                        content: Text(
                          'يوجد زبون مسجل باسم مشابه: «${existing.name}»'
                          '${existing.phone != null ? ' (${existing.phone})' : ''}.\n'
                          'هل تريد استخدامه بدلاً من التكرار؟',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(warnCtx, 'use'),
                            child: Text('استخدام «${existing.name}»'),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(warnCtx, 'add'),
                            child: const Text('إضافة اسم جديد'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(warnCtx, 'cancel'),
                            child: const Text('مراجعة'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (action == 'use' && ctx.mounted) {
                    Navigator.pop(ctx, existing);
                    return;
                  }
                  if (action != 'add') return;
                }

                try {
                  final id = const Uuid().v4();
                  await widget.db.customerDao.insertCustomer(
                    CustomersCompanion.insert(
                      id: id,
                      name: name,
                      phone: Value(
                        phoneCtrl.text.trim().isEmpty
                            ? null
                            : phoneCtrl.text.trim(),
                      ),
                      address: Value(
                        addressCtrl.text.trim().isEmpty
                            ? null
                            : addressCtrl.text.trim(),
                      ),
                    ),
                  );
                  final created = await widget.db.customerDao.getCustomerById(id);
                  if (created != null && mounted) {
                    setState(() => _customers.add(created));
                  }
                  if (ctx.mounted) Navigator.pop(ctx, created);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('تعذر إضافة الزبون: $e')),
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

  Future<int> _ensureShipmentProductId(VegetableShipment shipment) async {
    final barcode = 'SHP-${shipment.shipmentNumber}';
    final existing = await (widget.db.select(widget.db.products)
          ..where((p) => p.barcode.equals(barcode)))
        .getSingleOrNull();
    if (existing != null) return existing.id;

    final supplierName =
        _supplierMap[shipment.supplierId]?.name ?? 'مورد غير محدد';
    return widget.db.productDao.insertProduct(
      ProductsCompanion(
        name: Value('برنيكة $supplierName - ${shipment.shipmentNumber}'),
        quantity: Value(shipment.totalBarnikaCount),
        price: const Value(0.0),
        unit: const Value('قطعة'),
        category: const Value('خضار - برانيك'),
        barcode: Value(barcode),
        cartonQuantity: Value(shipment.totalBarnikaCount),
        cartonPrice: Value(shipment.totalCost),
        status: const Value('active'),
        barneka: const Value(true),
        costPrice: Value(shipment.costPricePerBarnika ?? 0.0),
      ),
    );
  }

  Future<void> _submitSale() async {
    if (!_isDayOpen) {
      await _openDayQuickDialog();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_selectedShipment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد شحنة مفتوحة مختارة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final shipment = _selectedShipment!;
    final available = ShipmentAllocationService.effectiveRemaining(shipment);
    final qty = _qty;
    if (qty <= 0 || qty > available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('الكمية المطلوبة ($qty) غير متاحة (المتبقي: $available)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_isWalkInCash && _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر الزبون أو فعّل خيار «عميل نقدي»'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final credit = _creditAmount;
    if (credit > 0.01 && _isWalkInCash) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('البيع الآجل أو الجزئي يتطلب اختيار زبون مسجل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final barnikaOut = _isWalkInCash
        ? 0
        : (int.tryParse(_barnikaOutCtrl.text.trim()) ?? qty);
    final barnikaReturned = _isWalkInCash
        ? 0
        : (int.tryParse(_barnikaReturnedCtrl.text.trim()) ?? 0);

    if (!_isWalkInCash && barnikaReturned > barnikaOut + _customerBarnikaBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'البرانيك المستلمة ($barnikaReturned) تتجاوز إجمالي العهدة المتاحة '
            '(${barnikaOut + _customerBarnikaBalance})',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final productId = await _ensureShipmentProductId(shipment);
      final paid = _paidAmount;
      final netTotal = _netTotal;
      final paymentMethod = paid <= 0.005
          ? 'credit'
          : (credit <= 0.005 ? _paymentChannel : 'mixed');
      final status = credit <= 0.005
          ? 'paid'
          : (paid > 0.005 ? 'partial' : 'pending');

      final cashPart = _paymentChannel == 'cash' ? paid : 0.0;
      final cardPart = _paymentChannel != 'cash' ? paid : 0.0;

      final commPct = shipment.commissionPercentage ?? 0.0;
      final commission = shipment.pricingMode == ShipmentPricingMode.commission &&
              commPct > 0
          ? ShipmentPricingService.calculateCommission(netTotal, commPct)
          : 0.0;

      final result = await InvoiceService(widget.db).createInvoice(
        customerId: _isWalkInCash ? null : _selectedCustomer!.id,
        customerName: _isWalkInCash ? 'عميل نقدي' : _selectedCustomer!.name,
        customerContact: _isWalkInCash ? '' : _selectedCustomer!.phone,
        customerAddress: _isWalkInCash ? '' : _selectedCustomer!.address,
        paymentMethod: paymentMethod,
        totalAmount: netTotal,
        paidAmount: paid,
        cashAmount: cashPart,
        cardAmount: cardPart,
        creditAmount: credit,
        status: status,
        primaryShipmentId: shipment.id,
        emptyBarnikaOutCount: _isWalkInCash ? 0 : barnikaOut,
        emptyBarnikaReturnedCount: _isWalkInCash ? 0 : barnikaReturned,
        items: [
          InvoiceItemParams(
            productId: productId,
            quantity: qty,
            price: _unitPrice,
            discount: _discount,
            commission: commission,
            shipmentId: shipment.id,
          ),
        ],
      );

      final invNo =
          displayInvoiceNumber(result.invoice.invoiceNumber, result.invoiceId) ??
              '#${result.invoiceId}';

      // Reset inputs for next fast entry
      _qtyCtrl.text = '1';
      _priceCtrl.clear(); // Always reset to empty — manual entry every sale
      _discountCtrl.text = '0';
      _paidCtrl.text = '0';
      _customBarnikaOut = false;
      _barnikaOutCtrl.text = '1';
      _barnikaReturnedCtrl.text = '0';

      await _loadInitialData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ تم تسجيل البيعة $invNo بنجاح (${netTotal.toStringAsFixed(2)} ج.م)'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تسجيل البيعة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بيع سريع (سوق الخضار)'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _loadInitialData,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_isDayOpen) ...[
                        Card(
                          color: Colors.red.withValues(alpha: isDark ? 0.16 : 0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.red.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lock_clock,
                                  color: isDark
                                      ? Colors.red.shade200
                                      : Colors.red.shade800,
                                ),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                    'اليوم المالي مغلق حالياً. افتح اليوم للبدء بالبيع.',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.red.shade200
                                          : Colors.red.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                FilledButton(
                                  onPressed: _openDayQuickDialog,
                                  child: const Text('فتح اليوم'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Gap(10),
                      ],

                      // 1. Customer section
                      _buildCustomerCard(theme),
                      const Gap(12),

                      // 2. Shipment section
                      _buildShipmentCard(theme),
                      const Gap(12),

                      // 3. Quantity & Manual Price
                      _buildQuantityPriceCard(theme),
                      const Gap(12),

                      // 4. Payment & Discount
                      _buildPaymentCard(theme),
                      const Gap(12),

                      // 5. Empty Barnika Custody (tied to sale)
                      if (!_isWalkInCash && _selectedCustomer != null) ...[
                        _buildBarnikaCard(theme),
                        const Gap(16),
                      ],

                      // 6. Confirm sale button
                      FilledButton.icon(
                        onPressed:
                            (_submitting || _openShipments.isEmpty) ? null : _submitSale,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 22),
                        label: Text(
                          _submitting
                              ? 'جاري التسجيل...'
                              : 'تسجيل البيعة (${_netTotal.toStringAsFixed(2)} ج.م)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF238636),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const Gap(24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildCustomerCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person, color: Color(0xFF388BFD)),
                    Gap(8),
                    Text(
                      '1. الزبون',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                ChoiceChip(
                  label: const Text('زبون مسجل'),
                  selected: !_isWalkInCash,
                  onSelected: (_) => setState(() => _isWalkInCash = false),
                ),
                ChoiceChip(
                  label: const Text('عميل نقدي'),
                  selected: _isWalkInCash,
                  onSelected: (_) => setState(() {
                    _isWalkInCash = true;
                    _paymentMode = _QuickPaymentMode.fullCash;
                    _paidCtrl.text = _netTotal.toStringAsFixed(2);
                  }),
                ),
              ],
            ),
            if (!_isWalkInCash) ...[
              const Gap(10),
              InkWell(
                onTap: _pickCustomerSheet,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.35),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 20),
                      const Gap(10),
                      Expanded(
                        child: Text(
                          _selectedCustomer?.name ?? 'اضغط لاختيار أو إضافة زبون...',
                          style: TextStyle(
                            fontWeight: _selectedCustomer != null
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _selectedCustomer != null
                                ? theme.colorScheme.onSurface
                                : Colors.grey,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              if (_selectedCustomer != null) ...[
                const Gap(10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      avatar: Icon(
                        Icons.account_balance_wallet,
                        size: 16,
                        color: _customerMoneyBalance > 0
                            ? Colors.red
                            : Colors.green,
                      ),
                      label: Text(
                        'الرصيد الآجل: ${_customerMoneyBalance.toStringAsFixed(2)} ج.م',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Chip(
                      avatar: const Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: Colors.orange,
                      ),
                      label: Text(
                        'عهدة البرانيك: $_customerBarnikaBalance',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShipmentCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_shipping, color: Color(0xFF238636)),
                Gap(8),
                Expanded(
                  child: Text(
                    '2. الشحنة المفتوحة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const Gap(10),
            if (_openShipments.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: isDark ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  'لا توجد شحنات مفتوحة بها برانيك متاحة للبيع حالياً.',
                  style: TextStyle(
                    color: isDark ? Colors.orange.shade200 : Colors.orange.shade900,
                  ),
                ),
              )
            else ...[
              DropdownButtonFormField<VegetableShipment>(
                initialValue: _selectedShipment,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'اختر الشحنة *',
                ),
                items: _openShipments.map((s) {
                  final supName = _supplierMap[s.supplierId]?.name ?? 'مورد غير محدد';
                  final rem = ShipmentAllocationService.effectiveRemaining(s);
                  final dateStr = DateFormat('MM/dd').format(s.date);
                  return DropdownMenuItem(
                    value: s,
                    child: Text(
                      '#${s.shipmentNumber} — $supName | متبقي: $rem | $dateStr',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedShipment = val;
                    if (val != null) {
                      final maxAvail = ShipmentAllocationService.effectiveRemaining(val);
                      if (_qty > maxAvail && maxAvail > 0) {
                        _qtyCtrl.text = maxAvail.toString();
                      }
                    }
                  });
                },
              ),
              if (_selectedShipment != null) ...[
                const Gap(8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      'المتاح للبيع: $_maxAvailable برنيكة',
                      style: const TextStyle(
                        color: Color(0xFF238636),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_selectedShipment!.pricingMode ==
                        ShipmentPricingMode.commission)
                      Text(
                        'عمولة: ${(_selectedShipment!.commissionPercentage ?? 0).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: isDark
                              ? Colors.orange.shade300
                              : Colors.orange.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityPriceCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calculate_outlined, color: MadarColors.gold),
                Gap(8),
                Expanded(
                  child: Text(
                    '3. العدد وسعر البيع اليدوي',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const Gap(12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 380;
                final qtyField = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('عدد البرانيك *', style: TextStyle(fontSize: 12)),
                    const Gap(4),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 44,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: _qty > 1
                              ? () => _qtyCtrl.text = (_qty - 1).toString()
                              : null,
                          icon: const Icon(Icons.remove, size: 18),
                        ),
                        const Gap(4),
                        Expanded(
                          child: TextFormField(
                            controller: _qtyCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                            validator: (v) {
                              final q = int.tryParse(v?.trim() ?? '');
                              if (q == null || q <= 0) return 'أدخل كمية > 0';
                              if (_selectedShipment != null &&
                                  q > _maxAvailable) {
                                return 'المتاح $_maxAvailable فقط';
                              }
                              return null;
                            },
                          ),
                        ),
                        const Gap(4),
                        IconButton.filledTonal(
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 44,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: _qty < _maxAvailable
                              ? () => _qtyCtrl.text = (_qty + 1).toString()
                              : null,
                          icon: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                  ],
                );
                final priceField = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'سعر البرنيكة (يدوي) *',
                      style: TextStyle(fontSize: 12),
                    ),
                    const Gap(4),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'اكتب السعر...',
                        suffixText: 'ج.م',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                      ),
                      validator: (v) {
                        final p = double.tryParse(v?.trim() ?? '');
                        if (p == null || p <= 0) {
                          return 'اكتب السعر يدوياً';
                        }
                        return null;
                      },
                    ),
                  ],
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      qtyField,
                      const Gap(10),
                      priceField,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: qtyField),
                    const Gap(12),
                    Expanded(child: priceField),
                  ],
                );
              },
            ),
            const Gap(10),
            LayoutBuilder(
              builder: (context, constraints) {
                final discountField = TextFormField(
                  controller: _discountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'خصم (اختياري)',
                    suffixText: 'ج.م',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final d = double.tryParse(v.trim());
                    if (d == null || d < 0) return 'خصم غير صحيح';
                    if (d > _grossTotal) return 'الخصم أكبر من الإجمالي';
                    return null;
                  },
                );
                final netBox = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: MadarColors.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: MadarColors.gold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('الصافي المطلوب', style: TextStyle(fontSize: 11)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${_netTotal.toStringAsFixed(2)} ج.م',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: MadarColors.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (constraints.maxWidth < 320) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      discountField,
                      const Gap(10),
                      netBox,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: discountField),
                    const Gap(12),
                    netBox,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.payments_outlined, color: Colors.indigo),
                Gap(8),
                Expanded(
                  child: Text(
                    '4. التحصيل وطريقة الدفع',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const Gap(10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('كاش كامل'),
                  selected: _paymentMode == _QuickPaymentMode.fullCash,
                  onSelected: (_) {
                    setState(() {
                      _paymentMode = _QuickPaymentMode.fullCash;
                      _paidCtrl.text = _netTotal.toStringAsFixed(2);
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('آجل بالكامل'),
                  selected: _paymentMode == _QuickPaymentMode.fullCredit,
                  onSelected: _isWalkInCash
                      ? null
                      : (_) {
                          setState(() {
                            _paymentMode = _QuickPaymentMode.fullCredit;
                            _paidCtrl.text = '0';
                          });
                        },
                ),
                ChoiceChip(
                  label: const Text('دفع جزئي'),
                  selected: _paymentMode == _QuickPaymentMode.partial,
                  onSelected: _isWalkInCash
                      ? null
                      : (_) {
                          setState(() {
                            _paymentMode = _QuickPaymentMode.partial;
                            _paidCtrl.text = '';
                          });
                        },
                ),
              ],
            ),
            const Gap(10),
            Row(
              children: [
                if (_paymentMode == _QuickPaymentMode.partial) ...[
                  Expanded(
                    child: TextFormField(
                      controller: _paidCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'المدفوع الآن *',
                        suffixText: 'ج.م',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (_paymentMode != _QuickPaymentMode.partial) {
                          return null;
                        }
                        final p = double.tryParse(v?.trim() ?? '');
                        if (p == null || p < 0 || p > _netTotal) {
                          return 'مبلغ بين 0 و ${_netTotal.toStringAsFixed(2)}';
                        }
                        return null;
                      },
                    ),
                  ),
                  const Gap(10),
                ],
                if (_paymentMode != _QuickPaymentMode.fullCredit)
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _paymentChannel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'وسيلة الدفع',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('نقدي (كاش)')),
                        DropdownMenuItem(value: 'bank', child: Text('تحويل / إنستاباي')),
                        DropdownMenuItem(value: 'card', child: Text('بطاقة / محفظة')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _paymentChannel = v);
                      },
                    ),
                  ),
              ],
            ),
            const Gap(8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  'المدفوع: ${_paidAmount.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'المتبقي آجل: ${_creditAmount.toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    color: _creditAmount > 0 ? Colors.red : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarnikaCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final outVal = int.tryParse(_barnikaOutCtrl.text.trim()) ?? 0;
    final retVal = int.tryParse(_barnikaReturnedCtrl.text.trim()) ?? 0;
    final afterBalance = _customerBarnikaBalance + outVal - retVal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_return_outlined, color: Colors.teal),
                const Gap(8),
                const Expanded(
                  child: Text(
                    '5. عهدة البرانيك الفارغة (مربوطة بالبيعة)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _barnikaReturnedCtrl.text = _barnikaOutCtrl.text;
                    });
                  },
                  child: const Text('استلام الكل'),
                ),
              ],
            ),
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _barnikaOutCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'برانيك خارجة',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      _customBarnikaOut = true;
                      setState(() {});
                    },
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: TextFormField(
                    controller: _barnikaReturnedCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'البرانيك المستلمة الآن',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const Gap(8),
            Text(
              'رصيد البرانيك بعد البيعة: ${math.max(0, afterBalance)} برنيكة فارغة على الزبون',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
