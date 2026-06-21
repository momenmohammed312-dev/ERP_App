import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/ui/supplier/services/supplier_statement_generator.dart';

class SupplierStatementScreen extends ConsumerStatefulWidget {
  final Supplier supplier;
  const SupplierStatementScreen({super.key, required this.supplier});

  @override
  ConsumerState<SupplierStatementScreen> createState() =>
      _SupplierStatementScreenState();
}

class _SupplierStatementScreenState
    extends ConsumerState<SupplierStatementScreen> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  List<LedgerTransaction> _transactions = [];
  double _openingBalance = 0.0;
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isDetailed = true;

  @override
  void initState() {
    super.initState();
    _loadStatement();
  }

  Future<void> _loadStatement() async {
    setState(() => _isLoading = true);
    final db = ref.read(appDatabaseProvider);

    final txs = await db.ledgerDao.getTransactionsByDateRange(
      'Supplier',
      widget.supplier.id,
      DateTime(_fromDate.year, _fromDate.month, _fromDate.day),
      DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59),
    );

    final prevBalance = await db.ledgerDao.getRunningBalance(
      'Supplier',
      widget.supplier.id,
      upToDate: _fromDate.subtract(const Duration(seconds: 1)),
    );

    setState(() {
      _transactions = txs;
      _openingBalance = prevBalance;
      _isLoading = false;
    });
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final currentBalance = await db.ledgerDao.getRunningBalance(
        'Supplier',
        widget.supplier.id,
        upToDate: _toDate,
      );

      if (_isDetailed) {
        await SupplierStatementGenerator.generateStatement(
          db: db,
          supplierId: widget.supplier.id,
          supplierName: widget.supplier.name,
          fromDate: _fromDate,
          toDate: _toDate,
          openingBalance: _openingBalance,
          currentBalance: currentBalance,
        );
      } else {
        await SupplierStatementGenerator.generateSummaryStatement(
          db: db,
          supplierId: widget.supplier.id,
          supplierName: widget.supplier.name,
          fromDate: _fromDate,
          toDate: _toDate,
          openingBalance: _openingBalance,
          currentBalance: currentBalance,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تصدير PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final goldColor = const Color(0xFFC9A84C);

    double runningBalance = _openingBalance;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          foregroundColor: textColor,
          elevation: 0,
          title: Row(
            children: [
              const Icon(Icons.business, color: Color(0xFFC9A84C)),
              const Gap(8),
              Expanded(
                child: Text(
                  'كشف حساب: ${widget.supplier.name}',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf, color: Color(0xFFC9A84C)),
              onPressed: _isExporting ? null : _exportPdf,
              tooltip: 'تصدير PDF',
            ),
          ],
        ),
        body: Column(
          children: [
            _buildSupplierInfo(cardBg, textColor, subTextColor, goldColor),
            _buildDateFilter(cardBg, textColor, goldColor),
            _buildStatementToggle(cardBg, textColor, goldColor),
            _buildOpeningBalance(cardBg, textColor, goldColor),
            _buildTableHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _transactions.isEmpty
                      ? Center(
                          child: Text(
                            'لا توجد معاملات في هذه الفترة',
                            style: TextStyle(color: subTextColor),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final tx = _transactions[index];
                            runningBalance += (tx.credit - tx.debit);
                            return _buildTransactionRow(
                              tx,
                              runningBalance,
                              textColor,
                              subTextColor,
                              isDark,
                            );
                          },
                        ),
            ),
            _buildFooter(
              runningBalance,
              textColor,
              goldColor,
              cardBg,
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierInfo(
    Color cardBg,
    Color textColor,
    Color subTextColor,
    Color goldColor,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: goldColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: goldColor.withValues(alpha: 0.15),
            child: Text(
              widget.supplier.name[0].toUpperCase(),
              style: TextStyle(color: goldColor, fontWeight: FontWeight.bold),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.supplier.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                if (widget.supplier.phone != null)
                  Text(
                    widget.supplier.phone!,
                    style: TextStyle(fontSize: 12, color: subTextColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilter(Color cardBg, Color textColor, Color goldColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: goldColor.withValues(alpha: 0.15)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: ColorScheme.dark(
                      primary: goldColor,
                      surface: const Color(0xFF161B22),
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              setState(() {
                _fromDate = picked.start;
                _toDate = picked.end;
              });
              _loadStatement();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.date_range, color: Color(0xFFC9A84C), size: 20),
                const Gap(8),
                Text(
                  'من ${DateFormat('yyyy/MM/dd').format(_fromDate)} إلى ${DateFormat('yyyy/MM/dd').format(_toDate)}',
                  style: TextStyle(color: textColor),
                ),
                const Spacer(),
                Icon(
                  Icons.edit_calendar,
                  color: textColor.withValues(alpha: 0.4),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatementToggle(Color cardBg, Color textColor, Color goldColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: goldColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long, color: goldColor, size: 18),
          const Gap(8),
          Text(
            'نوع الكشف:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const Spacer(),
          ChoiceChip(
            label: const Text('مفصل'),
            selected: _isDetailed,
            onSelected: (v) => setState(() => _isDetailed = true),
            selectedColor: goldColor,
            labelStyle: TextStyle(
              color: _isDetailed ? Colors.black : textColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            side: BorderSide(color: goldColor),
          ),
          const Gap(6),
          ChoiceChip(
            label: const Text('مختصر'),
            selected: !_isDetailed,
            onSelected: (v) => setState(() => _isDetailed = false),
            selectedColor: goldColor,
            labelStyle: TextStyle(
              color: !_isDetailed ? Colors.black : textColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            side: BorderSide(color: goldColor),
          ),
        ],
      ),
    );
  }

  Widget _buildOpeningBalance(Color cardBg, Color textColor, Color goldColor) {
    final isOwed = _openingBalance > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: goldColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: goldColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: goldColor, size: 18),
          const Gap(8),
          Text(
            'رصيد ما قبل الفترة:',
            style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
          ),
          const Spacer(),
          Text(
            '${_openingBalance.abs().toStringAsFixed(2)} ج.م',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isOwed ? Colors.redAccent : Colors.green,
            ),
          ),
          const Gap(4),
          Text(
            isOwed ? '(علينا)' : '(لنا)',
            style: TextStyle(
              fontSize: 11,
              color: isOwed ? Colors.redAccent : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'التاريخ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFFC9A84C),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'البيان',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFFC9A84C),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'دائن (+)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'مدين (-)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'الرصيد',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFFC9A84C),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(
    LedgerTransaction tx,
    double currentBalance,
    Color textColor,
    Color subTextColor,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF30363D).withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('MM/dd HH:mm').format(tx.date),
              style: TextStyle(fontSize: 11, color: subTextColor),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              tx.description,
              style: TextStyle(fontSize: 12, color: textColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              tx.credit > 0 ? tx.credit.toStringAsFixed(2) : '-',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight:
                    tx.credit > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              tx.debit > 0 ? tx.debit.toStringAsFixed(2) : '-',
              style: TextStyle(
                color: Colors.green,
                fontWeight:
                    tx.debit > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              currentBalance.toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: currentBalance > 0
                    ? Colors.redAccent
                    : (currentBalance < 0 ? Colors.green : textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    double finalBalance,
    Color textColor,
    Color goldColor,
    Color cardBg,
    bool isDark,
  ) {
    final isOwed = finalBalance > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border.all(color: goldColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet, color: goldColor, size: 20),
          const Gap(8),
          Text(
            'المستحق للمورد:',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const Spacer(),
          Text(
            '${finalBalance.abs().toStringAsFixed(2)} ج.م',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isOwed ? Colors.redAccent : Colors.green,
            ),
          ),
          const Gap(4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (isOwed ? Colors.redAccent : Colors.green)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isOwed ? 'علينا' : 'لنا',
              style: TextStyle(
                fontSize: 10,
                color: isOwed ? Colors.redAccent : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
