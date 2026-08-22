import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/label_print_service.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/services/windows_printer_paper_size.dart';

class LabelPrintPage extends StatefulWidget {
  final AppDatabase db;

  const LabelPrintPage({super.key, required this.db});

  @override
  State<LabelPrintPage> createState() => _LabelPrintPageState();
}

class _LabelPrintPageState extends State<LabelPrintPage> {
  List<Product> _products = [];
  final Map<int, bool> _selected = {};
  final Map<int, int> _copies = {};
  final Map<int, TextEditingController> _copyCtrls = {};
  final Map<int, TextEditingController> _barcodeCtrls = {};

  final _companyCtrl = TextEditingController();
  bool _showPrice = true;
  bool _loading = true;
  String? _detectedPrinter;
  String? _detectedSizeText;
  String _selectedPreset = '1.5×1.0in (38×25mm)';
  double _customWidth = 38.1;
  double _customHeight = 25.4;
  bool _customSize = false;
  // لو المستخدم اختار مقاس يدويًا (preset أو مخصص) — يبقى اختياره هو المعتمد
  // وقراءة مقاس الويندوز التلقائية ماتتغلبش عليه.
  bool _manualSize = false;

  static const _presets = {
    '1.5×1.0in (38×25mm)': [38.1, 25.4],
    '50×30mm': [50.0, 30.0],
    '50×50mm': [50.0, 50.0],
    '58×30mm': [58.0, 30.0],
    '58×40mm': [58.0, 40.0],
    '58×50mm': [58.0, 50.0],
    '70×40mm': [70.0, 40.0],
    '70×50mm': [70.0, 50.0],
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final company = await SettingsService.getBusinessName();
    _companyCtrl.text = company;

    final products = await widget.db.productDao.getAllProducts();
    // لو فيه منتجات قديمة لسه مالهاش باركود محفوظ — نولّد ونحفظ لها باركود
    // فورًا (نفس معادلة إضافة المنتج 10000000 + المعرف) عشان الكود اللي
    // بيظهر هنا يبقى هو نفسه اللي بيتسجل في المنتجات وقابل للبحث والمسح.
    for (final p in products) {
      if ((p.barcode?.trim() ?? '').isEmpty) {
        await widget.db.productDao
            .updateProductBarcode(p.id, '${10000000 + p.id}');
      }
    }

    // إعادة قراءة المنتجات بعد التوليد حتى تظهر الباركودات المحفوظة
    final updatedProducts = await widget.db.productDao.getAllProducts();
    setState(() {
      _products = updatedProducts;
      for (final p in updatedProducts) {
        _copies[p.id] = 1;
        _copyCtrls[p.id]?.dispose();
        _copyCtrls[p.id] = TextEditingController(text: '1');
        String barcodeVal = p.barcode?.trim() ?? '';
        if (barcodeVal.isEmpty) {
          // توليد باركود تلقائي فريد يعتمد على معرف المنتج (مثلاً 10000000 + المعرف)
          barcodeVal = '${10000000 + p.id}';
        }
        _barcodeCtrls[p.id] = TextEditingController(text: barcodeVal);
      }
      _loading = false;
    });

    // قراءة مقاس الورق من برينتر الويندوز تلقائياً — أي مقاس يضبطه
    // المستخدم في إعدادات الطباعة يتبعه التطبيق مباشرة بدون تدخل.
    await _applyWindowsPrinterSize();
  }

