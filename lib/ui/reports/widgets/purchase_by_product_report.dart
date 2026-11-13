import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'dart:convert';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';

class PurchaseByProductReport extends ConsumerStatefulWidget {
  const PurchaseByProductReport({super.key});

  @override
  ConsumerState<PurchaseByProductReport> createState() =>
      _PurchaseByProductReportState();
}

class _PurchaseByProductReportState
    extends ConsumerState<PurchaseByProductReport> {
  bool _isLoading = false;
  DateTimeRange? _selectedDateRange;
  List<Map<String, dynamic>> _productData = [];
  List<Map<String, dynamic>> _filteredProductData = [];
  double _totalQuantity = 0.0;
  double _totalAmount = 0.0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedDateRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    );
    _loadReportData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReportData() async {
    if (_selectedDateRange == null) return;

    setState(() => _isLoading = true);

    try {
      final db = ref.read(appDatabaseProvider);
      final start = _selectedDateRange!.start;
      final end = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
        23,
        59,
        59,
      );

      final query = '''
        SELECT 
          p.id as product_id,
          p.name as product_name,
          p.barcode as product_barcode,
          p.unit as product_unit,
          COALESCE(SUM(pi.quantity), 0) as total_quantity,
          COALESCE(SUM(pi.total_price), 0) as total_amount,
          COUNT(pi.id) as purchase_count
        FROM products p
        LEFT JOIN purchase_items pi ON p.id = CAST(pi.product_id AS INTEGER)
        WHERE p.status = 'Active'
          AND pi.created_at >= ? AND pi.created_at <= ?
        GROUP BY p.id, p.name, p.barcode, p.unit
        HAVING COALESCE(SUM(pi.quantity), 0) > 0
        ORDER BY total_quantity DESC
      ''';

      final results = await db.customSelect(
        query,
        variables: [
          drift.Variable.withDateTime(start),
          drift.Variable.withDateTime(end),
        ],
      ).get();

      double totalQty = 0.0;
      double totalAmt = 0.0;
      final List<Map<String, dynamic>> data = [];

      for (final row in results) {
        final d = row.data;
        final qty = (d['total_quantity'] as num?)?.toDouble() ?? 0.0;
        final amt = (d['total_amount'] as num?)?.toDouble() ?? 0.0;
        final count = (d['purchase_count'] as num?)?.toInt() ?? 0;
        final avgPrice = qty > 0 ? amt / qty : 0.0;

        totalQty += qty;
        totalAmt += amt;

        data.add({
          'product_id': d['product_id'],
          'product_name': d['product_name']?.toString() ?? '',
          'product_barcode': d['product_barcode']?.toString() ?? '',
          'product_unit': d['product_unit']?.toString() ?? 'قطعة',
          'total_quantity': qty,
          'total_amount': amt,
          'avg_unit_price': avgPrice,
          'purchase_count': count,
        });
      }

      setState(() {
        _productData = data;
        _totalQuantity = totalQty;
        _totalAmount = totalAmt;
        _isLoading = false;
      });
      _filterData();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل التقرير: $e'),
            backgroundColor: MadarColors.error,
          ),
        );
      }
    }
  }

  void _filterData() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredProductData = List.from(_productData);
      } else {
        _filteredProductData = _productData.where((item) {
          final name = (item['product_name'] ?? '').toLowerCase();
          final barcode = (item['product_barcode'] ?? '').toLowerCase();
          return name.contains(query) || barcode.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() => _selectedDateRange = picked);
      _loadReportData();
    }
  }

  Future<void> _exportToCSV() async {
    try {
      final csvData = <String>[];
      csvData.add('المنتج,الوحدة,إجمالي الكمية,إجمالي القيمة,متوسط السعر,عدد المرات');

      for (final item in _filteredProductData) {
        csvData.add(
          '${item['product_name']},${item['product_unit']},${item['total_quantity']},${item['total_amount']},${(item['avg_unit_price'] as double).toStringAsFixed(2)},${item['purchase_count']}',
        );
      }

      final csvString = csvData.join('\n');
      final _ = utf8.encode(csvString);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصدير التقرير بنجاح'),
            backgroundColor: MadarColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e'), backgroundColor: MadarColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'تقرير المشتريات حسب المنتج',
          style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Controls
            _buildControlsCard(isDark),
            const Gap(12),

            // KPI Summary Strip
            _buildKpiStrip(isDark),
            const Gap(12),

            // Data List / Table
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredProductData.isEmpty
                      ? _buildEmptyState()
                      : _buildTable(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? MadarColors.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? MadarColors.border : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Search Box
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => _filterData(),
                decoration: InputDecoration(
                  hintText: 'البحث باسم المنتج أو الباركود...',
                  hintStyle: const TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20, color: MadarColors.gold),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _filterData();
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  filled: true,
                  fillColor: isDark ? MadarColors.bgSurface : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const Gap(10),

          // Date Range Button
          InkWell(
            onTap: _selectDateRange,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? MadarColors.bgSurface : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? MadarColors.border : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, size: 18, color: MadarColors.gold),
                  const Gap(8),
                  Text(
                    _selectedDateRange != null
                        ? '${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('yyyy/MM/dd').format(_selectedDateRange!.end)}'
                        : 'تحديد الفترة',
                    style: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(4),
                  const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                ],
              ),
            ),
          ),
          const Gap(10),

          // Export Button
          FilledButton.tonalIcon(
            onPressed: _exportToCSV,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('تصدير CSV', style: TextStyle(fontFamily: 'NotoSansArabic', fontSize: 13)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(bool isDark) {
    final avgPrice = _totalQuantity > 0 ? _totalAmount / _totalQuantity : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        final kpi1 = _KpiCard(
          title: 'إجمالي الكميات المستلمة',
          valueText: '${_totalQuantity.toStringAsFixed(1)} وحدة',
          subtitle: '${_productData.length} صنف مختلف',
          color: MadarColors.info,
          icon: Icons.inventory_2_rounded,
          isDark: isDark,
        );

        final kpi2 = _KpiCard(
          title: 'إجمالي تكلفة المشتريات',
          value: _totalAmount,
          subtitle: 'قيمة فواتير التوريد',
          color: MadarColors.gold,
          icon: Icons.payments_rounded,
          isDark: isDark,
        );

        final kpi3 = _KpiCard(
          title: 'متوسط سعر الوحدة العام',
          value: avgPrice,
          subtitle: 'معدل التكلفة لكل صنف',
          color: MadarColors.success,
          icon: Icons.analytics_outlined,
          isDark: isDark,
        );

        if (isNarrow) {
          return Column(
            children: [
              kpi1,
              const Gap(8),
              Row(
                children: [
                  Expanded(child: kpi2),
                  const Gap(8),
                  Expanded(child: kpi3),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: kpi1),
            const Gap(10),
            Expanded(child: kpi2),
            const Gap(10),
            Expanded(child: kpi3),
          ],
        );
      },
    );
  }

  Widget _buildTable(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? MadarColors.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? MadarColors.border : Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            child: DataTable(
              columnSpacing: 16,
              headingRowColor: WidgetStateProperty.all(
                isDark ? MadarColors.bgSurface : Colors.grey.shade100,
              ),
              columns: const [
                DataColumn(label: Text('اسم الصنف / المنتج', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                DataColumn(label: Text('الوحدة', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                DataColumn(label: Text('إجمالي الكمية', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                DataColumn(label: Text('متوسط السعر', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                DataColumn(label: Text('إجمالي القيمة', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                DataColumn(label: Text('عدد التوريدات', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
              ],
              rows: _filteredProductData.map((item) {
                return DataRow(
                  cells: [
                    DataCell(Text(
                      item['product_name'] ?? '',
                      style: const TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold),
                    )),
                    DataCell(Text(
                      item['product_unit'] ?? '',
                      style: const TextStyle(fontFamily: 'NotoSansArabic'),
                    )),
                    DataCell(Text(
                      (item['total_quantity'] as double).toStringAsFixed(2),
                      style: const TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold),
                    )),
                    DataCell(Text(
                      '${(item['avg_unit_price'] as double).toStringAsFixed(2)} ج.م',
                      style: const TextStyle(fontFamily: 'NotoSansArabic'),
                    )),
                    DataCell(Text(
                      '${(item['total_amount'] as double).toStringAsFixed(2)} ج.م',
                      style: const TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontWeight: FontWeight.bold,
                        color: MadarColors.gold,
                      ),
                    )),
                    DataCell(Text(
                      '${item['purchase_count']}',
                      style: const TextStyle(fontFamily: 'NotoSansArabic'),
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey),
          const Gap(12),
          Text(
            _searchController.text.isNotEmpty
                ? 'لا توجد منتجات مطابقة للبحث'
                : 'لا توجد حركات مشتريات مسجلة في هذه الفترة',
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final double? value;
  final String? valueText;
  final String subtitle;
  final Color color;
  final IconData icon;
  final bool isDark;

  const _KpiCard({
    required this.title,
    this.value,
    this.valueText,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final display = valueText ?? '${value?.toStringAsFixed(2) ?? '0.00'} ج.م';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? MadarColors.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? MadarColors.border : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 11,
                    color: isDark ? MadarColors.textSecondary : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    display,
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 10,
                    color: isDark ? MadarColors.textMuted : Colors.grey.shade500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
