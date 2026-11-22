import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../../../core/provider/smart_advisor_provider.dart';
import '../../../core/services/smart_analytics/predictive_stock_service.dart';
import '../../../core/services/smart_analytics/financial_anomaly_service.dart';
import '../../../core/services/smart_analytics/customer_retention_service.dart';
import '../../../core/services/smart_analytics/staff_discipline_service.dart';
import '../../../core/services/smart_analytics/supplier_payables_service.dart';
import '../../../core/services/smart_analytics/operations_audit_service.dart';
import '../../../core/theme/madar_colors.dart';

/// Dedicated comprehensive page for Smart Analytics, Predictive Stockout,
/// Financial Anomaly Detection, Customer Retention, Staff Discipline,
/// Supplier Payables, and Lingering Operations Audit.
/// Fully responsive across mobile, tablet, and desktop with official Madar Light & Dark mode tokens.
class SmartAnalyticsReportPage extends ConsumerStatefulWidget {
  const SmartAnalyticsReportPage({super.key});

  @override
  ConsumerState<SmartAnalyticsReportPage> createState() =>
      _SmartAnalyticsReportPageState();
}

class _SmartAnalyticsReportPageState
    extends ConsumerState<SmartAnalyticsReportPage> {
  bool _isLoading = true;
  String _executiveBrief = '';
  List<StockPredictionItem> _stockPredictions = [];
  List<FinancialAnomalyItem> _anomalies = [];
  List<CustomerRetentionItem> _churnCustomers = [];
  List<CustomerCreditStagnationItem> _creditStagnant = [];
  List<StaffDisciplineItem> _staffIssues = [];
  List<SupplierPayableItem> _supplierPayables = [];
  List<OperationsAuditItem> _operationsIssues = [];

  @override
  void initState() {
    super.initState();
    _loadAllInsights();
  }

  Future<void> _loadAllInsights() async {
    setState(() => _isLoading = true);
    try {
      final advisor = ref.read(smartAdvisorServiceProvider);

      final brief = await advisor.generateExecutiveBrief();
      final stock = await advisor.stockService.analyzeStockRunRate();
      final anomalies = await advisor.anomalyService.checkSessionAnomalies();
      final churn = await advisor.retentionService.analyzeCustomerCadences();
      final creditStagnant =
          await advisor.retentionService.analyzeCreditAccumulationWithoutPayment();
      final staff = await advisor.staffService.analyzeStaffDiscipline();
      final suppliers = await advisor.supplierService.analyzeOverduePayables();
      final ops = await advisor.operationsAuditService.checkUnclosedOperations();

      if (mounted) {
        setState(() {
          _executiveBrief = brief;
          _stockPredictions = stock;
          _anomalies = anomalies;
          _churnCustomers = churn;
          _creditStagnant = creditStagnant;
          _staffIssues = staff;
          _supplierPayables = suppliers;
          _operationsIssues = ops;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: context.bgCanvas,
      appBar: AppBar(
        backgroundColor: context.bgCard,
        elevation: 0,
        title: Text(
          'التحليل الذكي والمستشار الشامل',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: context.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث التحليل',
            onPressed: _loadAllInsights,
            icon: Icon(Icons.refresh, color: context.textPrimary),
          ),
          const Gap(8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 24 : 14,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Executive Briefing Card
                      _buildExecutiveBriefCard(context),
                      const Gap(20),

                      // 2. Predictive Stock Analysis Section
                      _buildStockSection(context),
                      const Gap(20),

                      // 3. Shift Security & Anomaly Section
                      _buildAnomalySection(context),
                      const Gap(20),

                      // 4. Staff Discipline & Attendance Section
                      _buildStaffSection(context),
                      const Gap(20),

                      // 5. Customer Credit Stagnation & Churn Section
                      _buildCustomerSection(context),
                      const Gap(20),

                      // 6. Supplier Overdue Payables Section
                      _buildSupplierSection(context),
                      const Gap(20),

                      // 7. Lingering Operations & Custody Audit Section
                      _buildOperationsSection(context),
                      const Gap(30),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildExecutiveBriefCard(BuildContext context) {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'المستشار التنفيذي',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isDark ? MadarColors.gold : MadarColors.lightPrimary)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'تحليل فوري',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? MadarColors.gold : MadarColors.lightPrimary,
                  ),
                ),
              ),
            ],
          ),
          const Gap(12),
          Text(
            _executiveBrief.isEmpty
                ? 'جاري إعداد التقرير والموجز التنفيذي...'
                : _executiveBrief,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockSection(BuildContext context) {
    final atRiskItems = _stockPredictions
        .where((s) => s.urgency != 'healthy')
        .toList();
    final isDark = context.isDarkMode;

    return _buildSectionContainer(
      context: context,
      title: 'استشراف المخزون والطلب (Predictive Stockout)',
      subtitle: 'حساب سرعة البيع اليومية وتقدير موعد نفاد البضائع بدقة',
      child: atRiskItems.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'حالة المخزون ممتازة. لا توجد أصناف معرضة للنفاد خلال الـ 7 أيام القادمة.',
                style: TextStyle(
                  color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: context.textPrimary,
                ),
                dataTextStyle: TextStyle(
                  fontSize: 13,
                  color: context.textSecondary,
                ),
                columns: const [
                  DataColumn(label: Text('الصنف')),
                  DataColumn(label: Text('الرصيد')),
                  DataColumn(label: Text('معدل البيع/يوم')),
                  DataColumn(label: Text('أيام النفاد')),
                  DataColumn(label: Text('الطلب المقترح')),
                  DataColumn(label: Text('الحالة')),
                ],
                rows: atRiskItems.take(15).map((item) {
                  final isCritical =
                      item.urgency == 'critical' || item.urgency == 'out_of_stock';
                  final badgeColor = isCritical
                      ? (isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F))
                      : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100));

                  return DataRow(
                    cells: [
                      DataCell(Text(
                        '${item.productName}${item.variantName != null ? " (${item.variantName})" : ""}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      )),
                      DataCell(Text('${item.currentStock}')),
                      DataCell(Text('${item.dailyVelocity}')),
                      DataCell(Text(
                        '${item.daysUntilStockout} يوم',
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                        ),
                      )),
                      DataCell(Text('${item.suggestedReorderQuantity} ق')),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.urgency == 'out_of_stock'
                              ? 'نافد'
                              : item.urgency == 'critical'
                                  ? 'حرج'
                                  : 'منخفض',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget _buildAnomalySection(BuildContext context) {
    final isDark = context.isDarkMode;

    return _buildSectionContainer(
      context: context,
      title: 'رادار الأمان المالي والورديات (Shift Anomaly Radar)',
      subtitle: 'رصد المرتجعات غير المعتادة وعمليات الإلغاء الشاذة للمحل',
      child: _anomalies.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'العمليات المالية منتظمة ولا توجد أي انحرافات أو مؤشرات شاذة في الوردية.',
                style: TextStyle(
                  color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            )
          : Column(
              children: _anomalies.map((a) {
                final isCritical = a.severity == 'critical';
                final accentColor = isCritical
                    ? (isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F))
                    : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100));

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: accentColor,
                              ),
                            ),
                            const Gap(4),
                            Text(
                              a.description,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildStaffSection(BuildContext context) {
    final isDark = context.isDarkMode;

    return _buildSectionContainer(
      context: context,
      title: 'انضباط الموظفين والحضور (Staff Discipline)',
      subtitle: 'كشف الغياب المتتالي والمتكرر بدون عذر، وتكرار التأخيرات المؤثرة',
      child: _staffIssues.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'سجل الحضور ممتاز. لا توجد غيابات متتالية أو تأخيرات غير مبررة خلال آخر أسبوعين.',
                style: TextStyle(
                  color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: context.textPrimary,
                ),
                dataTextStyle: TextStyle(
                  fontSize: 13,
                  color: context.textSecondary,
                ),
                columns: const [
                  DataColumn(label: Text('الموظف')),
                  DataColumn(label: Text('نوع المخالفة')),
                  DataColumn(label: Text('التكرار')),
                  DataColumn(label: Text('التفاصيل / التوصية')),
                  DataColumn(label: Text('الحالة')),
                ],
                rows: _staffIssues.map((s) {
                  final isCritical = s.severity == 'critical';
                  final badgeColor = isCritical
                      ? (isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F))
                      : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100));

                  final issueLabel = s.issueType == 'consecutive_absence'
                      ? 'غياب متتالي'
                      : s.issueType == 'frequent_absence'
                          ? 'تكرار غياب'
                          : 'تأخير متكرر';

                  return DataRow(
                    cells: [
                      DataCell(Text(
                        s.staffName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      )),
                      DataCell(Text(issueLabel)),
                      DataCell(Text(
                        s.issueType == 'frequent_tardiness'
                            ? '${s.count} مرات (${s.totalLateMinutes} د)'
                            : '${s.count} أيام',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      )),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          s.recommendation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      )),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isCritical ? 'حرج' : 'تنبيه',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget _buildCustomerSection(BuildContext context) {
    final isDark = context.isDarkMode;
    final allCustomerAlerts = [..._creditStagnant, ..._churnCustomers];

    return _buildSectionContainer(
      context: context,
      title: 'رادار العملاء والائتمان (Customer Credit & Retention)',
      subtitle: 'العملاء الساحبون بضاعة بدون سداد، والعملاء الذين كسروا إيقاع ترددهم',
      child: allCustomerAlerts.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'التحصيلات منتظمة ومعدلات شراء العملاء مستقرة تماماً.',
                style: TextStyle(
                  color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: context.textPrimary,
                ),
                dataTextStyle: TextStyle(
                  fontSize: 13,
                  color: context.textSecondary,
                ),
                columns: const [
                  DataColumn(label: Text('العميل')),
                  DataColumn(label: Text('المشكلة / الحالة')),
                  DataColumn(label: Text('فترة الانقطاع')),
                  DataColumn(label: Text('المديونية')),
                  DataColumn(label: Text('التوصية')),
                ],
                rows: [
                  ..._creditStagnant.map((c) {
                    final badgeColor = isDark
                        ? const Color(0xFFFF5252)
                        : const Color(0xFFD32F2F);
                    return DataRow(
                      cells: [
                        DataCell(Text(
                          c.customerName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        )),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'سحب بدون سداد (${c.purchasesWithoutPaymentCount} فواتير)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: badgeColor,
                            ),
                          ),
                        )),
                        DataCell(Text('${c.daysSinceLastPayment} يوم بدون دفعة')),
                        DataCell(Text(
                          '${c.currentDebt.toStringAsFixed(0)} ج',
                          style: TextStyle(
                            color: badgeColor,
                            fontWeight: FontWeight.bold,
                          ),
                        )),
                        DataCell(ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Text(
                            c.recommendation,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        )),
                      ],
                    );
                  }),
                  ..._churnCustomers.map((c) {
                    final debtColor = isDark
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFE65100);
                    return DataRow(
                      cells: [
                        DataCell(Text(
                          c.customerName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        )),
                        DataCell(Text('انقطاع عن الشراء')),
                        DataCell(Text('${c.daysSinceLastPurchase} يوم (معدله: ${c.averageCadenceDays} د)')),
                        DataCell(Text(
                          '${c.outstandingDebt.toStringAsFixed(0)} ج',
                          style: TextStyle(
                            color: c.outstandingDebt > 0 ? debtColor : null,
                            fontWeight: c.outstandingDebt > 0 ? FontWeight.bold : null,
                          ),
                        )),
                        DataCell(ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: Text(
                            c.suggestedAction,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        )),
                      ],
                    );
                  }),
                ],
              ),
            ),
    );
  }

  Widget _buildSupplierSection(BuildContext context) {
    final isDark = context.isDarkMode;

    return _buildSectionContainer(
      context: context,
      title: 'مستحقات الموردين المتأخرة (Supplier Payables)',
      subtitle: 'أرصدة الموردين المستحقة دون سداد منذ أكثر من 15 يوماً',
      child: _supplierPayables.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'حسابات الموردين منتظمة ولا توجد أي دفعات متأخرة أو حرجة.',
                style: TextStyle(
                  color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 24,
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: context.textPrimary,
                ),
                dataTextStyle: TextStyle(
                  fontSize: 13,
                  color: context.textSecondary,
                ),
                columns: const [
                  DataColumn(label: Text('المورد')),
                  DataColumn(label: Text('المستحق له')),
                  DataColumn(label: Text('أيام بدون سداد')),
                  DataColumn(label: Text('المشتريات بعد آخر دفعة')),
                  DataColumn(label: Text('التوصية')),
                  DataColumn(label: Text('الحالة')),
                ],
                rows: _supplierPayables.map((s) {
                  final isCritical = s.severity == 'critical';
                  final badgeColor = isCritical
                      ? (isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F))
                      : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100));

                  return DataRow(
                    cells: [
                      DataCell(Text(
                        s.supplierName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      )),
                      DataCell(Text(
                        '${s.outstandingBalance.toStringAsFixed(0)} ج',
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                        ),
                      )),
                      DataCell(Text('${s.daysSinceLastPayment} يوم')),
                      DataCell(Text('${s.unpaidsPurchasesCount} فواتير')),
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          s.recommendation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      )),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isCritical ? 'حرج' : 'تنبيه',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget _buildOperationsSection(BuildContext context) {
    final isDark = context.isDarkMode;

    return _buildSectionContainer(
      context: context,
      title: 'العمليات والعهد المفتوحة المعلقة (Operations & Custodies)',
      subtitle: 'العهد المالية المفتوحة، مراحل التصنيع الجارية، والورديات المنسية',
      child: _operationsIssues.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'كافة العهد المالية ومراحل التصنيع والورديات مغلقة ومسواة بانتظام.',
                style: TextStyle(
                  color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            )
          : Column(
              children: _operationsIssues.map((op) {
                final isCritical = op.severity == 'critical';
                final accentColor = isCritical
                    ? (isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F))
                    : (isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100));

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  op.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: accentColor,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  op.category == 'cash_session'
                                      ? '${op.ageInDaysOrHours} ساعة'
                                      : '${op.ageInDaysOrHours} أيام',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                            const Gap(4),
                            Text(
                              op.description,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: context.textSecondary,
                              ),
                            ),
                            const Gap(4),
                            Text(
                              op.actionRequired,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? MadarColors.gold
                                    : MadarColors.lightPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildSectionContainer({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
          const Gap(4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: context.textMuted,
            ),
          ),
          Divider(height: 24, color: context.borderColor),
          child,
        ],
      ),
    );
  }
}