  /// يقرأ مقاس الورق من برينتر الويندوز الافتراضي ويطبقه على الملصقات.
  /// يطبَّق تلقائياً لو المقاس مقاس لصاقة (العرض بين 20 و 100 مم)
  /// حتى لا يخطف مقاس A4 أو أي مقاس ورق عادي بالغلط.
  /// اختيار المستخدم اليدوي دائمًا له الأولوية — التلقائي يشتغل بس
  /// لو مفيش اختيار يدوي (المرة الأولى أو عند إعادة فتح الصفحة).
  Future<void> _applyWindowsPrinterSize() async {
    if (_manualSize) return;
    final size = await WindowsPrinterPaperSize.detect();
    if (!mounted || size == null) return;
    final isLabelSize =
        size.widthMm >= 20 && size.widthMm <= 100 && size.heightMm > 0;
    if (!isLabelSize) return;
    setState(() {
      _detectedPrinter = size.printerName;
      _detectedSizeText =
          '${size.widthMm.toStringAsFixed(1)}×${size.heightMm.toStringAsFixed(1)} مم';
      _customSize = true;
      _customWidth = size.widthMm;
      _customHeight = size.heightMm;
    });
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    for (final c in _barcodeCtrls.values) {
      c.dispose();
    }
    for (final c in _copyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Product> get _selectedProducts =>
      _products.where((p) => _selected[p.id] == true).toList();

  bool get _hasSelection => _selected.values.any((v) => v);

  double get _currentWidth => _customSize ? _customWidth : _presets[_selectedPreset]![0];
  double get _currentHeight => _customSize ? _customHeight : _presets[_selectedPreset]![1];

  void _selectAll() {
    setState(() {
      final allSelected = _products.every((p) => _selected[p.id] == true);
      for (final p in _products) {
        _selected[p.id] = !allSelected;
      }
    });
  }

  /// تعيين عدد النسخ لمنتج — يمنع القيم الأقل من 1 ويزامن حقل الكتابة.
  void _setCopies(int productId, int value) {
    final v = value < 1 ? 1 : value;
    setState(() {
      _copies[productId] = v;
      final ctrl = _copyCtrls[productId];
      if (ctrl != null && ctrl.text != '$v') {
        ctrl.text = '$v';
      }
    });
  }

  Future<void> _print() async {
    final selected = _selectedProducts;
    if (selected.isEmpty) return;

    final copies = <int, int>{};

    // فحص تعارضات الباركود قبل الطباعة: لو الكود مستخدم بالفعل لمنتج آخر
    // نمنع طباعة كود خاطئ على الملصق (الكود مش هيتحفظ ولا هيتطبع).
    final conflictedIds = <int>{};
    final newBarcodes = <int, String>{};
    for (final p in selected) {
      final inputBarcode = _barcodeCtrls[p.id]?.text.trim() ?? '';
      if (inputBarcode.isEmpty || inputBarcode == p.barcode?.trim()) continue;
      final existing = await widget.db.productDao.getProductByBarcode(
        inputBarcode,
      );
      if (existing != null && existing.id != p.id) {
        conflictedIds.add(p.id);
      } else {
        newBarcodes[p.id] = inputBarcode;
      }
    }

    if (!mounted) return;
    if (conflictedIds.isNotEmpty) {
      final conflictsText = conflictedIds.map((id) {
        final p = selected.firstWhere((x) => x.id == id);
        return '«${p.name}» → كود ${_barcodeCtrls[id]?.text.trim()}';
      }).join('\n');
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تعارض في الباركود'),
            content: Text(
              'الباركودات التالية مستخدمة بالفعل لمنتجات أخرى ولن تُطبع على الملصقات:\n\n$conflictsText\n\nهل تريد الاستمرار؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('استمرار'),
              ),
            ],
          ),
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final barcodeData = <int, String>{};
    for (final p in selected) {
      copies[p.id] = _copies[p.id] ?? 1;
      barcodeData[p.id] = conflictedIds.contains(p.id)
          ? ''
          : (_barcodeCtrls[p.id]?.text.trim() ?? '');
    }

    // إعادة قراءة مقاس الويندوز عند الطباعة حتى لو اتغير بعد فتح الصفحة.
    await _applyWindowsPrinterSize();
    if (!mounted) return;

    // إظهار مؤشر التحميل أثناء التجهيز
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('جاري تجهيز الملصقات للطباعة...'),
            ],
          ),
        ),
      ),
    );

    try {
      // حفظ الباركودات الجديدة أو المعدلة في قاعدة البيانات لتصبح قابلة للمسح والتعرف عليها في الكاشير
      for (final e in newBarcodes.entries) {
        await widget.db.productDao.updateProductBarcode(e.key, e.value);
      }

      await LabelPrintService.printProductLabels(
        products: selected,
        copiesPerProduct: copies,
        companyName: _companyCtrl.text,
        showPrice: _showPrice,
        barcodeData: barcodeData,
        widthMm: _currentWidth,
        heightMm: _currentHeight,
      );
      if (mounted) {
        Navigator.of(context).pop(); // إغلاق مؤشر التحميل
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // إغلاق مؤشر التحميل
      }
      debugPrint('Label print error: $e');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('خطأ في الطباعة'),
          content: Text('تعذر الطباعة. تأكد من توصيل الطابعة والمحاولة مرة أخرى.\n\n$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('طباعة ملصقات الباركود'),
          centerTitle: true,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Row(
                children: [
                  // إعدادات
                  SizedBox(
                    width: 320,
                    child: _buildSettingsPanel(theme),
                  ),
                  const VerticalDivider(width: 1),
                  // قائمة المنتجات
                  Expanded(child: _buildProductList(theme)),
                ],
              ),
        bottomNavigationBar: _buildBottomBar(theme),
      ),
    );
  }

  Widget _buildSettingsPanel(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('إعدادات الملصق', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const Gap(12),

          TextField(
            controller: _companyCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم الشركة / المحل',
              prefixIcon: Icon(Icons.store),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const Gap(12),

          SwitchListTile(
            title: const Text('إظهار السعر'),
            value: _showPrice,
            onChanged: (v) => setState(() => _showPrice = v),
            contentPadding: EdgeInsets.zero,
          ),
          const Gap(8),

          Text('مقاس الملصق', style: theme.textTheme.labelLarge),
          const Gap(4),
          Wrap(
            spacing: 8,
            children: _presets.keys.map((preset) {
              return ChoiceChip(
                label: Text(preset),
                selected: !_customSize && _selectedPreset == preset,
                onSelected: (_) => setState(() {
                  _customSize = false;
                  _selectedPreset = preset;
                  _manualSize = true;
                }),
              );
            }).toList(),
          ),
          const Gap(4),
          ChoiceChip(
            label: const Text('مخصص'),
            selected: _customSize,
            onSelected: (_) => setState(() {
              _customSize = true;
              _manualSize = true;
            }),
          ),
          if (_customSize) ...[
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'عرض (mm)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: _customWidth.toString()),
                    onChanged: (v) {
                      setState(() {
                        _customWidth = double.tryParse(v) ?? 50;
                        _manualSize = true;
                      });
                    },
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'ارتفاع (mm)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: _customHeight.toString()),
                    onChanged: (v) {
                      setState(() {
                        _customHeight = double.tryParse(v) ?? 30;
                        _manualSize = true;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
          if (_detectedPrinter != null) ...[
            const Gap(4),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'البرينتر: $_detectedPrinter — $_detectedSizeText (تلقائي)',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const Gap(16),

          // معاينة
          Text('معاينة', style: theme.textTheme.labelLarge),
          const Gap(8),
          _buildPreview(theme),
        ],
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final barcodeValue = _selectedProducts.isNotEmpty
        ? (_barcodeCtrls[_selectedProducts.first.id]?.text ?? '')
        : '1234567890';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_companyCtrl.text.isNotEmpty)
            Text(
              _companyCtrl.text,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (_selectedProducts.isNotEmpty)
            Text(
              _selectedProducts.first.name,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              'اسم المنتج',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade400),
            ),
          if (_showPrice && _selectedProducts.isNotEmpty)
            Text(
              '${_selectedProducts.first.price.toStringAsFixed(2)} ج.م',
              style: const TextStyle(fontSize: 10, color: Colors.black),
            )
          else if (_showPrice)
            Text(
              '0.00 ج.م',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
          const Gap(4),
          if (barcodeValue.isNotEmpty)
            BarcodeWidget(
              barcode: Barcode.code128(),
              data: barcodeValue,
              width: 200,
              height: 50,
              drawText: true,
              style: const TextStyle(fontSize: 10),
            )
          else
            Container(
              width: 200,
              height: 50,
              color: Colors.grey.shade100,
              alignment: Alignment.center,
              child: Text('لا يوجد باركود', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
            ),
        ],
      ),
    );
  }

  Widget _buildProductList(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('المنتجات (${_selectedProducts.length}/${_products.length})',
                  style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: _selectAll,
                icon: const Icon(Icons.select_all, size: 18),
                label: const Text('تحديد الكل'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final p = _products[index];
              final isSelected = _selected[p.id] == true;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (v) => setState(() => _selected[p.id] = v ?? false),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('${p.price} ج.م',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      if (isSelected) ...[
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _barcodeCtrls[p.id],
                            decoration: const InputDecoration(
                              labelText: 'الباركود',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const Gap(8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('نسخ', style: TextStyle(fontSize: 10)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                                  onPressed: (_copies[p.id] ?? 1) > 1
                                      ? () => _setCopies(p.id, (_copies[p.id] ?? 1) - 1)
                                      : null,
                                ),
                                // حقل يسمح بكتابة العدد مباشرة (مثلاً 500) بدل الضغط المتكرر
                                SizedBox(
                                  width: 52,
                                  child: TextField(
                                    controller: _copyCtrls[p.id],
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding:
                                          EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                    ),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 12),
                                    onChanged: (v) =>
                                        _setCopies(p.id, int.tryParse(v) ?? 1),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 20),
                                  onPressed: () => _setCopies(p.id, (_copies[p.id] ?? 1) + 1),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildBottomBar(ThemeData theme) {
    final totalLabels = _selectedProducts.fold<int>(
      0,
      (sum, p) => sum + (_copies[p.id] ?? 1),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Text('إجمالي الملصقات: $totalLabels'),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _hasSelection ? _print : null,
            icon: const Icon(Icons.print),
            label: const Text('طباعة'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
