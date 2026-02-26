import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/dao/enhanced_purchase_dao.dart';
import '../../../../core/provider/app_database_provider.dart';
import '../../../../core/database/app_database.dart';
import '../../widgets/invoice_items_table.dart';

class PurchaseReportsScreen extends ConsumerStatefulWidget {
  const PurchaseReportsScreen({super.key});

  @override
  ConsumerState<PurchaseReportsScreen> createState() =>
      _PurchaseReportsScreenState();
}

class _PurchaseReportsScreenState extends ConsumerState<PurchaseReportsScreen> {
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  bool _isLoading = true;
  List<EnhancedPurchase> _purchases = [];
  late final EnhancedPurchaseDao _purchaseDao;

  @override
  void initState() {
    super.initState();
    _purchaseDao = EnhancedPurchaseDao(ref.read(appDatabaseProvider));
    _loadPurchases();
  }

  Future<void> _loadPurchases() async {
    setState(() => _isLoading = true);
    try {
      final purchases = await _purchaseDao.getPurchasesByDateRange(
        _selectedDateRange.start,
        _selectedDateRange.end,
      );
      setState(() {
        _purchases = purchases;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading purchases: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        title: const Text('تقارير المشتريات التفصيلية'),
        backgroundColor: const Color(0xFF2D2D3D),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: _selectedDateRange,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) {
                setState(() => _selectedDateRange = picked);
                _loadPurchases();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPurchases,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.purple),
                  )
                : _purchases.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد مشتريات في هذه الفترة',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _purchases.length,
                    itemBuilder: (context, index) {
                      return _PurchaseCard(
                        purchase: _purchases[index],
                        purchaseDao: _purchaseDao,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    final double totalAmount = _purchases.fold(
      0,
      (sum, p) => sum + p.totalAmount,
    );
    final int count = _purchases.length;

    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF2D2D3D),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(
            'إجمالي المبلغ',
            '${totalAmount.toStringAsFixed(2)} ج.م',
            Icons.payments,
            Colors.green,
          ),
          _buildSummaryItem(
            'عدد الفواتير',
            '$count',
            Icons.receipt_long,
            Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class _PurchaseCard extends StatefulWidget {
  final EnhancedPurchase purchase;
  final EnhancedPurchaseDao purchaseDao;

  const _PurchaseCard({required this.purchase, required this.purchaseDao});

  @override
  State<_PurchaseCard> createState() => _PurchaseCardState();
}

class _PurchaseCardState extends State<_PurchaseCard> {
  List<(EnhancedPurchaseItem, Product?)> _itemsWithProducts = [];
  bool _isLoadingItems = false;

  Future<void> _loadItems() async {
    if (_itemsWithProducts.isNotEmpty) return;
    setState(() => _isLoadingItems = true);
    try {
      final items = await widget.purchaseDao.getItemsWithProductsByPurchase(
        widget.purchase.id,
      );
      setState(() {
        _itemsWithProducts = items;
        _isLoadingItems = false;
      });
    } catch (e) {
      debugPrint('Error loading purchase items: $e');
      setState(() => _isLoadingItems = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2D2D3D),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          widget.purchase.supplierName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          DateFormat('yyyy-MM-dd HH:mm').format(widget.purchase.purchaseDate),
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${widget.purchase.totalAmount.toStringAsFixed(2)} ج.م',
              style: TextStyle(
                color: widget.purchase.isCreditPurchase
                    ? Colors.orange
                    : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.purchase.isCreditPurchase ? 'آجل' : 'نقدي',
              style: TextStyle(
                color: widget.purchase.isCreditPurchase
                    ? Colors.orange
                    : Colors.green,
                fontSize: 10,
              ),
            ),
          ],
        ),
        onExpansionChanged: (expanded) {
          if (expanded) _loadItems();
        },
        children: [
          if (_isLoadingItems)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(color: Colors.purple),
            )
          else if (_itemsWithProducts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'لا توجد تفاصيل لهذا الأمر',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تفاصيل المنتجات:',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InvoiceItemsTable(
                    items: _itemsWithProducts
                        .map(
                          (e) => InvoiceItemDisplayModel(
                            productName:
                                e.$2?.name ?? 'منتج #${e.$1.productId}',
                            quantity: e.$1.quantity.toDouble(),
                            unitPrice: e.$1.unitPrice,
                            total: e.$1.totalPrice,
                            unit: e.$1.unit,
                          ),
                        )
                        .toList(),
                  ),
                  if (widget.purchase.notes != null &&
                      widget.purchase.notes!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'ملاحظات: ${widget.purchase.notes}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
