import 'package:flutter/material.dart';
import '../utils/constants.dart';

class UserManagement extends StatefulWidget {
  const UserManagement({super.key});

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  String _searchQuery = '';
  String _selectedRole = 'الكل';
  String _selectedStatus = 'الكل';
  final List<String> _roles = ['الكل', 'مدير', 'كاشير', 'مستخدم عادي'];
  final List<String> _statuses = ['الكل', 'نشط', 'غير نشط'];

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
                'إدارة المستخدمين',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryColor,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _addNewUser(),
                icon: const Icon(Icons.person_add),
                label: const Text('مستخدم جديد'),
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
                    hintText: 'البحث عن مستخدم...',
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
                  value: _selectedRole,
                  decoration: InputDecoration(
                    labelText: 'الصلاحية',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: _roles.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedRole = value!;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _selectedStatus,
                  decoration: InputDecoration(
                    labelText: 'الحالة',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: _statuses.map((status) {
                    return DropdownMenuItem(
                      value: status,
                      child: Text(status),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value!;
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
                  'إجمالي المستخدمين',
                  '12',
                  Icons.people,
                  AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'المستخدمون النشطون',
                  '8',
                  Icons.person,
                  AppColors.successColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'المديرون',
                  '2',
                  Icons.admin_panel_settings,
                  AppColors.warningColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Users Table
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
                          child: Text('اسم المستخدم',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('البريد الإلكتروني',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('الصلاحية',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('الحالة',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          child: Text('آخر تسجيل دخول',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      SizedBox(width: 120, child: Text('')),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Users List
                _buildUsersList(),
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

  Widget _buildUsersList() {
    // Mock data - في التطبيق الحقيقي سيتم جلب البيانات من API
    final users = [
      {
        'username': 'admin',
        'email': 'admin@pos.com',
        'role': 'مدير',
        'status': 'نشط',
        'lastLogin': '2024-01-15 14:30',
      },
      {
        'username': 'cashier1',
        'email': 'cashier1@pos.com',
        'role': 'كاشير',
        'status': 'نشط',
        'lastLogin': '2024-01-15 09:15',
      },
      {
        'username': 'user1',
        'email': 'user1@pos.com',
        'role': 'مستخدم عادي',
        'status': 'نشط',
        'lastLogin': '2024-01-14 16:45',
      },
      {
        'username': 'cashier2',
        'email': 'cashier2@pos.com',
        'role': 'كاشير',
        'status': 'غير نشط',
        'lastLogin': '2024-01-10 11:20',
      },
    ];

    // Filter users
    var filteredUsers = users.where((user) {
      final matchesSearch = _searchQuery.isEmpty ||
          (user['username'] as String)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      final matchesRole =
          _selectedRole == 'الكل' || user['role'] == _selectedRole;
      final matchesStatus =
          _selectedStatus == 'الكل' || user['status'] == _selectedStatus;
      return matchesSearch && matchesRole && matchesStatus;
    }).toList();

    if (filteredUsers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'لا توجد مستخدمين',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: filteredUsers.map((user) {
        return _buildUserRow(user);
      }).toList(),
    );
  }

  Widget _buildUserRow(Map<String, dynamic> user) {
    final isActive = user['status'] == 'نشط';

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
                  user['username']!,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  user['email']!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Expanded(child: Text(user['role']!)),
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
                user['status']!,
                style: TextStyle(
                  color:
                      isActive ? AppColors.successColor : AppColors.errorColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              user['lastLogin']!,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 20),
                  onPressed: () => _viewUserDetails(user),
                  tooltip: 'عرض التفاصيل',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editUser(user),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: Icon(
                    isActive ? Icons.block : Icons.check_circle,
                    size: 20,
                    color: isActive
                        ? AppColors.warningColor
                        : AppColors.successColor,
                  ),
                  onPressed: () => _toggleUserStatus(user),
                  tooltip: isActive ? 'تعطيل' : 'تفعيل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete,
                      size: 20, color: AppColors.errorColor),
                  onPressed: () => _deleteUser(user),
                  tooltip: 'حذف',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewUser() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة مستخدم جديد'),
        content: const Text('نموذج إضافة مستخدم جديد - قيد التطوير'),
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

  void _viewUserDetails(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل المستخدم: ${user['username']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('اسم المستخدم: ${user['username']}'),
              Text('البريد الإلكتروني: ${user['email']}'),
              Text('الصلاحية: ${user['role']}'),
              Text('الحالة: ${user['status']}'),
              Text('آخر تسجيل دخول: ${user['lastLogin']}'),
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

  void _editUser(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل المستخدم: ${user['username']}'),
        content: const Text('نموذج تعديل المستخدم - قيد التطوير'),
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

  void _toggleUserStatus(Map<String, dynamic> user) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'تم ${user['status'] == 'نشط' ? 'تعطيل' : 'تفعيل'} المستخدم بنجاح'),
        backgroundColor: AppColors.successColor,
      ),
    );
  }

  void _deleteUser(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المستخدم "${user['username']}"؟'),
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
                  content: Text('تم حذف المستخدم بنجاح'),
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
