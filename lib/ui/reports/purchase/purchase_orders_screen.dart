import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/dao/enhanced_purchase_dao.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class PurchaseOrdersScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersScreen> createState() =>
      _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends ConsumerState<PurchaseOrdersScreen> {
  bool _isLoading = true;
  List<EnhancedPurchase> _purchases = [];
  String _searchQuery = '';
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
      final purchases = await _purchaseDao.getAllPurchases();
      // Sort by date desc
      purchases.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
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
    final filteredPurchases = _purchases.where((p) {
      final query = _searchQuery.toLowerCase();
      return p.purchaseNumber.toLowerCase().contains(query) ||
          p.supplierName.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        title: const Text('أوامر الشراء'),
        backgroundColor: const Color(0xFF2D2D3D),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'بحث برقم الفاتورة أو المورد...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredPurchases.length,
              itemBuilder: (context, index) {
                final purchase = filteredPurchases[index];
                return Card(
                  color: const Color(0xFF2D2D3D),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: Text(
                      purchase.purchaseNumber,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          purchase.supplierName,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        Text(
                          DateFormat(
                            'yyyy-MM-dd HH:mm',
                          ).format(purchase.purchaseDate),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    trailing: Text(
                      '${purchase.totalAmount.toStringAsFixed(2)} ج.م',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () {
                      // We could show details here too, similar to PurchaseReportsScreen
                    },
                  ),
                );
              },
            ),
    );
  }
}
