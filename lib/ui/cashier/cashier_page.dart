import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import 'package:pos_offline_desktop/ui/day/close_day_dialog.dart';
import '../../core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';

class CashierPage extends ConsumerStatefulWidget {
  const CashierPage({super.key});

  @override
  ConsumerState<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends ConsumerState<CashierPage> {
  CashSession? _currentSession;
  double _openingBalance = 0;
  double _totalIncome = 0;
  double _totalExpenses = 0.0;
  double _closingBalance = 0;
  List<LedgerTransaction> _transactions = [];
  bool _isDayOpen = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentDay();
  }

  Future<void> _loadCurrentDay() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(businessDateServiceProvider);
      final session = await service.getCurrentSession();
      
      if (session != null && session.status == 'open') {
        final today = DateTime.now();
        final db = ref.read(appDatabaseProvider);
        
        // Fetch all transactions for this session
        final allTransactions = await db.ledgerDao
            .getAllTransactionsByDateRange(session.openedAt, today);

        // Cash drawer figures come from the invoices/expenses tables
        // (mirrors the day-close settlement). The ledger double-books a
        // cash sale as sale-debit + payment-credit, which cancels to zero,
        // so it cannot be used for the drawer total.
        final invoices = await db.invoiceDao.getInvoicesByDateRange(
          session.openedAt,
          today,
        );
        double cashSales = 0.0;
        double creditCollections = 0.0;
        for (final invoice in invoices) {
          if (invoice.paymentMethod == 'cash') {
            cashSales += invoice.totalAmount;
          } else {
            creditCollections += invoice.paidAmount;
          }
        }
        final expenseItems = await db.expenseDao.getExpensesByDateRange(
          session.openedAt,
          today,
        );
        final totalExpenses = expenseItems.fold<double>(
          0.0,
          (sum, e) => sum + e.amount,
        );

        setState(() {
          _currentSession = session;
          _isDayOpen = true;
          _transactions = allTransactions;
          _openingBalance = session.openingBalance;

          _totalIncome = cashSales + creditCollections;
          _totalExpenses = totalExpenses;
          _closingBalance = _openingBalance + _totalIncome - _totalExpenses;
        });
      } else {
        setState(() {
          _currentSession = null;
          _isDayOpen = false;
          _transactions = [];
          _openingBalance = 0;
          _totalIncome = 0;
          _totalExpenses = 0;
          _closingBalance = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        final msg = e.toString().contains('no such table')
            ? 'خطأ في قاعدة البيانات: بعض الجداول مفقودة. يرجى إعادة تشغيل التطبيق.'
            : '${l10n.error_loading_data}: يرجى التأكد من فتح اليوم أولاً.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openNewDay() async {
    final l10n = AppLocalizations.of(context);
    final result = await _showOpeningBalanceDialog();
    if (!mounted || result == null) return;

    try {
      final service = ref.read(businessDateServiceProvider);
      final currentUser = ref.read(authProvider);
      await service.openSession(
        openedBy: currentUser?.fullName ?? 'Admin',
        openingBalance: result,
      );

      await _loadCurrentDay();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.day_opened_successfully)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.error_opening_day(e.toString()))),
        );
      }
    }
  }

  Future<void> _closeDay() async {
    if (_currentSession == null) return;

    // Vegetable flavor: day close goes through the full settlement dialog.
    if (AppFeatures.hasDaySettlement) {
      final closed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const CloseDayDialog(),
      );
      if (closed == true && mounted) {
        await _loadCurrentDay();
        if (!mounted) return;
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.day_closed_successfully)),
        );
      }
      return;
    }

    final result = await _showClosingBalanceDialog();
    if (result == null || !mounted) return;

    try {
      final service = ref.read(businessDateServiceProvider);
      await service.closeSession(
        sessionId: _currentSession!.id,
        actualCash: result['cash']!,
        notes: 'إغلاق يدوي من صفحة الكاشير',
      );

      await _loadCurrentDay();
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.day_closed_successfully)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.error_closing_day(e.toString()))),
        );
      }
    }
  }

  // ... (Dialog methods remain largely the same, but using the new state) ...
  Future<double?> _showOpeningBalanceDialog() async {
    final controller = TextEditingController();
    double? balance;
    final l10n = AppLocalizations.of(context);
    return showDialog<double>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.opening_balance_dialog_title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.opening_balance_prompt),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${l10n.opening_balance_label} (ج.م)',
                  border: const OutlineInputBorder(),
                  prefixText: 'ج.م ',
                ),
                onChanged: (value) => balance = double.tryParse(value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () {
                if (balance != null && balance! >= 0) {
                  Navigator.of(context).pop(balance);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.invalid_amount)));
                }
              },
              child: Text(l10n.open_new_day),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, double>?> _showClosingBalanceDialog() async {
    final cashController = TextEditingController();
    double? cashAmount;
    final l10n = AppLocalizations.of(context);
    return showDialog<Map<String, double>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.closing_day_dialog_title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${l10n.current_balance}: ${_closingBalance.toStringAsFixed(2)} ج.م'),
              const SizedBox(height: 16),
              TextField(
                controller: cashController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '${l10n.closing_cash_label} (ج.م)',
                  border: const OutlineInputBorder(),
                  prefixText: 'ج.م ',
                ),
                onChanged: (value) => cashAmount = double.tryParse(value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () {
                if (cashAmount != null && cashAmount! >= 0) {
                  Navigator.of(context).pop({'cash': cashAmount!});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.invalid_amount)));
                }
              },
              child: Text(l10n.close_day),
            ),
          ],
        );
      },
    );
  }

  void _showShiftReportDialog() {
    final TextEditingController actualCashController = TextEditingController();
    double actualCash = 0.0;
    double expectedCash = _closingBalance;
    double variance = 0.0;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('تقرير الوردية', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _reportRow('الرصيد الافتتاحي', _openingBalance),
                    _reportRow('إجمالي الإيرادات (كاش)', _totalIncome),
                    _reportRow('إجمالي المصروفات', _totalExpenses),
                    const Divider(),
                    _reportRow('الرصيد المتوقع', expectedCash, isBold: true),
                    const Gap(16),
                    TextField(
                      controller: actualCashController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الرصيد الفعلي (الموجود بالدرج)',
                        border: OutlineInputBorder(),
                        prefixText: 'ج.م ',
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          actualCash = double.tryParse(value) ?? 0.0;
                          variance = actualCash - expectedCash;
                        });
                      },
                    ),
                    const Gap(16),
                    _reportRow('العجز / الزيادة', variance, isBold: true, color: variance < 0 ? Colors.red : Colors.green),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
                ElevatedButton.icon(
                  onPressed: () async {
                    await PrinterService.printShiftReport(
                      date: DateTime.now(),
                      startTime: _currentSession?.openedAt ?? DateTime.now(),
                      endTime: DateTime.now(),
                      openingCash: _openingBalance,
                      totalRevenue: _totalIncome,
                      totalExpenses: _totalExpenses,
                      expectedCash: expectedCash,
                      actualCash: actualCash,
                      variance: variance,
                    );
                  },
                  icon: const Icon(Icons.print),
                  label: const Text('طباعة التقرير'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _reportRow(String label, double value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
          Text('${value.toStringAsFixed(2)} ج.م', style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 16, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: Text(l10n.cashier),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'تحديث',
                  onPressed: _loadCurrentDay,
                ),
                IconButton(
                  icon: const Icon(Icons.assignment_outlined),
                  tooltip: 'تقرير الوردية',
                  onPressed: _showShiftReportDialog,
                ),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Strip if embedded
                if (!canPop)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: MadarColors.gold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.point_of_sale_rounded,
                            size: 18,
                            color: MadarColors.gold,
                          ),
                        ),
                        const Gap(10),
                        Text(
                          l10n.cashier,
                          style: const TextStyle(
                            fontFamily: 'NotoSansArabic',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: 'تحديث البيانات',
                          onPressed: _loadCurrentDay,
                        ),
                        const Gap(6),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.assignment_outlined, size: 16),
                          label: const Text('تقرير الوردية'),
                          onPressed: _showShiftReportDialog,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Main Content
                if (!_isDayOpen)
                  Expanded(child: _buildClosedDayHero(context, l10n))
                else
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Gap(12),
                          // Open Status Banner
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withValues(alpha: 0.15),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF238636)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFF238636)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFF238636),
                                        ),
                                      ),
                                      const Gap(6),
                                      Text(
                                        l10n.day_is_open,
                                        style: const TextStyle(
                                          fontFamily: 'NotoSansArabic',
                                          color: Color(0xFF238636),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Gap(12),
                                if (_currentSession != null)
                                  Expanded(
                                    child: Text(
                                      '${l10n.opening_date}: ${DateFormat('yyyy/MM/dd HH:mm').format(_currentSession!.openedAt)} (${_currentSession!.openedBy})',
                                      style: TextStyle(
                                        fontFamily: 'NotoSansArabic',
                                        fontSize: 12.5,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                FilledButton.icon(
                                  onPressed: _closeDay,
                                  icon: const Icon(
                                    Icons.lock_clock_rounded,
                                    size: 16,
                                  ),
                                  label: Text(l10n.close_day),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFF85149),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Gap(16),

                          // Drawer Stats Row
                          Row(
                            children: [
                              _buildStatCard(
                                l10n.opening_balance_drawer,
                                _openingBalance,
                                const Color(0xFF388BFD),
                                Icons.account_balance_wallet_rounded,
                              ),
                              const Gap(12),
                              _buildStatCard(
                                l10n.total_revenue,
                                _totalIncome,
                                const Color(0xFF238636),
                                Icons.trending_up_rounded,
                              ),
                              const Gap(12),
                              _buildStatCard(
                                l10n.current_balance_drawer,
                                _closingBalance,
                                MadarColors.gold,
                                Icons.point_of_sale_rounded,
                              ),
                            ],
                          ),
                          const Gap(20),

                          // Recent Transactions
                          Row(
                            children: [
                              const Icon(
                                Icons.history_rounded,
                                size: 18,
                                color: MadarColors.gold,
                              ),
                              const Gap(8),
                              Text(
                                l10n.recent_transactions_cashier,
                                style: const TextStyle(
                                  fontFamily: 'NotoSansArabic',
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const Gap(12),

                          if (_transactions.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(32),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withValues(alpha: 0.12),
                                ),
                              ),
                              child: Text(
                                'لا توجد حركات نقدية مسجلة في هذه الوردية بعد',
                                style: TextStyle(
                                  fontFamily: 'NotoSansArabic',
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _transactions.length,
                              itemBuilder: (context, index) {
                                final t = _transactions[index];
                                final isIncome = t.debit > 0;
                                final color = isIncome
                                    ? const Color(0xFF238636)
                                    : const Color(0xFFF85149);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withValues(alpha: 0.12),
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 2,
                                    ),
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        isIncome
                                            ? Icons.arrow_downward_rounded
                                            : Icons.arrow_upward_rounded,
                                        color: color,
                                        size: 18,
                                      ),
                                    ),
                                    title: Text(
                                      t.description,
                                      style: const TextStyle(
                                        fontFamily: 'NotoSansArabic',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Text(
                                      DateFormat(
                                        'yyyy/MM/dd HH:mm',
                                      ).format(t.date),
                                      style: TextStyle(
                                        fontFamily: 'NotoSansArabic',
                                        fontSize: 11.5,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    trailing: Text(
                                      '${(t.debit - t.credit).abs().toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                        fontFamily: 'NotoSansArabic',
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          const Gap(24),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildClosedDayHero(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 540),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MadarColors.gold.withValues(alpha: 0.12),
                  border: Border.all(
                    color: MadarColors.gold.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  size: 38,
                  color: MadarColors.gold,
                ),
              ),
              const Gap(20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF85149).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFF85149).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFF85149),
                      ),
                    ),
                    const Gap(6),
                    Text(
                      l10n.day_is_closed,
                      style: const TextStyle(
                        fontFamily: 'NotoSansArabic',
                        color: Color(0xFFF85149),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(14),
              const Text(
                'الوردية واليومية مغلقة حالياً',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const Gap(8),
              Text(
                'لبدء تسجيل المبيعات والفواتير والتحصيلات لليوم، يرجى فتح يوم جديد وتسجيل رصيد العهدة النقدية الافتتاحية بالدرج.',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const Gap(24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openNewDay,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text(
                    l10n.open_new_day,
                    style: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF238636),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
              const Gap(16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        'يتم احتساب رصيد الدرج تلقائياً: (العهدة الافتتاحية + المقبوضات الكاش - المصروفات).',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 11.5,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
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
    );
  }

  Widget _buildStatCard(
    String title,
    double value,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: color, size: 15),
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Gap(10),
            Text(
              '${value.toStringAsFixed(2)} ج.م',
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
