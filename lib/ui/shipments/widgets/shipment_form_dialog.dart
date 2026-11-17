import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/supplier_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';

class ShipmentFormDialog extends StatefulWidget {
  final AppDatabase db;
  final VegetableShipment? shipment;

  const ShipmentFormDialog({
    super.key,
    required this.db,
    this.shipment,
  });

  @override
  State<ShipmentFormDialog> createState() => _ShipmentFormDialogState();
}

class _ShipmentFormDialogState extends State<ShipmentFormDialog> {
  final _formKey = GlobalKey<FormState>();

  Supplier? _selectedSupplier;
  List<Supplier> _suppliers = [];
  bool _loadingSuppliers = true;

  late String _pricingMode;
  final _shipmentNumberCtrl = TextEditingController();
  final _totalBarnikaCtrl = TextEditingController();
  final _costPerBarnikaCtrl = TextEditingController();
  final _lumpSumCostCtrl = TextEditingController();
  final _commissionPercentageCtrl = TextEditingController();
  final _containerPriceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pricingMode = widget.shipment?.pricingMode ??
        (AppFeatures.hasCommissionPricing
            ? ShipmentPricingMode.commission
            : ShipmentPricingMode.perUnit);

    if (widget.shipment != null) {
      final s = widget.shipment!;
      _shipmentNumberCtrl.text = s.shipmentNumber;
      _totalBarnikaCtrl.text = s.totalBarnikaCount.toString();
      if (s.costPricePerBarnika != null) {
        _costPerBarnikaCtrl.text = s.costPricePerBarnika.toString();
      }
      if (s.lumpSumCost != null) {
        _lumpSumCostCtrl.text = s.lumpSumCost.toString();
      }
      if (s.commissionPercentage != null) {
        _commissionPercentageCtrl.text = s.commissionPercentage.toString();
      }
      if (s.containerPrice != null) {
        _containerPriceCtrl.text = s.containerPrice.toString();
      }
      if (s.notes != null) {
        _notesCtrl.text = s.notes!;
      }
      _selectedDate = s.date;
    } else {
      _shipmentNumberCtrl.text =
          'SHP-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    }

    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    try {
      final dbSuppliers = await widget.db.supplierDao.getActiveSuppliers();
      final unknownPlaceholder = Supplier(
        id: DefaultSupplier.unknownId,
        name: DefaultSupplier.unknownName,
        phone: null,
        address: null,
        openingBalance: 0.0,
        createdAt: DateTime.now(),
        status: 'Active',
      );
      final list = <Supplier>[
        unknownPlaceholder,
        ...dbSuppliers.where((s) => s.id != DefaultSupplier.unknownId),
      ];
      setState(() {
        _suppliers = list;
        _loadingSuppliers = false;
        if (widget.shipment != null) {
          final matches =
              list.where((s) => s.id == widget.shipment!.supplierId);
          _selectedSupplier =
              matches.isNotEmpty ? matches.first : list.first;
        } else {
          // Default to «مورد غير محدد» so supplier is optional on arrival
          _selectedSupplier = list.first;
        }
      });
    } catch (e) {
      setState(() {
        _loadingSuppliers = false;
        _errorMessage = 'فشل تحميل الموردين: $e';
      });
    }
  }

