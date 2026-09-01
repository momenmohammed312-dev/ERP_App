import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/ui/supplier/add_supplier_transaction_dialog.dart';
import 'package:pos_offline_desktop/ui/supplier/edit_supplier_transaction_dialog.dart';
import 'package:pos_offline_desktop/ui/supplier/services/supplier_statement_generator.dart';

class SupplierStatementScreen extends ConsumerStatefulWidget {
  final Supplier supplier;
  const SupplierStatementScreen({super.key, required this.supplier});

  @override
  ConsumerState<SupplierStatementScreen> createState() => _SupplierStatementScreenState();
}

class _StatementRowData {
  final LedgerTransaction tx;
  final double balance;
  _StatementRowData({required this.tx, required this.balance});
}

class _SupplierStatementScreenState extends ConsumerState<SupplierStatementScreen> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  List<_StatementRowData> _rows = [];
  double _openingBalance = 0.0;
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isDetailed = true;

  double _totalPurchases = 0;
  double _totalPayments = 0;
  double _totalAdjustments = 0;
  double _totalReversals = 0;
  int _txCount = 0;

  String _filterType = 'all'; // all | purchase | payment | adjustment | reversal
  final TextEditingController _searchController = TextEditingController();
  final _nf = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _loadStatement();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    double purchases = 0, payments = 0, adjustments = 0, reversals = 0;
    for (final tx in txs) {
      final amount = tx.credit > 0 ? tx.credit : tx.debit;
      switch (tx.origin) {
        case 'purchase':
        case 'opening':
          purchases += amount;
          break;
        case 'payment':
          payments += amount;
          break;
        case 'adjustment':
          adjustments += (tx.credit - tx.debit);
          break;
        case 'reversal':
          reversals += amount;
          break;
        default:
          // fallback: credit = purchase-like, debit = payment-like
          if (tx.credit > 0) purchases += tx.credit;
          if (tx.debit > 0) payments += tx.debit;
      }
    }

    double running = prevBalance;
    final rows = <_StatementRowData>[];
    for (final tx in txs) {
      running += tx.credit - tx.debit;
      rows.add(_StatementRowData(tx: tx, balance: running));
    }

    setState(() {
      _rows = rows;
      _openingBalance = prevBalance;
      _totalPurchases = purchases;
      _totalPayments = payments;
      _totalAdjustments = adjustments;
      _totalReversals = reversals;
      _txCount = txs.length;
      _isLoading = false;
    });
  }

  List<_StatementRowData> get _filteredRows {
    final q = _searchController.text.trim().toLowerCase();
    return _rows.where((r) {
      final tx = r.tx;
      if (_filterType == 'purchase' && tx.origin != 'purchase' && tx.origin != 'opening') return false;
      if (_filterType == 'payment' && tx.origin != 'payment') return false;
      if (_filterType == 'adjustment' && tx.origin != 'adjustment') return false;
      if (_filterType == 'reversal' && tx.origin != 'reversal') return false;
      if (q.isNotEmpty) {
        final hay = '${tx.description} ${tx.receiptNumber ?? ''} ${tx.paymentMethod ?? ''}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final currentBalance = await db.ledgerDao.getRunningBalance('Supplier', widget.supplier.id, upToDate: _toDate);
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في تصدير PDF: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _addTransaction() {
    showDialog(
      context: context,
      builder: (ctx) => AddSupplierTransactionDialog(
        db: ref.read(appDatabaseProvider),
        supplier: widget.supplier,
        onSaved: _loadStatement,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final goldColor = const Color(0xFFC9A84C);

    final finalBalance = _rows.isEmpty ? _openingBalance : _rows.last.balance;

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
              Expanded(child: Text('كشف حساب مورد: ${widget.supplier.name}', style: const TextStyle(fontSize: 18))),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.add, color: Color(0xFFC9A84C)), onPressed: _addTransaction, tooltip: 'إضافة حركة'),
            IconButton(
              icon: _isExporting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf, color: Color(0xFFC9A84C)),
              onPressed: _isExporting ? null : _exportPdf,
              tooltip: 'تصدير PDF',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addTransaction,
          icon: const Icon(Icons.add),
          label: const Text('حركة جديدة'),
          backgroundColor: goldColor,
          foregroundColor: Colors.black,
        ),
        body: Column(
          children: [
            _buildSupplierInfo(cardBg, textColor, subTextColor, goldColor),
            _buildSummaryCards(cardBg, textColor),
            _buildDateFilter(cardBg, textColor, goldColor),
            _buildFilters(cardBg, textColor, goldColor),
            _buildStatementToggle(cardBg, textColor, goldColor),
            _buildOpeningBalance(cardBg, textColor, goldColor),
            _buildTableHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredRows.isEmpty
                      ? Center(child: Text('لا توجد معاملات في هذه الفترة', style: TextStyle(color: subTextColor)))
                      : ListView.builder(
                          itemCount: _filteredRows.length,
                          itemBuilder: (context, index) {
                            final row = _filteredRows[index];
                            return _SupplierStatementRow(
                              db: ref.read(appDatabaseProvider),
                              data: row,
                              textColor: textColor,
                              subTextColor: subTextColor,
                              isDark: isDark,
                              goldColor: goldColor,
                              onChanged: _loadStatement,
                            );
                          },
                        ),
            ),
            _buildFooter(finalBalance, textColor, goldColor, cardBg, isDark),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String label, double value, Color color, Color cardBg, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.7))),
          const Gap(4),
          Text('${_nf.format(value)} ج.م', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(Color cardBg, Color textColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(width: 150, child: _summaryCard('الرصيد الافتتاحي', _openingBalance, const Color(0xFFC9A84C), cardBg, textColor)),
          SizedBox(width: 150, child: _summaryCard('إجمالي المشتريات', _totalPurchases, Colors.redAccent, cardBg, textColor)),
          SizedBox(width: 150, child: _summaryCard('المدفوعات', _totalPayments, Colors.green, cardBg, textColor)),
          SizedBox(width: 150, child: _summaryCard('التسويات', _totalAdjustments, Colors.purple, cardBg, textColor)),
          SizedBox(width: 150, child: _summaryCard('المرتجعات', _totalReversals, Colors.orange, cardBg, textColor)),
          SizedBox(width: 150, child: _summaryCard('عدد الحركات', _txCount.toDouble(), Colors.blue, cardBg, textColor)),
        ],
      ),
    );
  }

  Widget _buildSupplierInfo(Color cardBg, Color textColor, Color subTextColor, Color goldColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: goldColor.withValues(alpha: 0.2))),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: goldColor.withValues(alpha: 0.15), child: Text(widget.supplier.name[0].toUpperCase(), style: TextStyle(color: goldColor, fontWeight: FontWeight.bold))),
          const Gap(12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.supplier.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
              if (widget.supplier.phone != null) Text(widget.supplier.phone!, style: TextStyle(fontSize: 12, color: subTextColor)),
              if (widget.supplier.address != null && widget.supplier.address!.isNotEmpty) Text(widget.supplier.address!, style: TextStyle(fontSize: 11, color: subTextColor)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('الرصيد الحالي', style: TextStyle(fontSize: 11, color: subTextColor)),
            Text('${_nf.format(_rows.isEmpty ? _openingBalance : _rows.last.balance)} ج.م',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: (_rows.isEmpty ? _openingBalance : _rows.last.balance) > 0 ? Colors.redAccent : Colors.green)),
          ]),
        ],
      ),
    );
  }

  Widget _buildDateFilter(Color cardBg, Color textColor, Color goldColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: goldColor.withValues(alpha: 0.15))),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.dark(primary: goldColor, surface: const Color(0xFF161B22))), child: child!),
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
            child: Row(children: [
              const Icon(Icons.date_range, color: Color(0xFFC9A84C), size: 20),
              const Gap(8),
              Text('من ${DateFormat('yyyy/MM/dd').format(_fromDate)} إلى ${DateFormat('yyyy/MM/dd').format(_toDate)}', style: TextStyle(color: textColor)),
              const Spacer(),
              Icon(Icons.edit_calendar, color: textColor.withValues(alpha: 0.4), size: 16),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(Color cardBg, Color textColor, Color goldColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: goldColor.withValues(alpha: 0.15))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'بحث برقم المرجع أو البيان', prefixIcon: Icon(Icons.search, size: 18), border: InputBorder.none, isDense: true),
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
          const Gap(8),
          DropdownButton<String>(
            value: _filterType,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('الكل')),
              DropdownMenuItem(value: 'purchase', child: Text('مشتريات')),
              DropdownMenuItem(value: 'payment', child: Text('مدفوعات')),
              DropdownMenuItem(value: 'adjustment', child: Text('تسويات')),
              DropdownMenuItem(value: 'reversal', child: Text('مرتجعات')),
            ],
            onChanged: (v) => setState(() => _filterType = v!),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementToggle(Color cardBg, Color textColor, Color goldColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: goldColor.withValues(alpha: 0.15))),
      child: Row(
        children: [
          Icon(Icons.receipt_long, color: goldColor, size: 18),
          const Gap(8),
          Text('نوع الكشف:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
          const Spacer(),
          ChoiceChip(label: const Text('مفصل'), selected: _isDetailed, onSelected: (v) => setState(() => _isDetailed = true), selectedColor: goldColor, labelStyle: TextStyle(color: _isDetailed ? Colors.black : textColor, fontWeight: FontWeight.bold, fontSize: 12), side: BorderSide(color: goldColor)),
          const Gap(6),
          ChoiceChip(label: const Text('مختصر'), selected: !_isDetailed, onSelected: (v) => setState(() => _isDetailed = false), selectedColor: goldColor, labelStyle: TextStyle(color: !_isDetailed ? Colors.black : textColor, fontWeight: FontWeight.bold, fontSize: 12), side: BorderSide(color: goldColor)),
        ],
      ),
    );
  }

  Widget _buildOpeningBalance(Color cardBg, Color textColor, Color goldColor) {
    final isOwed = _openingBalance > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: goldColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: goldColor.withValues(alpha: 0.2))),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: goldColor, size: 18),
          const Gap(8),
          Text('رصيد ما قبل الفترة:', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
          const Spacer(),
          Text('${_openingBalance.abs().toStringAsFixed(2)} ج.م', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isOwed ? Colors.redAccent : Colors.green)),
          const Gap(4),
          Text(isOwed ? '(علينا)' : '(لنا)', style: TextStyle(fontSize: 11, color: isOwed ? Colors.redAccent : Colors.green)),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(color: Color(0xFF1E1E2C), borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC9A84C), fontSize: 12))),
          Expanded(flex: 3, child: Text('البيان', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC9A84C), fontSize: 12))),
          Expanded(flex: 2, child: Text('مدين (-)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12))),
          Expanded(flex: 2, child: Text('دائن (+)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 12))),
          Expanded(flex: 2, child: Text('الرصيد', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC9A84C), fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildFooter(double finalBalance, Color textColor, Color goldColor, Color cardBg, bool isDark) {
    final isOwed = finalBalance > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)), border: Border.all(color: goldColor.withValues(alpha: 0.15)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05), blurRadius: 8, offset: const Offset(0, -2))]),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet, color: goldColor, size: 20),
          const Gap(8),
          Text('المستحق للمورد:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
          const Spacer(),
          Text('${finalBalance.abs().toStringAsFixed(2)} ج.م', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isOwed ? Colors.redAccent : Colors.green)),
          const Gap(4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: (isOwed ? Colors.redAccent : Colors.green).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
            child: Text(isOwed ? 'علينا' : 'لنا', style: TextStyle(fontSize: 10, color: isOwed ? Colors.redAccent : Colors.green, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _SupplierStatementRow extends StatefulWidget {
  final AppDatabase db;
  final _StatementRowData data;
  final Color textColor;
  final Color subTextColor;
  final bool isDark;
  final Color goldColor;
  final VoidCallback onChanged;

  const _SupplierStatementRow({
    required this.db,
    required this.data,
    required this.textColor,
    required this.subTextColor,
    required this.isDark,
    required this.goldColor,
    required this.onChanged,
  });

  @override
  State<_SupplierStatementRow> createState() => _SupplierStatementRowState();
}

class _SupplierStatementRowState extends State<_SupplierStatementRow> {
  bool _expanded = false;

  String _originLabel(String origin) {
    switch (origin) {
      case 'purchase':
        return 'مشتريات';
      case 'payment':
        return 'دفعة';
      case 'opening':
        return 'افتتاحي';
      case 'adjustment':
        return 'تسوية';
      case 'reversal':
        return 'مرتجع';
      case 'sale':
        return 'بيع (عمولة)';
      default:
        return origin;
    }
  }

  void _edit() {
    showDialog(
      context: context,
      builder: (ctx) => EditSupplierTransactionDialog(db: widget.db, transaction: widget.data.tx, onSaved: widget.onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.data.tx;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      color: widget.isDark ? const Color(0xFF161B22) : Colors.white,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(DateFormat('MM/dd HH:mm').format(tx.date), style: TextStyle(fontSize: 11, color: widget.subTextColor))),
                  Expanded(flex: 3, child: Text(tx.description, style: TextStyle(fontSize: 12, color: widget.textColor), overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 2, child: Text(tx.debit > 0 ? tx.debit.toStringAsFixed(2) : '-', style: TextStyle(color: Colors.green, fontWeight: tx.debit > 0 ? FontWeight.w600 : FontWeight.normal))),
                  Expanded(flex: 2, child: Text(tx.credit > 0 ? tx.credit.toStringAsFixed(2) : '-', style: TextStyle(color: Colors.redAccent, fontWeight: tx.credit > 0 ? FontWeight.w600 : FontWeight.normal))),
                  Expanded(flex: 2, child: Text(widget.data.balance.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.bold, color: widget.data.balance > 0 ? Colors.redAccent : (widget.data.balance < 0 ? Colors.green : widget.textColor)))),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: widget.subTextColor),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: widget.goldColor.withValues(alpha: 0.2)))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Gap(8),
                  _detailRow('النوع', _originLabel(tx.origin), Colors.purple),
                  if (tx.receiptNumber != null) _detailRow('المرجع', tx.receiptNumber!, Colors.grey),
                  _detailRow('طريقة الدفع', tx.paymentMethod ?? 'غير محدد', Colors.green),
                  _detailRow('المبلغ', '${(tx.credit > 0 ? tx.credit : tx.debit).toStringAsFixed(2)} ج.م', tx.credit > 0 ? Colors.redAccent : Colors.green),
                  const Gap(8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(onPressed: _edit, icon: const Icon(Icons.edit, size: 18), label: const Text('تعديل/حذف الحركة'), style: OutlinedButton.styleFrom(foregroundColor: Colors.blue)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: widget.subTextColor))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: color))),
        ],
      ),
    );
  }
}
