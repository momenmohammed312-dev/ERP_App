import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/inventory_service.dart';

/// Inventory Report Tab
/// تبويب تقرير المخزون - عرض حالة المخزون والمنتجات
class InventoryReportTab extends ConsumerStatefulWidget {
  const InventoryReportTab({super.key});

  @override
  ConsumerState<InventoryReportTab> createState() => _InventoryReportTabState();
}

class _InventoryReportTabState extends ConsumerState<InventoryReportTab> {
  final int _lowStockThreshold = 10;
  List<Product> _lowStockProducts = [];
  Map<String, dynamic> _inventoryStats = {};
  Map<String, List<Product>> _productsByCategory = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInventoryData();
  }

  Future<void> _loadInventoryData() async {
    setState(() => _isLoading = true);

    try {
      final db = ref.read(appDatabaseProvider);
      final inventoryService = InventoryService(db);

      // Get low stock products
      final lowStock = await inventoryService.getLowStockProducts(
        _lowStockThreshold,
      );

      // Get inventory valuation
      final stats = await inventoryService.getInventoryValuation();

      // Get products by category
      final byCategory = await inventoryService.getInventoryByCategory();

      setState(() {
        _lowStockProducts = lowStock;
        _inventoryStats = stats;
        _productsByCategory = byCategory;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading inventory data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadInventoryData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'تقرير المخزون',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadInventoryData,
                  tooltip: 'تحديث',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats Cards
            _buildStatsSection(),

            const SizedBox(height: 24),

            // Low Stock Warning
            if (_lowStockProducts.isNotEmpty) ...[
              _buildLowStockWarning(),
              const SizedBox(height: 24),
            ],

            // Products by Category
            _buildCategoriesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    final totalProducts = _inventoryStats['totalProducts'] ?? 0;
    final totalValue = _inventoryStats['totalValue'] ?? 0.0;
    final totalQuantity = _inventoryStats['totalQuantity'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'إجمالي المنتجات',
            value: totalProducts.toString(),
            icon: Icons.inventory_2,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'القيمة الإجمالية',
            value: '${totalValue.toStringAsFixed(2)} ج.م',
            icon: Icons.attach_money,
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'إجمالي الكميات',
            value: totalQuantity.toString(),
            icon: Icons.numbers,
            color: Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockWarning() {
    return Card(
      color: Colors.orange.shade50,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning, color: Colors.orange, size: 28),
                const SizedBox(width: 12),
                Text(
                  'تنبيه: منتجات بمخزون منخفض (${_lowStockProducts.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            ..._lowStockProducts.take(5).map((product) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: product.quantity < 5
                          ? Colors.red.shade100
                          : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${product.quantity} ${product.unit ?? "قطعة"}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: (product.quantity) < 5
                              ? Colors.red
                              : Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (_lowStockProducts.length > 5) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => _showAllLowStockProducts(),
                  child: Text('عرض الكل (${_lowStockProducts.length})'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesSection() {
    if (_productsByCategory.isEmpty) {
      return const Center(child: Text('لا توجد منتجات في المخزون'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'المنتجات حسب الفئة',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._productsByCategory.entries.map((entry) {
          final category = entry.key;
          final products = entry.value;
          final totalValue = products.fold<double>(
            0,
            (sum, p) => sum + (p.price * p.quantity),
          );

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: const Icon(Icons.category),
              title: Text(
                category,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${products.length} منتج - ${totalValue.toStringAsFixed(2)} ج.م',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: products.map((product) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(product.name)),
                            Text(
                              '${product.quantity} × ${product.price.toStringAsFixed(2)} = ${(product.quantity * product.price).toStringAsFixed(2)} ج.م',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  void _showAllLowStockProducts() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('جميع المنتجات بمخزون منخفض'),
        content: SizedBox(
          width: 400,
          height: 400,
          child: ListView.builder(
            itemCount: _lowStockProducts.length,
            itemBuilder: (context, index) {
              final product = _lowStockProducts[index];
              return ListTile(
                title: Text(product.name),
                subtitle: Text('الفئة: ${product.category ?? "غير محدد"}'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: product.quantity < 5
                        ? Colors.red.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${product.quantity} ${product.unit ?? ""}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: product.quantity < 5 ? Colors.red : Colors.orange,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