  @override
  void dispose() {
    _shipmentNumberCtrl.dispose();
    _totalBarnikaCtrl.dispose();
    _costPerBarnikaCtrl.dispose();
    _lumpSumCostCtrl.dispose();
    _commissionPercentageCtrl.dispose();
    _containerPriceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double _calculateTotalCost() {
    final qty = int.tryParse(_totalBarnikaCtrl.text) ?? 0;
    final costPerBarnika = double.tryParse(_costPerBarnikaCtrl.text);
    final lumpSum = double.tryParse(_lumpSumCostCtrl.text);

    switch (_pricingMode) {
      case ShipmentPricingMode.perUnit:
        return (costPerBarnika ?? 0) * qty;
      case ShipmentPricingMode.lumpSum:
        return lumpSum ?? 0;
      case ShipmentPricingMode.commission:
        return 0;
      default:
        return 0;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final number = _shipmentNumberCtrl.text.trim();

    // Check shipment number uniqueness on creation
    if (widget.shipment == null) {
      final existing =
          await widget.db.vegetableShipmentDao.getByShipmentNumber(number);
      if (existing != null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'رقم الشحنة موجود بالفعل، يرجى اختيار رقم آخر';
        });
        return;
      }
    }

    final totalCount = int.parse(_totalBarnikaCtrl.text.trim());
    final totalCost = _calculateTotalCost();
    final containerPrice = double.tryParse(_containerPriceCtrl.text.trim());
    final supplierId = _selectedSupplier?.id ?? DefaultSupplier.unknownId;
    final supplierName =
        _selectedSupplier?.name ?? DefaultSupplier.unknownName;

    double? costPerBarnika;
    double? lumpSumCost;
    double? commissionPercentage;

    switch (_pricingMode) {
      case ShipmentPricingMode.perUnit:
        costPerBarnika = double.parse(_costPerBarnikaCtrl.text.trim());
        break;
      case ShipmentPricingMode.lumpSum:
        lumpSumCost = double.parse(_lumpSumCostCtrl.text.trim());
        break;
      case ShipmentPricingMode.commission:
        commissionPercentage =
            double.parse(_commissionPercentageCtrl.text.trim());
        break;
    }

    try {
      if (widget.shipment == null) {
        final companion = VegetableShipmentsCompanion(
          supplierId: Value(supplierId),
          shipmentNumber: Value(number),
          date: Value(_selectedDate),
          pricingMode: Value(_pricingMode),
          totalBarnikaCount: Value(totalCount),
          barnikaRemainingCount: Value(totalCount),
          costPricePerBarnika: Value(costPerBarnika),
          lumpSumCost: Value(lumpSumCost),
          commissionPercentage: Value(commissionPercentage),
          containerPrice: Value(containerPrice),
          totalCost: Value(totalCost),
          notes: Value(
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
        );
        await widget.db.vegetableShipmentDao.insertShipment(companion);

        // Vegetable flavor: auto-create product for this shipment (barnika/crate)
        final productName = 'برنيكة $supplierName - $number';
        await widget.db.productDao.insertProduct(
          ProductsCompanion(
            name: Value(productName),
            price: Value(containerPrice ?? costPerBarnika ?? 0),
            unit: const Value('قطعة'),
            category: const Value('خضار - برانيك'),
            barcode: Value('SHP-$number'),
            cartonQuantity: Value(totalCount),
            cartonPrice: Value(totalCost),
            status: const Value('active'),
            barneka: const Value(true),
            costPrice: Value(costPerBarnika ?? 0),
          ),
        );
      } else {
        if (supplierId == DefaultSupplier.unknownId) {
          await widget.db.supplierDao.ensureUnknownSupplier();
        }
        final s = widget.shipment!;
        final newRemaining =
            (totalCount - s.barnikaSoldCount - s.toppingCount)
                .clamp(0, 1 << 30);
        final updated = s.copyWith(
          supplierId: supplierId,
          shipmentNumber: number,
          date: _selectedDate,
          pricingMode: _pricingMode,
          totalBarnikaCount: totalCount,
          barnikaRemainingCount: newRemaining,
          costPricePerBarnika: Value(costPerBarnika),
          lumpSumCost: Value(lumpSumCost),
          commissionPercentage: Value(commissionPercentage),
          containerPrice: Value(containerPrice),
          totalCost: totalCost,
          notes: Value(
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
        );
        await widget.db.vegetableShipmentDao.updateShipment(updated);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'حدث خطأ أثناء الحفظ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth =
        math.min(540.0, MediaQuery.of(context).size.width * 0.94);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth,
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 380;
              final shipmentNumberField = TextFormField(
                controller: _shipmentNumberCtrl,
                decoration: const InputDecoration(
                  labelText: 'رقم الشحنة *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag),
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'رقم الشحنة مطلوب'
                    : null,
              );
              final shipmentDateField = InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'تاريخ الشحنة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    DateFormat('yyyy/MM/dd').format(_selectedDate),
                  ),
                ),
              );
              final containerPriceField = TextFormField(
                controller: _containerPriceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'سعر تأمين البرنيكة (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.shield_outlined),
                ),
              );
              final calculatedCostBox = Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pricingMode == ShipmentPricingMode.commission
                          ? 'نظام التحاسب:'
                          : 'التكلفة الإجمالية المحسوبة:',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      _pricingMode == ShipmentPricingMode.commission
                          ? 'عمولة من إجمالي البيع'
                          : '${_calculateTotalCost().toStringAsFixed(2)} ج.م',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              );

              return Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          widget.shipment == null
                              ? Icons.add_business
                              : Icons.edit,
                          color: theme.colorScheme.primary,
                          size: 26,
                        ),
                        const Gap(10),
                        Expanded(
                          child: Text(
                            widget.shipment == null
                                ? 'استلام شحنة جديدة'
                                : 'تعديل بيانات الشحنة',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      const Gap(16),
                    ],

                    // Supplier picker (optional on arrival — defaults to «مورد غير محدد»)
                    if (_loadingSuppliers)
                      const Center(child: CircularProgressIndicator())
                    else
                      DropdownButtonFormField<Supplier>(
                        initialValue: _selectedSupplier,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'المورد (اختياري وقت الاستلام)',
                          helperText:
                              'يمكن تركه «مورد غير محدد» وتعيينه لاحقاً قبل قفل الشحنة',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        items: _suppliers
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s.id == DefaultSupplier.unknownId
                                      ? '${s.name} (تحديد لاحقاً)'
                                      : '${s.name}${s.phone != null ? ' (${s.phone})' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedSupplier = val),
                      ),
                    const Gap(16),

                    // Shipment number & date (stacked on narrow mobile screens)
                    if (isCompact) ...[
                      shipmentNumberField,
                      const Gap(12),
                      shipmentDateField,
                    ] else
                      Row(
                        children: [
                          Expanded(child: shipmentNumberField),
                          const Gap(12),
                          Expanded(child: shipmentDateField),
                        ],
                      ),
                    const Gap(20),

                    // Pricing mode selector
                    Text(
                      'نظام التسعير *',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Gap(8),
                    Row(
                      children: [
                        _buildPricingChoiceChip(
                          mode: ShipmentPricingMode.perUnit,
                          label: isCompact ? 'بالسعر' : 'بالسعر/سعر البرنيكة',
                          icon: Icons.filter_1,
                        ),
                        const Gap(8),
                        _buildPricingChoiceChip(
                          mode: ShipmentPricingMode.lumpSum,
                          label: isCompact ? 'جملة' : 'جملة (Lump Sum)',
                          icon: Icons.all_inclusive,
                        ),
                        const Gap(8),
                        _buildPricingChoiceChip(
                          mode: ShipmentPricingMode.commission,
                          label: isCompact ? 'عمولة' : 'عمولة (Commission)',
                          icon: Icons.percent,
                        ),
                      ],
                    ),
                    const Gap(16),

                    // Total Barnika Count
                    TextFormField(
                      controller: _totalBarnikaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'عدد البرانيك الكلي *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.inventory_2),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (val) {
                        final n = int.tryParse(val ?? '');
                        if (n == null || n <= 0) {
                          return 'ادخل عدد برانيك صحيح أكبر من 0';
                        }
                        return null;
                      },
                    ),
                    const Gap(16),

                    // Mode-specific inputs
                    if (_pricingMode == ShipmentPricingMode.perUnit) ...[
                      TextFormField(
                        controller: _costPerBarnikaCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'سعر التكلفة للبرنيكة الواحدة (ج.م) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (val) {
                          final n = double.tryParse(val ?? '');
                          if (n == null || n < 0) return 'ادخل سعر تكلفة صحيح';
                          return null;
                        },
                      ),
                      const Gap(16),
                    ] else if (_pricingMode == ShipmentPricingMode.lumpSum) ...[
                      TextFormField(
                        controller: _lumpSumCostCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'إجمالي تكلفة الشحنة (جملة) (ج.م) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.account_balance_wallet),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (val) {
                          final n = double.tryParse(val ?? '');
                          if (n == null || n < 0) {
                            return 'ادخل التكلفة الإجمالية الصحيحة';
                          }
                          return null;
                        },
                      ),
                      const Gap(16),
                    ] else if (_pricingMode == ShipmentPricingMode.commission) ...[
                      TextFormField(
                        controller: _commissionPercentageCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'نسبة عمولة المحل (%) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.percent),
                          suffixText: '%',
                        ),
                        validator: (val) {
                          final n = double.tryParse(val ?? '');
                          if (n == null || n < 0 || n > 100) {
                            return 'ادخل نسبة بين 0 و 100%';
                          }
                          return null;
                        },
                      ),
                      const Gap(16),
                    ],

                    // Container price & calculated cost
                    if (isCompact) ...[
                      containerPriceField,
                      const Gap(12),
                      calculatedCostBox,
                    ] else
                      Row(
                        children: [
                          Expanded(child: containerPriceField),
                          const Gap(12),
                          Expanded(child: calculatedCostBox),
                        ],
                      ),
                    const Gap(16),

                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات (اختياري)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note_alt_outlined),
                      ),
                    ),
                    const Gap(24),

                    // Submit buttons
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _submit,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(
                            widget.shipment == null
                                ? 'إضافة الشحنة'
                                : 'حفظ التعديلات',
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPricingChoiceChip({
    required String mode,
    required String label,
    required IconData icon,
  }) {
    final selected = _pricingMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _pricingMode = mode),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade400,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                size: 20,
              ),
              const Gap(4),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
