import 'package:flutter/material.dart';
import '../utils/constants.dart';

class InventoryManagement extends StatefulWidget {
  const InventoryManagement({super.key});

  @override
  State<InventoryManagement> createState() => _InventoryManagementState();
}

class _InventoryManagementState extends State<InventoryManagement> {
  String _searchQuery = '';
  String _selectedCategory = 'الكل';
  final List<String> _categories = [
    'الكل',
    'إلكترونيات',
    'ملابس',
    'أطعمة',
    'أخرى'
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'إدارة المخزون',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryColor,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _addNewProduct(),
                icon: const Icon(Icons.add),
                label: const Text('منتج جديد'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Search and Filter Row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'البحث عن منتج...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'الفئة',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: _categories.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                    });
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Products Table
          Card(
            child: Column(
              children: [
                // Table Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: Text('اسم المنتج',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('الباركود',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('الفئة',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('السعر',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('الكمية',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('الحالة',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      SizedBox(width: 100, child: Text('')),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Products List
                _buildProductsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList() {
    // Mock data - في التطبيق الحقيقي سيتم جلب البيانات من API
    final products = [
      {
        'name': 'لابتوب Dell XPS 15',
        'barcode': '1234567890123',
        'category': 'إلكترونيات',
        'price': '12,999.00',
        'stock': 25,
        'status': 'متوفر',
      },
      {
        'name': 'هاتف Samsung Galaxy S21',
        'barcode': '9876543210987',
        'category': 'إلكترونيات',
        'price': '4,599.00',
        'stock': 12,
        'status': 'متوفر',
      },
      {
        'name': 'تيشيرت رجالي قطن',
        'barcode': '5556667778889',
        'category': 'ملابس',
        'price': '299.00',
        'stock': 50,
        'status': 'متوفر',
      },
      {
        'name': 'قهوة عربية',
        'barcode': '1112223334445',
        'category': 'أطعمة',
        'price': '45.00',
        'stock': 100,
        'status': 'متوفر',
      },
      {
        'name': 'شاحن معطر',
        'barcode': '9998887776665',
        'category': 'أخرى',
        'price': '25.00',
        'stock': 0,
        'status': 'نفذ',
      },
    ];

    // Filter products
    var filteredProducts = products.where((product) {
      final matchesSearch = _searchQuery.isEmpty ||
          (product['name'] as String)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == 'الكل' ||
          product['category'] == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    if (filteredProducts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'لا توجد منتجات',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: filteredProducts.map((product) {
        return _buildProductRow(product);
      }).toList(),
    );
  }

  Widget _buildProductRow(Map<String, dynamic> product) {
    final isOutOfStock = product['stock'] == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              product['name']!,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(product['barcode']!)),
          Expanded(child: Text(product['category']!)),
          Expanded(
            child: Text(
              '${product['price']} ج.م',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              '${product['stock']}',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: (product['stock'] as int) > 10
                    ? AppColors.successColor
                    : AppColors.warningColor,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: !isOutOfStock
                    ? AppColors.successColor.withValues(alpha: 0.1)
                    : AppColors.errorColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                product['status']!,
                style: TextStyle(
                  color: !isOutOfStock
                      ? AppColors.successColor
                      : AppColors.errorColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 20),
                  onPressed: () => _viewProductDetails(product),
                  tooltip: 'عرض التفاصيل',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editProduct(product),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete,
                      size: 20, color: AppColors.errorColor),
                  onPressed: () => _deleteProduct(product),
                  tooltip: 'حذف',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewProduct() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة منتج جديد'),
        content: const Text('نموذج إضافة منتج جديد - قيد التطوير'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _viewProductDetails(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل المنتج: ${product['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الباركود: ${product['barcode']}'),
              Text('الفئة: ${product['category']}'),
              Text('السعر: ${product['price']} ج.م'),
              Text('الكمية: ${product['stock']}'),
              Text('الحالة: ${product['status']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _editProduct(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل المنتج: ${product['name']}'),
        content: const Text('نموذج تعديل المنتج - قيد التطوير'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _deleteProduct(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المنتج "${product['name']}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم حذف المنتج بنجاح'),
                  backgroundColor: AppColors.successColor,
                ),
              );
            },
            child: const Text('حذف',
                style: TextStyle(color: AppColors.errorColor)),
          ),
        ],
      ),
    );
  }
}
