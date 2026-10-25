import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/madar_colors.dart';
import '../../core/utils/app_utils.dart';
import '../../ui/supplier/services/supplier_statement_generator.dart';

class SupplierReportScreen extends StatefulWidget {
  final AppDatabase database;

  const SupplierReportScreen({super.key, required this.database});

  @override
  State<SupplierReportScreen> createState() => _SupplierReportScreenState();
}

class _SupplierReportScreenState extends State<SupplierReportScreen> {
  List<Map<String, dynamic>> _supplierData = [];
  List<Map<String, dynamic>> _filteredSuppliers = [];
  bool _isLoading = true;
  String _selectedPeriod = 'all'; // 'all', 'today', 'week', 'month'
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSupplierData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSupplierData() async {
    setState(() => _isLoading = true);
    try {
      final suppliers = await widget.database.customSelect('''
        SELECT 
          s.id, s.name, s.phone,
          COALESCE(s.opening_balance, 0) as current_balance,
          COUNT(CASE WHEN p.is_deleted = 0 OR p.is_deleted IS NULL THEN p.id END) as invoice_count,
          COALESCE(SUM(CASE WHEN p.is_deleted = 0 OR p.is_deleted IS NULL THEN p.total_amount ELSE 0 END), 0) as total_purchases,
          COALESCE(SUM(CASE WHEN p.is_deleted = 0 OR p.is_deleted IS NULL THEN p.paid_amount ELSE 0 END), 0) as purchase_payments
        FROM suppliers s
        LEFT JOIN purchases p ON s.id = p.supplier_id
        GROUP BY s.id
        ORDER BY s.name
      ''').get();

      // Also get direct ledger payments (سداد دفعة للمورد)
      final ledgerPayments = await widget.database.customSelect('''
        SELECT ref_id, COALESCE(SUM(debit), 0) as direct_payments
        FROM ledger_transactions
        WHERE entity_type = 'Supplier' AND (debit > 0 OR origin = 'payment' OR origin = 'reversal')
        GROUP BY ref_id
      ''').get();

      final directPaymentMap = <String, double>{};
      for (final row in ledgerPayments) {
        final refId = row.data['ref_id']?.toString() ?? '';
        final amount = (row.data['direct_payments'] as num?)?.toDouble() ?? 0.0;
        directPaymentMap[refId] = amount;
      }

      final List<Map<String, dynamic>> result = [];
      for (final row in suppliers) {
        final data = row.data;
        final supplierId = data['id'].toString();
        final openingBalance = (data['current_balance'] as num?)?.toDouble() ?? 0.0;
        final totalPurchases = (data['total_purchases'] as num?)?.toDouble() ?? 0.0;
        final purchasePayments = (data['purchase_payments'] as num?)?.toDouble() ?? 0.0;
        final directPayments = directPaymentMap[supplierId] ?? 0.0;

        // Total payments = direct payments if recorded, else purchase payments
        final totalPayments = directPayments > 0 ? directPayments : purchasePayments;
        final outstanding = totalPurchases - totalPayments + openingBalance;

        result.add({
          'id': data['id'],
          'name': data['name'],
          'phone': data['phone'],
          'current_balance': openingBalance,
          'invoice_count': (data['invoice_count'] as num?)?.toInt() ?? 0,
          'total_purchases': totalPurchases,
          'total_payments': totalPayments,
          'outstanding': outstanding,
        });
      }

      setState(() {
        _supplierData = result;
        _isLoading = false;
      });
      _filterSuppliers();
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading supplier data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل بيانات الموردين: $e'),
            backgroundColor: MadarColors.error,
          ),
        );
      }
    }
  }

  void _filterSuppliers() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSuppliers = List.from(_supplierData);
      } else {
        _filteredSuppliers = _supplierData.where((s) {
          final name = (s['name']?.toString() ?? '').toLowerCase();
          final phone = (s['phone']?.toString() ?? '').toLowerCase();
          return name.contains(query) || phone.contains(query);
        }).toList();
      }
    });
  }

  double get _totalOutstanding =>
      _filteredSuppliers.fold(0.0, (sum, s) => sum + (s['outstanding'] as double));
  double get _totalPurchases =>
      _filteredSuppliers.fold(0.0, (sum, s) => sum + (s['total_purchases'] as double));
  double get _totalPayments =>
      _filteredSuppliers.fold(0.0, (sum, s) => sum + (s['total_payments'] as double));

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
          'المشتريات والتعاملات حسب المورد',
          style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadSupplierData,
            tooltip: 'تحديث البيانات',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: _exportAllSuppliersStatement,
            tooltip: 'كشف حساب كل الموردين PDF',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  // Controls card
                  _buildControlsCard(isDark),
                  const Gap(12),

                  // Summary Cards Strip
                  _buildKpiStrip(isDark),
                  const Gap(12),

                  // Suppliers List
                  Expanded(
                    child: _filteredSuppliers.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            itemCount: _filteredSuppliers.length,
                            itemBuilder: (context, index) {
                              final supplier = _filteredSuppliers[index];
                              return _buildSupplierItemCard(isDark, supplier);
                            },
                          ),
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
        border: Border.all(
          color: isDark ? MadarColors.border : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Search Input
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => _filterSuppliers(),
                    decoration: InputDecoration(
                      hintText: 'البحث عن مورد بالاسم أو الهاتف...',
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
                                _filterSuppliers();
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

              // Period Selector
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? MadarColors.bgSurface : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? MadarColors.border : Colors.grey.shade300,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedPeriod,
                    dropdownColor: isDark ? MadarColors.bgCard : Colors.white,
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('كل الفترات')),
                      DropdownMenuItem(value: 'today', child: Text('اليوم فقط')),
                      DropdownMenuItem(value: 'week', child: Text('هذا الأسبوع')),
                      DropdownMenuItem(value: 'month', child: Text('هذا الشهر')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedPeriod = value);
                        _loadSupplierData();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        final kpi1 = _KpiCard(
          title: 'إجمالي المديونية للموردين',
          value: _totalOutstanding,
          subtitle: 'مستحق السداد',
          color: MadarColors.error,
          icon: Icons.account_balance_wallet_rounded,
          isDark: isDark,
        );

        final kpi2 = _KpiCard(
          title: 'إجمالي المشتريات',
          value: _totalPurchases,
          subtitle: 'قيمة التوريدات',
          color: MadarColors.info,
          icon: Icons.shopping_cart_rounded,
          isDark: isDark,
        );

        final kpi3 = _KpiCard(
          title: 'إجمالي المدفوعات المسددة',
          value: _totalPayments,
          subtitle: 'سدادات ودفعات نقدية',
          color: MadarColors.success,
          icon: Icons.payments_rounded,
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

  Widget _buildSupplierItemCard(bool isDark, Map<String, dynamic> supplier) {
    final outstanding = (supplier['outstanding'] as num?)?.toDouble() ?? 0.0;
    final isDue = outstanding > 0.01;
    final isCredit = outstanding < -0.01;
    final badgeColor = isDue
        ? MadarColors.error
        : isCredit
            ? MadarColors.info
            : MadarColors.success;

    final badgeText = isDue
        ? 'مستحق له: ${outstanding.toStringAsFixed(2)} ج.م'
        : isCredit
            ? 'مدين لنا: ${(-outstanding).toStringAsFixed(2)} ج.م'
            : 'خالص الحساب';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? MadarColors.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? MadarColors.border : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        onTap: () => _viewSupplierTransactions(supplier),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: badgeColor.withValues(alpha: 0.12),
              child: Text(
                supplier['name']?.toString().isNotEmpty == true
                    ? supplier['name'].toString()[0]
                    : 'م',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: badgeColor,
                ),
              ),
            ),
            const Gap(12),

            // Name & Phone
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supplier['name']?.toString() ?? '',
                    style: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Gap(3),
                  Row(
                    children: [
                      Icon(
                        Icons.phone_rounded,
                        size: 13,
                        color: isDark ? MadarColors.textMuted : Colors.grey.shade600,
                      ),
                      const Gap(4),
                      Text(
                        supplier['phone']?.toString().isNotEmpty == true
                            ? supplier['phone'].toString()
                            : 'لا يوجد هاتف',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 12,
                          color: isDark ? MadarColors.textMuted : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Purchases count & Balance Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ),
            const Gap(10),

            // Action Button
            FilledButton.tonalIcon(
              onPressed: () => _viewSupplierTransactions(supplier),
              icon: const Icon(Icons.receipt_long_rounded, size: 16),
              label: const Text(
                'عرض المعاملات والسداد',
                style: TextStyle(fontFamily: 'NotoSansArabic', fontSize: 12),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.business_outlined,
            size: 56,
            color: Colors.grey,
          ),
          const Gap(12),
          Text(
            _searchController.text.isNotEmpty
                ? 'لا توجد نتائج مطابقة للبحث'
                : 'لا توجد بيانات موردين مسجلة',
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

  /// Show comprehensive transactions table: BOTH Purchases AND Payments!
  Future<void> _viewSupplierTransactions(Map<String, dynamic> supplier) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final supplierId = supplier['id'].toString();

      // 1. Fetch Purchases
      final purchasesRows = await widget.database.customSelect(
        '''
        SELECT 
          p.id,
          p.purchase_date as date,
          p.invoice_number,
          p.total_amount,
          p.paid_amount,
          p.payment_method,
          p.notes,
          'purchase' as item_type
        FROM purchases p
        WHERE p.supplier_id = ?
          AND (p.is_deleted = 0 OR p.is_deleted IS NULL)
        ORDER BY p.purchase_date DESC
        ''',
        variables: [drift.Variable.withString(supplierId)],
      ).get();

      // 2. Fetch Payments (سندات السداد من دفتر الأستاذ)
      final paymentsRows = await widget.database.customSelect(
        '''
        SELECT 
          id,
          date,
          COALESCE(receipt_number, description) as invoice_number,
          debit as total_amount,
          debit as paid_amount,
          payment_method,
          description as notes,
          'payment' as item_type
        FROM ledger_transactions
        WHERE entity_type = 'Supplier'
          AND ref_id = ?
          AND (debit > 0 OR origin = 'payment' OR origin = 'reversal')
        ORDER BY date DESC
        ''',
        variables: [drift.Variable.withString(supplierId)],
      ).get();

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      final List<Map<String, dynamic>> combined = [
        ...purchasesRows.map((r) => r.data),
        ...paymentsRows.map((r) => r.data),
      ];

      // Sort by date descending
      combined.sort((a, b) {
        final dateA = parseDate(a['date']);
        final dateB = parseDate(b['date']);
        return dateB.compareTo(dateA);
      });

      final isDark = Theme.of(context).brightness == Brightness.dark;

      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: isDark ? MadarColors.bgCard : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? MadarColors.border : Colors.grey.shade300),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? MadarColors.bgSurface : Colors.grey.shade100,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? MadarColors.border : Colors.grey.shade300,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: MadarColors.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.business_rounded, color: MadarColors.gold, size: 20),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Text(
                          'كشف فواتير وسدادات المورد: ${supplier['name']}',
                          style: const TextStyle(
                            fontFamily: 'NotoSansArabic',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Summary Row
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _summaryChip(
                        'إجمالي المشتريات',
                        '${(supplier['total_purchases'] as double).toStringAsFixed(2)} ج.م',
                        MadarColors.info,
                      ),
                      const Gap(8),
                      _summaryChip(
                        'إجمالي المدفوع والسداد',
                        '${(supplier['total_payments'] as double).toStringAsFixed(2)} ج.م',
                        MadarColors.success,
                      ),
                      const Gap(8),
                      _summaryChip(
                        'المستحق الحالي',
                        '${(supplier['outstanding'] as double).toStringAsFixed(2)} ج.م',
                        (supplier['outstanding'] as double) > 0.01
                            ? MadarColors.error
                            : MadarColors.success,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Transactions Table
                combined.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
                            Gap(12),
                            Text(
                              'لا توجد فواتير أو حركات سداد مسجلة لهذا المورد',
                              style: TextStyle(fontFamily: 'NotoSansArabic', color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: double.infinity,
                            child: DataTable(
                              columnSpacing: 14,
                              headingRowColor: WidgetStateProperty.all(
                                isDark
                                    ? MadarColors.bgSurface
                                    : Colors.grey.shade100,
                              ),
                              columns: const [
                                DataColumn(label: Text('التاريخ', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('البيان / الفاتورة', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('المبلغ', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('المدفوع', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('المتبقي', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('النوع', style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold))),
                              ],
                              rows: combined.map((p) {
                                final isPayment = p['item_type'] == 'payment';
                                final total = (p['total_amount'] as num?)?.toDouble() ?? 0.0;
                                final paid = (p['paid_amount'] as num?)?.toDouble() ?? 0.0;
                                final remaining = isPayment ? 0.0 : (total - paid);

                                DateTime? date;
                                try {
                                  date = parseDate(p['date']);
                                } catch (_) {}

                                final String label = isPayment
                                    ? (p['invoice_number']?.toString() ?? 'سداد دفعة للمورد')
                                    : 'فاتورة #${p['invoice_number'] ?? '-'}';

                                return DataRow(
                                  cells: [
                                    DataCell(Text(
                                      date != null ? DateFormat('yyyy/MM/dd').format(date) : '-',
                                      style: const TextStyle(fontFamily: 'NotoSansArabic', fontSize: 12),
                                    )),
                                    DataCell(Text(
                                      label,
                                      style: TextStyle(
                                        fontFamily: 'NotoSansArabic',
                                        fontSize: 12,
                                        fontWeight: isPayment ? FontWeight.bold : FontWeight.normal,
                                        color: isPayment ? MadarColors.success : null,
                                      ),
                                    )),
                                    DataCell(Text(
                                      '${total.toStringAsFixed(2)} ج.م',
                                      style: const TextStyle(fontFamily: 'NotoSansArabic', fontSize: 12),
                                    )),
                                    DataCell(Text(
                                      '${paid.toStringAsFixed(2)} ج.م',
                                      style: const TextStyle(
                                        fontFamily: 'NotoSansArabic',
                                        fontSize: 12,
                                        color: MadarColors.success,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )),
                                    DataCell(Text(
                                      '${remaining.toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                        fontFamily: 'NotoSansArabic',
                                        fontSize: 12,
                                        color: remaining > 0.01 ? MadarColors.error : MadarColors.success,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isPayment
                                              ? MadarColors.success.withValues(alpha: 0.15)
                                              : MadarColors.info.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isPayment ? 'سند سداد' : 'فاتورة شراء',
                                          style: TextStyle(
                                            fontFamily: 'NotoSansArabic',
                                            color: isPayment ? MadarColors.success : MadarColors.info,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل المعاملات: $e'),
          backgroundColor: MadarColors.error,
        ),
      );
    }
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(2),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAllSuppliersStatement() async {
    try {
      final now = DateTime.now();
      late final DateTime from;
      switch (_selectedPeriod) {
        case 'today':
          from = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          from = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          from = DateTime(now.year, now.month, 1);
          break;
        case 'all':
        default:
          from = DateTime(2020);
      }
      await SupplierStatementGenerator.generateAllSuppliersStatement(
        db: widget.database,
        fromDate: from,
        toDate: now,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تصدير الكشف: $e')),
        );
      }
    }
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final double value;
  final String subtitle;
  final Color color;
  final IconData icon;
  final bool isDark;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
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
                    '${value.toStringAsFixed(2)} ج.م',
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
