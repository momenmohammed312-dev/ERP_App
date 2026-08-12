import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/ui/customer/edit_payment_dialog.dart';
import 'package:pos_offline_desktop/ui/customer/services/enhanced_customer_statement_generator.dart';
import 'package:pos_offline_desktop/ui/invoice/edit_invoice_page.dart';
import 'package:pos_offline_desktop/ui/widgets/invoice_items_table.dart';

class CustomerStatementScreen extends ConsumerStatefulWidget {
  final Customer customer;
  const CustomerStatementScreen({super.key, required this.customer});

  @override
  ConsumerState<CustomerStatementScreen> createState() =>
      _CustomerStatementScreenState();
}

class _StatementRowData {
  final LedgerTransaction tx;
  final double balance;
  _StatementRowData({required this.tx, required this.balance});
}

class _CustomerStatementScreenState
    extends ConsumerState<CustomerStatementScreen> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  List<_StatementRowData> _rows = [];
  double _openingBalance = 0.0;
  bool _isLoading = true;
  bool _isExporting = false;
  bool _isDetailed = true;

  // Summary
  double _totalPurchases = 0;
  double _totalPayments = 0;
  double _totalReturns = 0;
  double _totalDiscount = 0;
  int _invoiceCount = 0;

  // Filters
  String _filterType = 'all'; // all | sale | payment | reversal
  final TextEditingController _searchController = TextEditingController();

  final _nf = NumberFormat('#,##0.00');
  static final _invReceipt = RegExp(r'^INV(\d+)$');

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

    final txs = await db.ledgerDao.getCustomerTransactionsByDateRange(
      widget.customer.id,
      DateTime(_fromDate.year, _fromDate.month, _fromDate.day),
      DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59),
    );

    final prevBalance = await db.ledgerDao.getRunningBalance(
      'Customer',
      widget.customer.id,
      upToDate: _fromDate.subtract(const Duration(seconds: 1)),
    );

    double purchases = 0;
    double payments = 0;
    double returns = 0;
    double discounts = 0;
    int invoices = 0;

    for (final tx in txs) {
      if (tx.origin == 'sale') {
        purchases += tx.debit;
        invoices++;
        if (tx.receiptNumber != null) {
          final m = _invReceipt.firstMatch(tx.receiptNumber!);
          if (m != null) {
            final id = int.tryParse(m.group(1) ?? '');
            if (id != null) {
              final items =
                  await db.invoiceDao.getItemsWithProductsByInvoice(id);
              for (final it in items) {
                discounts += it.$1.discount;
              }
            }
          }
        }
      } else if (tx.origin == 'payment') {
        payments += tx.credit;
      } else if (tx.origin == 'reversal') {
        returns += tx.credit;
      }
    }

    double running = prevBalance;
    final rows = <_StatementRowData>[];
    for (final tx in txs) {
      running += tx.debit - tx.credit;
      rows.add(_StatementRowData(tx: tx, balance: running));
    }

    setState(() {
      _rows = rows;
      _openingBalance = prevBalance;
      _totalPurchases = purchases;
      _totalPayments = payments;
      _totalReturns = returns;
      _totalDiscount = discounts;
      _invoiceCount = invoices;
      _isLoading = false;
    });
  }

  List<_StatementRowData> get _filteredRows {
    final q = _searchController.text.trim().toLowerCase();
    return _rows.where((r) {
      final tx = r.tx;
      if (_filterType == 'sale' && tx.origin != 'sale') return false;
      if (_filterType == 'payment' && tx.origin != 'payment') return false;
      if (_filterType == 'reversal' && tx.origin != 'reversal') return false;
      if (q.isNotEmpty) {
        final hay = '${tx.description} ${tx.receiptNumber ?? ''}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final currentBalance =
          await db.ledgerDao.getCustomerBalance(widget.customer.id);

      if (_isDetailed) {
        await EnhancedCustomerStatementGenerator.generateStatement(
          db: db,
          customerId: widget.customer.id,
          customerName: widget.customer.name,
          fromDate: _fromDate,
          toDate: _toDate,
          openingBalance: _openingBalance,
          currentBalance: currentBalance,
        );
      } else {
        await EnhancedCustomerStatementGenerator.generateSummaryStatement(
          db: db,
          customerId: widget.customer.id,
          customerName: widget.customer.name,
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

    final finalBalance = _rows.isEmpty
        ? _openingBalance
        : _rows.last.balance;

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
              const Icon(Icons.account_balance, color: Color(0xFFC9A84C)),
              const Gap(8),
              Expanded(
                child: Text(
                  'كشف حساب: ${widget.customer.name}',
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
            _buildCustomerInfo(cardBg, textColor, subTextColor, goldColor),
            _buildSummaryCards(cardBg, textColor, subTextColor, goldColor),
            _buildDateFilter(cardBg, textColor, goldColor),
            _buildFilters(cardBg, textColor, goldColor),
            _buildStatementToggle(cardBg, textColor, goldColor),
            _buildOpeningBalance(cardBg, textColor, goldColor),
            _buildTableHeader(textColor, goldColor),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredRows.isEmpty
                      ? Center(
                          child: Text(
                            'لا توجد معاملات في هذه الفترة',
                            style: TextStyle(color: subTextColor),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredRows.length,
                          itemBuilder: (context, index) {
                            final row = _filteredRows[index];
                            return _StatementRow(
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
            _buildFooter(
              finalBalance,
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

  Widget _summaryCard(
    String label,
    double value,
    Color color,
    Color cardBg,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.7)),
          ),
          const Gap(4),
          Text(
            '${_nf.format(value)} ج.م',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(
    Color cardBg,
    Color textColor,
    Color subTextColor,
    Color goldColor,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 150,
            child: _summaryCard('الرصيد الافتتاحي', _openingBalance,
                goldColor, cardBg, textColor),
          ),
          SizedBox(
            width: 150,
            child: _summaryCard('إجمالي المشتريات', _totalPurchases,
                Colors.redAccent, cardBg, textColor),
          ),
          SizedBox(
            width: 150,
            child: _summaryCard('المدفوعات', _totalPayments, Colors.green,
                cardBg, textColor),
          ),
          SizedBox(
            width: 150,
            child: _summaryCard('المرتجعات', _totalReturns, Colors.orange,
                cardBg, textColor),
          ),
          SizedBox(
            width: 150,
            child: _summaryCard(
                'الخصومات', _totalDiscount, Colors.purple, cardBg, textColor),
          ),
          SizedBox(
            width: 150,
            child: _summaryCard('عدد الفواتير', _invoiceCount.toDouble(),
                Colors.blue, cardBg, textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInfo(
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
              widget.customer.name[0].toUpperCase(),
              style: TextStyle(color: goldColor, fontWeight: FontWeight.bold),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.customer.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                if (widget.customer.phone != null)
                  Text(
                    widget.customer.phone!,
                    style: TextStyle(fontSize: 12, color: subTextColor),
                  ),
                if (widget.customer.address != null &&
                    widget.customer.address!.isNotEmpty)
                  Text(
                    widget.customer.address!,
                    style: TextStyle(fontSize: 11, color: subTextColor),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'الرصيد الحالي',
                style: TextStyle(fontSize: 11, color: subTextColor),
              ),
              Text(
                '${_nf.format(_rows.isEmpty ? _openingBalance : _rows.last.balance)} ج.م',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: (_rows.isEmpty ? _openingBalance : _rows.last.balance) > 0
                      ? Colors.redAccent
                      : Colors.green,
                ),
              ),
            ],
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

  Widget _buildFilters(Color cardBg, Color textColor, Color goldColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: goldColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'بحث برقم المرجع أو البيان',
                prefixIcon:
                    const Icon(Icons.search, size: 18),
                border: InputBorder.none,
                isDense: true,
              ),
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
          const Gap(8),
          DropdownButton<String>(
            value: _filterType,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('الكل')),
              DropdownMenuItem(value: 'sale', child: Text('فواتير')),
              DropdownMenuItem(value: 'payment', child: Text('مدفوعات')),
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
    final isDebt = _openingBalance > 0;
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
              color: isDebt ? Colors.redAccent : Colors.green,
            ),
          ),
          const Gap(4),
          Text(
            isDebt ? '(مدين)' : '(دائن)',
            style: TextStyle(
              fontSize: 11,
              color: isDebt ? Colors.redAccent : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(Color textColor, Color goldColor) {
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
              'المشتريات',
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
              'المدفوعات',
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

  Widget _buildFooter(
    double finalBalance,
    Color textColor,
    Color goldColor,
    Color cardBg,
    bool isDark,
  ) {
    final isDebt = finalBalance > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
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
            'الرصيد النهائي:',
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
              color: isDebt ? Colors.redAccent : Colors.green,
            ),
          ),
          const Gap(4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (isDebt ? Colors.redAccent : Colors.green)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isDebt ? 'مدين' : 'دائن',
              style: TextStyle(
                fontSize: 10,
                color: isDebt ? Colors.redAccent : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementRow extends StatefulWidget {
  final AppDatabase db;
  final _StatementRowData data;
  final Color textColor;
  final Color subTextColor;
  final bool isDark;
  final Color goldColor;
  final VoidCallback onChanged;

  const _StatementRow({
    required this.db,
    required this.data,
    required this.textColor,
    required this.subTextColor,
    required this.isDark,
    required this.goldColor,
    required this.onChanged,
  });

  @override
  State<_StatementRow> createState() => _StatementRowState();
}

class _StatementRowState extends State<_StatementRow> {
  bool _expanded = false;
  bool _isLoadingDetails = false;
  List<InvoiceItemDisplayModel> _items = [];
  List<SalesReturnItem> _returnItems = [];
  SalesReturn? _returnHeader;

  bool get _isSale => widget.data.tx.origin == 'sale';
  bool get _isPayment => widget.data.tx.origin == 'payment';
  bool get _isReturn => widget.data.tx.origin == 'reversal';

  int? get _invoiceId {
    final rn = widget.data.tx.receiptNumber;
    if (rn == null) return null;
    final m = RegExp(r'^INV(\d+)$').firstMatch(rn);
    return m != null ? int.tryParse(m.group(1) ?? '') : null;
  }

  int? get _returnId {
    final rn = widget.data.tx.receiptNumber;
    if (rn == null) return null;
    final m = RegExp(r'^RET(\d+)$').firstMatch(rn);
    return m != null ? int.tryParse(m.group(1) ?? '') : null;
  }

  Future<void> _loadDetails() async {
    if (_isLoadingDetails) return;
    setState(() => _isLoadingDetails = true);
    try {
      if (_isSale && _invoiceId != null) {
        final items = await widget.db.invoiceDao
            .getItemsWithProductsByInvoice(_invoiceId!);
        setState(() {
          _items = items.map((e) {
            final item = e.$1;
            final product = e.$2;
            return InvoiceItemDisplayModel(
              productName: product?.name ?? 'منتج ${item.productId}',
              quantity: item.quantity.toDouble(),
              unitPrice:
                  item.quantity > 0 ? item.price / item.quantity : item.price,
              total: item.price,
              unit: product?.unit,
            );
          }).toList();
        });
      } else if (_isReturn && _returnId != null) {
        final header =
            await widget.db.salesReturnsDao.getReturnById(_returnId!);
        final items =
            await widget.db.salesReturnsDao.getItemsForReturn(_returnId!);
        setState(() {
          _returnHeader = header;
          _returnItems = items;
        });
      }
    } catch (e) {
      debugPrint('Error loading row details: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) _loadDetails();
  }

  void _editInvoice() {
    if (_invoiceId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditInvoicePage(
          db: widget.db,
          invoiceId: _invoiceId!,
          onSaved: () {
            widget.onChanged();
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _editPayment() {
    showDialog(
      context: context,
      builder: (ctx) => EditPaymentDialog(
        db: widget.db,
        transaction: widget.data.tx,
        onSaved: widget.onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.data.tx;
    final amount = tx.debit > 0 ? tx.debit : tx.credit;
    final isDebitRow = tx.debit > 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      color: widget.isDark ? const Color(0xFF161B22) : Colors.white,
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      DateFormat('MM/dd HH:mm').format(tx.date),
                      style: TextStyle(fontSize: 11, color: widget.subTextColor),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      tx.description,
                      style: TextStyle(fontSize: 12, color: widget.textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      tx.debit > 0 ? tx.debit.toStringAsFixed(2) : '-',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: tx.debit > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      tx.credit > 0 ? tx.credit.toStringAsFixed(2) : '-',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: tx.credit > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      widget.data.balance.toStringAsFixed(2),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: widget.data.balance > 0
                            ? Colors.redAccent
                            : (widget.data.balance < 0
                                ? Colors.green
                                : widget.textColor),
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: widget.subTextColor,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: widget.goldColor.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: _buildExpandedContent(amount, isDebitRow),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(double amount, bool isDebitRow) {
    if (_isLoadingDetails) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final children = <Widget>[];

    if (_isSale) {
      children.add(
        _detailRow('نوع المعاملة', 'فاتورة بيع', Colors.redAccent),
      );
      if (_items.isEmpty) {
        children.add(const Text('لا توجد تفاصيل أصناف'));
      } else {
        children.add(InvoiceItemsTable(items: _items));
      }
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _editInvoice,
            icon: const Icon(Icons.edit_note, size: 18),
            label: const Text('تعديل الفاتورة'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue,
            ),
          ),
        ),
      );
    } else if (_isPayment) {
      children.add(_detailRow(
        'طريقة الدفع',
        _paymentMethodLabel(widget.data.tx.paymentMethod),
        Colors.green,
      ));
      children.add(_detailRow(
        'المبلغ',
        '${amount.toStringAsFixed(2)} ج.م',
        Colors.green,
      ));
      if (widget.data.tx.receiptNumber != null) {
        children
            .add(_detailRow('المرجع', widget.data.tx.receiptNumber!, Colors.grey));
      }
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _editPayment,
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('تعديل الدفعة'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.blue),
          ),
        ),
      );
    } else if (_isReturn) {
      children.add(_detailRow('نوع المعاملة', 'مرتجع', Colors.orange));
      if (_returnHeader != null) {
        children.add(_detailRow(
          'رقم المرتجع',
          _returnHeader!.returnNumber,
          Colors.orange,
        ));
        children.add(_detailRow(
          'السبب',
          _returnHeader!.returnReason,
          Colors.orange,
        ));
      }
      if (_returnItems.isEmpty) {
        children.add(const Text('لا توجد تفاصيل أصناف مرتجعة'));
      } else {
        children.add(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('الصنف')),
                DataColumn(label: Text('الكمية')),
                DataColumn(label: Text('سعر الوحدة')),
                DataColumn(label: Text('الإجمالي')),
              ],
              rows: _returnItems
                  .map(
                    (it) => DataRow(
                      cells: [
                        DataCell(Text(it.productName)),
                        DataCell(Text('${it.quantity}')),
                        DataCell(Text(it.unitPrice.toStringAsFixed(2))),
                        DataCell(Text(it.totalPrice.toStringAsFixed(2))),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _detailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: widget.subTextColor),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  String _paymentMethodLabel(String? method) {
    switch (method) {
      case 'cash':
        return 'نقدي';
      case 'credit':
        return 'آجل';
      case 'visa':
      case 'card':
        return 'بطاقة';
      case 'bank':
        return 'بنك';
      case 'instapay':
        return 'انستاباي';
      case 'wallet':
        return 'محفظة';
      default:
        return method ?? 'غير محدد';
    }
  }
}
