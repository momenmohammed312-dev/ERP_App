import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../services/data_service.dart';
import '../models/client_model.dart';

class CustomerManagement extends StatefulWidget {
  const CustomerManagement({super.key});

  @override
  State<CustomerManagement> createState() => _CustomerManagementState();
}

class _CustomerManagementState extends State<CustomerManagement> {
  final DataService _dataService = DataService();
  String _searchQuery = '';
  String _selectedFilter = 'الكل';
  final List<String> _filters = ['الكل', 'نشط', 'غير نشط', 'مدين'];

  @override
  void initState() {
    super.initState();
    _dataService.init().then((_) {
      if (mounted) setState(() {});
    });
  }

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
                  initialValue: _selectedFilter,
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
          _buildStatsCards(),

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

  Widget _buildStatsCards() {
    final clients = _dataService.getClients();
    final activeCount = clients.where((c) => c.isActive).length;
    final debtorCount =
        clients.where((c) => c.totalPaid < 0).length; // Adjust logic as needed

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 3
            : (constraints.maxWidth > 600 ? 2 : 1);
        const spacing = 16.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (crossAxisCount - 1))) /
                crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                'إجمالي العملاء',
                clients.length.toString(),
                Icons.people,
                AppColors.primaryColor,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                'العملاء النشطون',
                activeCount.toString(),
                Icons.person,
                AppColors.successColor,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildStatCard(
                'العملاء المدينون',
                debtorCount.toString(),
                Icons.account_balance,
                AppColors.warningColor,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
      ),
    );
  }

  Widget _buildCustomersList() {
    final clients = _dataService.getClients();

    // Filter customers
    var filteredCustomers = clients.where((client) {
      final matchesSearch = _searchQuery.isEmpty ||
          client.name.toLowerCase().contains(_searchQuery.toLowerCase());

      final bool matchesFilter = _selectedFilter == 'الكل' ||
          (_selectedFilter == 'نشط' && client.isActive) ||
          (_selectedFilter == 'غير نشط' && !client.isActive) ||
          (_selectedFilter == 'مدين' && client.totalPaid < 0);

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
      children: filteredCustomers.map((client) {
        return _buildCustomerRow(client);
      }).toList(),
    );
  }

  Widget _buildCustomerRow(ClientModel client) {
    final isActive = client.isActive;
    final isDebtor = client.totalPaid < 0; // Simplified for now

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
                  client.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  client.phone,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${client.totalPaid.toStringAsFixed(2)} ج.م',
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
                isActive ? 'نشط' : 'غير نشط',
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
                  onPressed: () => _viewCustomerDetails(client),
                  tooltip: 'عرض التفاصيل',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editCustomer(client),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete,
                      size: 20, color: AppColors.errorColor),
                  onPressed: () => _deleteCustomer(client),
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
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    String packageType = 'basic';
    bool isActive = true;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة عميل جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'اسم العميل'),
                ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'الهاتف'),
                ),
                TextField(
                  controller: emailController,
                  decoration:
                      const InputDecoration(labelText: 'البريد الإلكتروني'),
                ),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: packageType,
                  decoration: const InputDecoration(labelText: 'الباقة'),
                  items: [
                    const DropdownMenuItem(
                        value: 'basic', child: Text('أساسي')),
                    const DropdownMenuItem(
                        value: 'standard', child: Text('قياسي')),
                    const DropdownMenuItem(
                        value: 'professional', child: Text('احترافي')),
                  ],
                  onChanged: (value) => packageType = value!,
                ),
                SwitchListTile(
                  title: const Text('نشط'),
                  value: isActive,
                  onChanged: (value) => setState(() => isActive = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newClient = ClientModel(
                  id: '',
                  name: nameController.text,
                  phone: phoneController.text,
                  email: emailController.text,
                  address: addressController.text,
                  packageType: packageType,
                  createdAt: DateTime.now(),
                  isActive: isActive,
                );
                await _dataService.addClient(newClient);
                if (mounted) {
                  Navigator.of(context).pop();
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم إضافة العميل بنجاح')),
                  );
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _viewCustomerDetails(ClientModel client) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تفاصيل العميل: ${client.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(Icons.phone, 'الهاتف', client.phone),
              _detailRow(Icons.email, 'البريد', client.email),
              _detailRow(Icons.location_on, 'العنوان', client.address),
              _detailRow(Icons.inventory, 'الباقة', client.packageDisplayName),
              _detailRow(Icons.calendar_today, 'تاريخ البدء',
                  '${client.createdAt.year}-${client.createdAt.month}-${client.createdAt.day}'),
              _detailRow(
                  Icons.money, 'إجمالي المدفوع', '${client.totalPaid} ج.م'),
              _detailRow(Icons.check_circle, 'الحالة',
                  client.isActive ? 'نشط' : 'غير نشط'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryColor),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  void _editCustomer(ClientModel client) {
    final nameController = TextEditingController(text: client.name);
    final phoneController = TextEditingController(text: client.phone);
    final emailController = TextEditingController(text: client.email);
    final addressController = TextEditingController(text: client.address);
    String packageType = client.packageType;
    bool isActive = client.isActive;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعديل العميل'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'اسم العميل'),
                ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'الهاتف'),
                ),
                TextField(
                  controller: emailController,
                  decoration:
                      const InputDecoration(labelText: 'البريد الإلكتروني'),
                ),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: packageType,
                  decoration: const InputDecoration(labelText: 'الباقة'),
                  items: [
                    const DropdownMenuItem(
                        value: 'basic', child: Text('أساسي')),
                    const DropdownMenuItem(
                        value: 'standard', child: Text('قياسي')),
                    const DropdownMenuItem(
                        value: 'professional', child: Text('احترافي')),
                  ],
                  onChanged: (value) => packageType = value!,
                ),
                SwitchListTile(
                  title: const Text('نشط'),
                  value: isActive,
                  onChanged: (value) => setState(() => isActive = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updatedClient = client.copyWith(
                  name: nameController.text,
                  phone: phoneController.text,
                  email: emailController.text,
                  address: addressController.text,
                  packageType: packageType,
                  isActive: isActive,
                );
                await _dataService.updateClient(updatedClient);
                if (mounted) {
                  Navigator.of(context).pop();
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تعديل العميل بنجاح')),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteCustomer(ClientModel client) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل أنت متأكد من حذف العميل "${client.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                await _dataService.deleteClient(client.id);
                if (mounted) {
                  Navigator.of(context).pop();
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم حذف العميل بنجاح'),
                      backgroundColor: AppColors.successColor,
                    ),
                  );
                }
              },
              child: const Text('حذف',
                  style: TextStyle(color: AppColors.errorColor)),
            ),
          ],
        ),
      ),
    );
  }
}
