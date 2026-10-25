import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'customer_monthly_report_page.dart';

class CustomerReportTab extends StatefulWidget {
  final AppDatabase db;

  const CustomerReportTab({super.key, required this.db});

  @override
  State<CustomerReportTab> createState() => _CustomerReportTabState();
}

class _CustomerReportTabState extends State<CustomerReportTab> {
  List<CustomerWithBalance> _customers = [];
  List<CustomerWithBalance> _filteredCustomers = [];
  bool _isLoading = false;
  bool _showOnlyDues = false;
  DateTime _reportStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _reportEnd = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  final ExportService _exportService = ExportService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final customers = await widget.db.customerDao.getAllCustomers();

      // Fast single aggregate query instead of N queries
      final rows = await widget.db.customSelect(
        '''
        SELECT ref_id, COALESCE(SUM(debit - credit), 0) AS balance
        FROM ledger_transactions
        WHERE entity_type = 'Customer'
        GROUP BY ref_id
        ''',
      ).get();

      final Map<String, double> ledgerMap = {
        for (final r in rows) r.read<String>('ref_id'): r.read<double>('balance'),
      };

      final List<CustomerWithBalance> result = customers.map((c) {
        final totalBalance = c.openingBalance + (ledgerMap[c.id] ?? 0.0);
        return CustomerWithBalance(customer: c, balance: totalBalance);
      }).toList();

