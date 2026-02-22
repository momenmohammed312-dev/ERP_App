import 'package:flutter/material.dart';
import '../utils/constants.dart';

class CustomerManagement extends StatefulWidget {
  const CustomerManagement({super.key});

  @override
  State<CustomerManagement> createState() => _CustomerManagementState();
}

class _CustomerManagementState extends State<CustomerManagement> {
  String _searchQuery = '';
  String _selectedFilter = 'الكل';
  final List<String> _filters = ['الكل', 'نشط', 'غير نشط', 'مدين'];

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
                'إدارة العملاء',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryColor,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _addNewCustomer(),
                icon: const Icon(Icons.person_add),
                label: const Text('عميل جديد'),
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
                    hintText: 'البحث عن عميل...',
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
                  value: _selectedFilter,
                  decoration: InputDecoration(
                    labelText: 'الحالة',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: _filters.map((filter) {
                    return DropdownMenuItem(
                      value: filter,
                      child: Text(filter),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedFilter = value!;
                    });
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Stats Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'إجمالي العملاء',
                  '245',
                  Icons.people,
                  AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'العملاء النشطون',
                  '198',
                  Icons.person,
                  AppColors.successColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'العملاء المدينون',
                  '47',
                  Icons.account_balance,
                  AppColors.warningColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Customers Table
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
                          child: Text('اسم العميل',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('الهاتف',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('الرصيد',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('الحالة',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      SizedBox(width: 120, child: Text('')),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Customers List
                _buildCustomersList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomersList() {
    // Mock data - في التطبيق الحقيقي سيتم جلب البيانات من API
    final customers = [
      {
        'name': 'أحمد محمد',
        'phone': '0501234567',
        'balance': '1,234.50',
        'status': 'نشط',
      },
      {
        'name': 'فاطمة علي',
        'phone': '0507654321',
        'balance': '-450.00',
        'status': 'نشط',
      },
      {
        'name': 'محمد سعيد',
        'phone': '0509876543',
        'balance': '2,456.75',
        'status': 'نشط',
      },
      {
        'name': 'خالد أحمد',
        'phone': '0502345678',
        'balance': '-890.25',
        'status': 'مدين',
      },
      {
        'name': 'عمر خالد',
        'phone': '0503456789',
        'balance': '567.25',
        'status': 'نشط',
      },
    ];

    // Filter customers
    var filteredCustomers = customers.where((customer) {
      final matchesSearch = _searchQuery.isEmpty ||
          (customer['name'] as String)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      final matchesFilter =
          _selectedFilter == 'الكل' || customer['status'] == _selectedFilter;
      return matchesSearch && matchesFilter;
    }).toList();

    if (filteredCustomers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'لا توجد عملاء',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: filteredCustomers.map((customer) {
        return _buildCustomerRow(customer);
      }).toList(),
    );
  }

  Widget _buildCustomerRow(Map<String, dynamic> customer) {
    final isActive = customer['status'] == 'نشط';
    final isDebtor = (customer['balance'] as String).startsWith('-');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer['name']!,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  customer['phone']!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${customer['balance']} ج.م',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDebtor ? AppColors.errorColor : AppColors.successColor,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.successColor.withValues(alpha: 0.1)
                    : AppColors.errorColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                customer['status']!,
                style: TextStyle(
                  color:
                      isActive ? AppColors.successColor : AppColors.errorColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 20),
                  onPressed: () => _viewCustomerDetails(customer),
                  tooltip: 'عرض التفاصيل',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editCustomer(customer),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete,
                      size: 20, color: AppColors.errorColor),
                  onPressed: () => _deleteCustomer(customer),
                  tooltip: 'حذف',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewCustomer() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة عميل جديد'),
        content: const Text('نموذج إضافة عميل جديد - قيد التطوير'),
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

  void _viewCustomerDetails(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل العميل: ${customer['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الهاتف: ${customer['phone']}'),
              Text('الرصيد: ${customer['balance']} ج.م'),
              Text('الحالة: ${customer['status']}'),
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

  void _editCustomer(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل العميل: ${customer['name']}'),
        content: const Text('نموذج تعديل العميل - قيد التطوير'),
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

  void _deleteCustomer(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف العميل "${customer['name']}"؟'),
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
                  content: Text('تم حذف العميل بنجاح'),
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
