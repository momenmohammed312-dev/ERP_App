import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import '../../core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
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

        setState(() {
          _currentSession = session;
          _isDayOpen = true;
          _transactions = allTransactions;
          _openingBalance = session.openingBalance;

          // Calculate totals for CASH
          final cashTransactions = allTransactions.where(
            (t) => (t.paymentMethod == 'cash' || t.entityType == 'Cash') &&
                   t.origin != 'opening' && t.origin != 'closing',
          );

          _totalIncome = cashTransactions
              .where((t) => t.debit > 0)
              .fold(0.0, (sum, t) => sum + t.debit);

          _totalExpenses = cashTransactions
              .where((t) => t.credit > 0)
              .fold(0.0, (sum, t) => sum + t.credit);

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
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cashier),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadCurrentDay),
          IconButton(icon: const Icon(Icons.assignment), onPressed: _showShiftReportDialog),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _isDayOpen ? l10n.day_is_open : l10n.day_is_closed,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _isDayOpen ? Colors.green : Colors.red,
                                    ),
                              ),
                              if (_isDayOpen)
                                ElevatedButton(
                                  onPressed: _closeDay,
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                  child: Text(l10n.close_day),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_currentSession != null) ...[
                  const Gap(10),
                  Text('${l10n.opening_date}: ${DateFormat('yyyy/MM/dd HH:mm').format(_currentSession!.openedAt)}'),
                ],
                const Gap(16),
                if (_isDayOpen) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildStatCard(l10n.opening_balance_drawer, _openingBalance, Colors.blue),
                        const Gap(16),
                        _buildStatCard(l10n.total_revenue, _totalIncome, Colors.green),
                        const Gap(16),
                        _buildStatCard(l10n.current_balance_drawer, _closingBalance, Colors.orange),
                      ],
                    ),
                  ),
                  const Gap(16),
                ],
                if (!_isDayOpen)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _openNewDay,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: Text(l10n.open_new_day),
                      ),
                    ),
                  ),
                if (_transactions.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(l10n.recent_transactions_cashier, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _transactions.length,
                      itemBuilder: (context, index) {
                        final t = _transactions[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(t.debit > 0 ? Icons.arrow_downward : Icons.arrow_upward, color: t.debit > 0 ? Colors.green : Colors.red),
                            title: Text(t.description),
                            subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(t.date)),
                            trailing: Text('${(t.debit - t.credit).toStringAsFixed(2)} ج.م', style: TextStyle(fontWeight: FontWeight.bold, color: t.debit > 0 ? Colors.green : Colors.red)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildStatCard(String title, double value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontSize: 14)),
              const Gap(8),
              Text('${value.toStringAsFixed(2)} ج.م', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