      setState(() {
        _customers = result;
        _isLoading = false;
      });
      _filterCustomers();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.error_loading_data_with_error(e)),
          ),
        );
      }
    }
  }

  void _filterCustomers() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredCustomers = _customers.where((item) {
        final name = item.customer.name.toLowerCase();
        final phone = (item.customer.phone ?? '').toLowerCase();
        final matchesSearch = query.isEmpty || name.contains(query) || phone.contains(query);
        final passesDues = !_showOnlyDues || item.balance > 0.01;
        return matchesSearch && passesDues;
      }).toList();
    });
  }

  Future<void> _showStatementDialog(Customer customer) async {
    DateTime start = DateTime.now().subtract(const Duration(days: 30));
    DateTime end = DateTime.now();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? MadarColors.bgCard : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? MadarColors.border : Colors.grey.shade300,
                ),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: MadarColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: MadarColors.gold, size: 20),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      'كشف حساب: ${customer.name}',
                      style: const TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'حدد الفترة الزمنية المطلوبة لإنشاء وطباعة كشف الحساب التفصيلي:',
                    style: TextStyle(fontFamily: 'NotoSansArabic', fontSize: 13),
                  ),
                  const Gap(14),
                  InkWell(
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: DateTimeRange(start: start, end: end),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          start = picked.start;
                          end = picked.end;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? MadarColors.bgSurface : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? MadarColors.border : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, size: 20, color: MadarColors.gold),
                          const Gap(10),
                          Expanded(
                            child: Text(
                              '${DateFormat('yyyy/MM/dd').format(start)}  إلى  ${DateFormat('yyyy/MM/dd').format(end)}',
                              style: const TextStyle(
                                fontFamily: 'NotoSansArabic',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'NotoSansArabic')),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _exportStatement(customer, start, end);
                  },
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('طباعة وتصدير الكشف', style: TextStyle(fontFamily: 'NotoSansArabic')),
                  style: FilledButton.styleFrom(
                    backgroundColor: MadarColors.gold,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportStatement(
    Customer customer,
    DateTime start,
    DateTime end,
  ) async {
    setState(() => _isLoading = true);
    try {
      final openingBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        customer.id,
        upToDate: start.subtract(const Duration(days: 1)),
      );

      final currentBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        customer.id,
        upToDate: end,
      );

      await _exportService.exportCustomerStatement(
        db: widget.db,
        customerId: customer.id,
        customerName: customer.name,
        fromDate: start,
        toDate: end,
        openingBalance: openingBalance,
        currentBalance: currentBalance,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalDue = _filteredCustomers.fold(
      0.0,
      (sum, item) => sum + (item.balance > 0.01 ? item.balance : 0),
    );
    final totalCredited = _filteredCustomers.fold(
      0.0,
      (sum, item) => sum + (item.balance < -0.01 ? -item.balance : 0),
    );
    final countDue = _filteredCustomers.where((c) => c.balance > 0.01).length;
    final countCredited = _filteredCustomers.where((c) => c.balance < -0.01).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'تقرير العملاء والذمم',
          style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Unified Controls Card
            _buildControlsCard(context, isDark),
            const Gap(12),

            // KPI Cards Strip
            _buildKpiStrip(context, isDark, totalDue, totalCredited, countDue, countCredited),
            const Gap(12),

            // Customer List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredCustomers.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          itemCount: _filteredCustomers.length,
                          itemBuilder: (context, index) {
                            final item = _filteredCustomers[index];
                            return _buildCustomerItemCard(context, isDark, item);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard(BuildContext context, bool isDark) {
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
                    onChanged: (val) => _filterCustomers(),
                    decoration: InputDecoration(
                      hintText: 'البحث عن عميل بالاسم أو رقم الهاتف...',
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
                                _filterCustomers();
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

              // Filter Chip: فقط المدينين
              FilterChip(
                selected: _showOnlyDues,
                label: const Text(
                  'فقط المدينين',
                  style: TextStyle(fontFamily: 'NotoSansArabic', fontSize: 12),
                ),
                avatar: Icon(
                  _showOnlyDues ? Icons.check_circle_rounded : Icons.filter_alt_outlined,
                  size: 16,
                  color: _showOnlyDues ? Colors.white : MadarColors.warning,
                ),
                selectedColor: MadarColors.warning,
                checkmarkColor: Colors.white,
                onSelected: (selected) {
                  setState(() => _showOnlyDues = selected);
                  _filterCustomers();
                },
              ),
            ],
          ),
          const Gap(10),
          Row(
            children: [
              // Date Range Button
              InkWell(
                onTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: DateTimeRange(
                      start: _reportStart,
                      end: _reportEnd,
                    ),
                  );
                  if (picked != null) {
                    setState(() {
                      _reportStart = picked.start;
                      _reportEnd = picked.end;
                    });
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? MadarColors.bgSurface : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? MadarColors.border : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.date_range_rounded, size: 16, color: MadarColors.gold),
                      const Gap(6),
                      Text(
                        'الفترة: ${DateFormat('yyyy/MM/dd').format(_reportStart)} - ${DateFormat('yyyy/MM/dd').format(_reportEnd)}',
                        style: const TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Gap(4),
                      const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const Spacer(),

              // Button: تقرير كامل مع الحركات
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => CustomerMonthlyReportPage(
                        db: widget.db,
                        start: _reportStart,
                        end: _reportEnd,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: const Text(
                  'تقرير كامل مع الحركات',
                  style: TextStyle(fontFamily: 'NotoSansArabic', fontSize: 13),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: MadarColors.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
    BuildContext context,
    bool isDark,
    double totalDue,
    double totalCredited,
    int countDue,
    int countCredited,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        final kpi1 = _KpiCard(
          title: 'مستحقات على العملاء (مدينين)',
          value: totalDue,
          subtitle: '$countDue عميل مطلوب منه سداد',
          color: MadarColors.error,
          icon: Icons.trending_up_rounded,
          isDark: isDark,
        );

        final kpi2 = _KpiCard(
          title: 'أرصدة لصالح العملاء (دائنين)',
          value: totalCredited,
          subtitle: '$countCredited عميل له رصيد متبقي',
          color: MadarColors.info,
          icon: Icons.account_balance_wallet_rounded,
          isDark: isDark,
        );

        final kpi3 = _KpiCard(
          title: 'إجمالي العملاء المسجلين',
          valueText: '${_customers.length}',
          subtitle: '${_filteredCustomers.length} عميل ظاهر بالبحث',
          color: MadarColors.gold,
          icon: Icons.people_alt_rounded,
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

  Widget _buildCustomerItemCard(BuildContext context, bool isDark, CustomerWithBalance item) {
    final balance = item.balance;
    final isDue = balance > 0.01;
    final isCredit = balance < -0.01;
    final isSettled = !isDue && !isCredit;

    final Color badgeColor = isDue
        ? MadarColors.error
        : isCredit
            ? MadarColors.info
            : MadarColors.success;

    final String badgeText = isDue
        ? 'مطلوب منه: ${balance.toStringAsFixed(2)} ج.م'
        : isCredit
            ? 'له رصيد: ${(-balance).toStringAsFixed(2)} ج.م'
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
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: badgeColor.withValues(alpha: 0.12),
            child: Text(
              item.customer.name.isNotEmpty ? item.customer.name[0] : 'ع',
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
                  item.customer.name,
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
                      item.customer.phone?.isNotEmpty == true
                          ? item.customer.phone!
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

          // Balance Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDue
                      ? Icons.arrow_outward_rounded
                      : isCredit
                          ? Icons.arrow_downward_rounded
                          : Icons.check_circle_outline_rounded,
                  size: 14,
                  color: badgeColor,
                ),
                const Gap(6),
                Text(
                  badgeText,
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
          const Gap(10),

          // Statement Action Button
          OutlinedButton.icon(
            onPressed: () => _showStatementDialog(item.customer),
            icon: const Icon(Icons.receipt_long_rounded, size: 16),
            label: const Text(
              'كشف حساب',
              style: TextStyle(fontFamily: 'NotoSansArabic', fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: BorderSide(color: isDark ? MadarColors.border : Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.people_outline_rounded,
            size: 56,
            color: Colors.grey,
          ),
          const Gap(12),
          Text(
            _searchController.text.isNotEmpty
                ? 'لا توجد نتائج مطابقة لبحثك'
                : 'لا توجد بيانات عملاء مسجلة',
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

class CustomerWithBalance {
  final Customer customer;
  final double balance;

  CustomerWithBalance({required this.customer, required this.balance});
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
