import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:drift/drift.dart' show Value;
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
  final _pageUrlCtrl = TextEditingController();
  final _customWidthCtrl = TextEditingController();
  final _customHeightCtrl = TextEditingController();
  bool _showPrice = true;
  bool _showQr = false;
  bool _loading = true;
  // أصناف المنتجات (ألوان/فئات) لطباعة ملصق لكل صنف بباركوده الخاص.
  final Map<int, List<ProductVariant>> _variantsByProduct = {};
  final Map<int, bool> _variantsLoading = {};
  final Set<int> _expanded = {};
  final Map<int, bool> _variantSelected = {};
  final Map<int, int> _variantCopies = {};
  final Map<int, TextEditingController> _variantCopyCtrls = {};
  final Map<int, TextEditingController> _variantBarcodeCtrls = {};
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
    '2.2×1.0in (56×25mm)': [55.88, 25.4],
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
    _customWidthCtrl.text = _customWidth.toString();
    _customHeightCtrl.text = _customHeight.toString();
    _init();
  }

  Future<void> _init() async {
    final company = await SettingsService.getBusinessName();
    _companyCtrl.text = company;
    final pageUrl = await SettingsService.getBusinessPageUrl();
    _pageUrlCtrl.text = pageUrl;
    // لو فيه لينك محفوظ — فعّل الـ QR افتراضيًا (المستخدم يقدر يطفيه).
    if (pageUrl.trim().isNotEmpty) _showQr = true;

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
      _syncCustomCtrls();
    });
  }

  /// مزامنة حقلي المخصص مع القيم الحالية (بعد قراءة تلقائية أو اختيار يدوي).
  void _syncCustomCtrls() {
    _customWidthCtrl.text = _customWidth.toString();
    _customHeightCtrl.text = _customHeight.toString();
  }

  /// يقبل أي رقم موجب (نقطة أو فاصلة) — ويرفض الصفر/السالب/الفارغ
  /// بإبقاء القيمة السابقة بدل الاستبدال الصامت برقم افتراضي.
  double? _parseCustomMm(String v) {
    final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0 || !parsed.isFinite) return null;
    return parsed;
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _pageUrlCtrl.dispose();
    _customWidthCtrl.dispose();
    _customHeightCtrl.dispose();
    for (final c in _barcodeCtrls.values) {
      c.dispose();
    }
    for (final c in _copyCtrls.values) {
      c.dispose();
    }
    for (final c in _variantBarcodeCtrls.values) {
      c.dispose();
    }
    for (final c in _variantCopyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Product> get _selectedProducts =>
      _products.where((p) => _selected[p.id] == true).toList();

  bool get _hasSelection =>
      _selected.values.any((v) => v) ||
      _variantSelected.values.any((v) => v);

  /// عدّاد نسخ مدمج (منتجات وأصناف) — نفس السلوك: كتابة مباشرة + حد أدنى 1.
  Widget _copiesStepper({
    required int value,
    required TextEditingController controller,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('نسخ', style: TextStyle(fontSize: 10)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: value > 1 ? () => onChanged(value - 1) : null,
            ),
            // حقل يسمح بكتابة العدد مباشرة (مثلاً 500) بدل الضغط المتكرر
            SizedBox(
              width: 52,
              child: TextField(
                controller: controller,
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
                onChanged: (v) => onChanged(int.tryParse(v) ?? 1),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }

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

  /// تحميل أصناف منتج عند فرد صفه (lazy — استعلام واحد لكل منتج يُفرد فقط).
  Future<void> _loadVariants(int productId) async {
    if (_variantsByProduct.containsKey(productId) ||
        _variantsLoading[productId] == true) {
      return;
    }
    setState(() => _variantsLoading[productId] = true);
    try {
      final variants = await widget.db.productVariantDao.getVariantsByProduct(
        productId,
      );
      // backfill: أي صنف قديم بلا باركود يتولد له ويتحفظ (نفس قاعدة الـ DAO).
      for (final v in variants) {
        if ((v.barcode?.trim() ?? '').isEmpty) {
          await widget.db.productVariantDao.updateVariant(
            v.copyWith(barcode: Value('${20000000 + v.id}')),
          );
        }
      }
      final fresh = await widget.db.productVariantDao.getVariantsByProduct(
        productId,
      );
      if (!mounted) return;
      setState(() {
        _variantsByProduct[productId] = fresh;
        for (final v in fresh) {
          _variantCopies.putIfAbsent(v.id, () => 1);
          _variantCopyCtrls.putIfAbsent(
            v.id,
            () => TextEditingController(text: '1'),
          );
          _variantBarcodeCtrls.putIfAbsent(
            v.id,
            () => TextEditingController(text: v.barcode?.trim() ?? ''),
          );
        }
        _variantsLoading[productId] = false;
      });
    } catch (_) {
      if (mounted) setState(() => _variantsLoading[productId] = false);
    }
  }

  void _toggleExpand(int productId) {
    setState(() {
      if (_expanded.contains(productId)) {
        _expanded.remove(productId);
      } else {
        _expanded.add(productId);
      }
    });
    if (_expanded.contains(productId)) _loadVariants(productId);
  }

  void _setVariantCopies(int variantId, int value) {
    final v = value < 1 ? 1 : value;
    setState(() {
      _variantCopies[variantId] = v;
      final ctrl = _variantCopyCtrls[variantId];
      if (ctrl != null && ctrl.text != '$v') {
        ctrl.text = '$v';
      }
    });
  }

  /// مهام الملصقات المحددة: منتجات (الأب) + أصناف (كل لون بباركوده).
  List<ProductLabelJob> _selectedJobs() {
    final jobs = <ProductLabelJob>[];
    final byId = {for (final p in _products) p.id: p};
    for (final p in _products) {
      if (_selected[p.id] == true) {
        jobs.add(
          ProductLabelJob(
            product: p,
            copies: _copies[p.id] ?? 1,
            barcode: _barcodeCtrls[p.id]?.text.trim() ?? '',
          ),
        );
      }
    }
    for (final variants in _variantsByProduct.values) {
      for (final v in variants) {
        if (_variantSelected[v.id] == true) {
          final parent = byId[v.productId];
          if (parent == null) continue;
          jobs.add(
            ProductLabelJob(
              product: parent,
              variant: v,
              copies: _variantCopies[v.id] ?? 1,
              barcode: _variantBarcodeCtrls[v.id]?.text.trim() ?? '',
            ),
          );
        }
      }
    }
    return jobs;
  }

  Future<void> _print() async {
    final jobs = _selectedJobs();
    if (jobs.isEmpty) return;

    // فحص تعارضات الباركود قبل الطباعة: لو الكود مستخدم بالفعل لمنتج/صنف آخر
    // نمنع طباعة كود خاطئ على الملصق (الكود مش هيتحفظ ولا هيتطبع).
    final conflictedProductIds = <int>{};
    final newProductBarcodes = <int, String>{};
    final conflictedVariantIds = <int>{};
    final newVariantBarcodes = <int, String>{};
    final conflictsText = StringBuffer();

    for (final job in jobs.where((j) => j.variant == null)) {
      final p = job.product;
      final inputBarcode = _barcodeCtrls[p.id]?.text.trim() ?? '';
      if (inputBarcode.isEmpty || inputBarcode == p.barcode?.trim()) continue;
      final existingP = await widget.db.productDao.getProductByBarcode(
        inputBarcode,
      );
      final existingV = await widget.db.productVariantDao.getVariantByBarcode(
        inputBarcode,
      );
      if ((existingP != null && existingP.id != p.id) || existingV != null) {
        conflictedProductIds.add(p.id);
        conflictsText.writeln('«${p.name}» → كود $inputBarcode');
      } else {
        newProductBarcodes[p.id] = inputBarcode;
      }
    }

    for (final job in jobs.where((j) => j.variant != null)) {
      final v = job.variant!;
      final inputBarcode = _variantBarcodeCtrls[v.id]?.text.trim() ?? '';
      if (inputBarcode.isEmpty || inputBarcode == v.barcode?.trim()) continue;
      final existingP = await widget.db.productDao.getProductByBarcode(
        inputBarcode,
      );
      final existingV = await widget.db.productVariantDao.getVariantByBarcode(
        inputBarcode,
      );
      if (existingP != null || (existingV != null && existingV.id != v.id)) {
        conflictedVariantIds.add(v.id);
        conflictsText.writeln('«${job.displayName}» → كود $inputBarcode');
      } else {
        newVariantBarcodes[v.id] = inputBarcode;
      }
    }

    if (!mounted) return;
    if (conflictedProductIds.isNotEmpty || conflictedVariantIds.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تعارض في الباركود'),
            content: Text(
              'الباركودات التالية مستخدمة بالفعل لمنتجات/أصناف أخرى ولن تُطبع على الملصقات:\n\n$conflictsText\nهل تريد الاستمرار؟',
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

    // الباركودات النهائية: المتعارض يُطبع بلا باركود (نفس سلوك المسار القديم).
    final finalJobs = <ProductLabelJob>[];
    for (final job in jobs) {
      if (job.variant == null) {
        finalJobs.add(
          ProductLabelJob(
            product: job.product,
            copies: job.copies,
            barcode: conflictedProductIds.contains(job.product.id)
                ? ''
                : (_barcodeCtrls[job.product.id]?.text.trim() ?? ''),
          ),
        );
      } else {
        finalJobs.add(
          ProductLabelJob(
            product: job.product,
            variant: job.variant,
            copies: job.copies,
            barcode: conflictedVariantIds.contains(job.variant!.id)
                ? ''
                : (_variantBarcodeCtrls[job.variant!.id]?.text.trim() ?? ''),
          ),
        );
      }
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
      for (final e in newProductBarcodes.entries) {
        await widget.db.productDao.updateProductBarcode(e.key, e.value);
      }
      for (final e in newVariantBarcodes.entries) {
        final v = await widget.db.productVariantDao.getVariantById(e.key);
        if (v != null) {
          await widget.db.productVariantDao.updateVariant(
            v.copyWith(barcode: Value(e.value)),
          );
        }
      }

      await LabelPrintService.printLabelJobs(
        jobs: finalJobs,
        companyName: _companyCtrl.text,
        showPrice: _showPrice,
        widthMm: _currentWidth,
        heightMm: _currentHeight,
        qrData: _showQr ? _pageUrlCtrl.text.trim() : null,
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
          SwitchListTile(
            title: const Text('QR بجانب الباركود (لينك الصفحة)'),
            value: _showQr,
            onChanged: (v) => setState(() => _showQr = v),
            contentPadding: EdgeInsets.zero,
          ),
          if (_showQr) ...[
            TextField(
              controller: _pageUrlCtrl,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'لينك الصفحة',
                hintText: 'https://facebook.com/...',
                prefixIcon: Icon(Icons.qr_code),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const Gap(8),
            if (_currentWidth < 50)
              Builder(
                builder: (context) {
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.orange.shade900.withValues(alpha: 0.5)
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? Colors.orange.shade700
                            : Colors.orange.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          size: 18,
                          color: isDark
                              ? Colors.orange.shade200
                              : Colors.orange.shade800,
                        ),
                        const Gap(6),
                        Expanded(
                          child: Text(
                            'المقاس ضيق على باركود + QR معًا — انصح بمقاس 50×30 أو أكبر، أو لينك أقصر.',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.orange.shade100
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
            else
              const Text(
                'نصيحة: كلما كان اللينك أقصر كان الـ QR أوضح وأسرع في المسح.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
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
              _syncCustomCtrls();
            }),
          ),
          if (_customSize) ...[
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customWidthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'عرض (mm)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) {
                      final parsed = _parseCustomMm(v);
                      if (parsed == null) return;
                      setState(() {
                        _customWidth = parsed;
                        _manualSize = true;
                      });
                    },
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: TextField(
                    controller: _customHeightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ارتفاع (mm)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) {
                      final parsed = _parseCustomMm(v);
                      if (parsed == null) return;
                      setState(() {
                        _customHeight = parsed;
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
    // المعاينة لأول مهمة محددة (منتج أو صنف) — بنفس الاسم والسعر والباركود
    // اللي هيتطبعوا فعليًا.
    final jobs = _selectedJobs();
    final previewJob = jobs.isEmpty ? null : jobs.first;
    final barcodeValue = previewJob?.barcode ?? '1234567890';

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
          if (previewJob != null)
            Text(
              previewJob.displayName,
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
          if (_showPrice && previewJob != null)
            Text(
              '${previewJob.price.toStringAsFixed(2)} ج.م',
              style: const TextStyle(fontSize: 10, color: Colors.black),
            )
          else if (_showPrice)
            Text(
              '0.00 ج.م',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
          const Gap(4),
          if (barcodeValue.isNotEmpty)
            if (_showQr && _pageUrlCtrl.text.trim().isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: barcodeValue,
                      width: 140,
                      height: 50,
                      drawText: true,
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                  const Gap(6),
                  BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: _pageUrlCtrl.text.trim(),
                    width: 64,
                    height: 64,
                    drawText: false,
                  ),
                ],
              )
            else
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
              Text('المنتجات (${_selectedProducts.length}/${_products.length})'
                  '${_variantSelected.values.any((v) => v) ? ' • ${_variantSelected.values.where((v) => v).length} صنف' : ''}',
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: isSelected,
                            onChanged: (v) => setState(() => _selected[p.id] = v ?? false),
                          ),
                          IconButton(
                            icon: Icon(
                              _expanded.contains(p.id)
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 20,
                            ),
                            tooltip: 'الأصناف (ألوان/فئات)',
                            onPressed: () => _toggleExpand(p.id),
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
                            _copiesStepper(
                              value: _copies[p.id] ?? 1,
                              controller: _copyCtrls[p.id]!,
                              onChanged: (v) => _setCopies(p.id, v),
                            ),
                          ],
                        ],
                      ),
                      if (_expanded.contains(p.id)) _buildVariantRows(p, theme),
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

  /// صفوف أصناف منتج (كل لون بباركوده ونسخه) — تُحمّل عند الفرد فقط.
  Widget _buildVariantRows(Product p, ThemeData theme) {
    if (_variantsLoading[p.id] == true) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final variants = _variantsByProduct[p.id] ?? [];
    if (variants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 48, vertical: 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            'لا توجد أصناف — يُطبع ملصق المنتج فقط.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 40),
      child: Column(
        children: [
          const Divider(height: 8),
          for (final v in variants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Checkbox(
                    value: _variantSelected[v.id] == true,
                    onChanged: (val) =>
                        setState(() => _variantSelected[v.id] = val ?? false),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          v.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'متاح: ${v.quantity} • ${(v.price ?? p.price).toStringAsFixed(2)} ج.م',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _variantBarcodeCtrls[v.id],
                      decoration: const InputDecoration(
                        labelText: 'باركود الصنف',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const Gap(6),
                  _copiesStepper(
                    value: _variantCopies[v.id] ?? 1,
                    controller: _variantCopyCtrls[v.id]!,
                    onChanged: (val) => _setVariantCopies(v.id, val),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    final totalLabels = _selectedJobs().fold<int>(
      0,
      (sum, j) => sum + j.copies,
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
