import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../services/staff_management_service_simple.dart';
import 'staff_form_page.dart';
import 'staff_details_page.dart';
import 'attendance_page.dart';

class StaffListPage extends ConsumerStatefulWidget {
  const StaffListPage({super.key});

  @override
  ConsumerState<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends ConsumerState<StaffListPage> {
  late StaffManagementService _service;
  late StaffManagementDao _dao;
  List<Staff> _staffList = [];
  List<Staff> _filteredStaffList = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
    _searchController.addListener(_filterStaff);
  }

  Future<void> _init() async {
    await _initializeService();
    await _loadStaff();
  }

  Future<void> _initializeService() async {
    final db = ref.read(appDatabaseProvider);
    _dao = StaffManagementDao(db);
    _service = StaffManagementService(_dao);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final staff = await _dao.getAllStaff();
      setState(() {
        _staffList = staff;
        _filteredStaffList = staff;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تحميل بيانات الموظفين: $e')),
      );
    }
  }

  void _filterStaff() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStaffList = _staffList
          .where(
            (staff) =>
                staff.name.toLowerCase().contains(query) ||
                staff.position.toLowerCase().contains(query) ||
                staff.staffId.toLowerCase().contains(query) ||
                (staff.phone?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الموظفين'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStaff,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildStatsCards(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredStaffList.isEmpty
                ? _buildEmptyState()
                : _buildStaffList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewStaff,
        backgroundColor: Colors.green,
        tooltip: 'إضافة موظف جديد',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: Colors.black87),
        decoration: InputDecoration(
          hintText: 'البحث بالاسم، المنصب، أو الرقم الوظيفي...',
          hintStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    final activeStaff = _staffList
        .where((s) => s.status == 'active' && s.isActive)
        .length;
    final totalStaff = _staffList.length;
    final totalSalary = _staffList.fold<double>(
      0,
      (sum, staff) => sum + staff.basicSalary,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      '$activeStaff',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'موظف نشط',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      '$totalStaff',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'إجمالي الموظفين',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      totalSalary.toStringAsFixed(0),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'إجمالي المرتبات',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد موظفين',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على زر الإضافة لإنشاء موظف جديد',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addNewStaff,
            icon: const Icon(Icons.add),
            label: const Text('إضافة موظف جديد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _filteredStaffList.length,
      itemBuilder: (context, index) {
        final staff = _filteredStaffList[index];
        return _buildStaffCard(staff);
      },
    );
  }

  Widget _buildStaffCard(Staff staff) {
    final isActive = staff.status == 'active' && staff.isActive;
    final statusColor = isActive ? Colors.green : Colors.red;
    final statusText = isActive ? 'نشط' : 'غير نشط';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.green[100] : Colors.red[100],
          child: Icon(
            Icons.person,
            color: isActive ? Colors.green[700] : Colors.red[700],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                staff.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(staff.position),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.badge, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(staff.staffId, style: TextStyle(color: Colors.grey[600])),
                const SizedBox(width: 16),
                Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  staff.phone ?? 'لا يوجد',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.attach_money, size: 16, color: Colors.green[600]),
                const SizedBox(width: 4),
                Text(
                  'المرتب الأساسي: ${staff.basicSalary.toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleMenuAction(value, staff),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('عرض التفاصيل'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('تعديل'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'attendance',
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.green),
                  SizedBox(width: 8),
                  Text('سجل الحضور'),
                ],
              ),
            ),
            if (isActive) ...[
              const PopupMenuItem(
                value: 'terminate',
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.red),
                    SizedBox(width: 8),
                    Text('إنهاء الخدمة'),
                  ],
                ),
              ),
            ] else ...[
              const PopupMenuItem(
                value: 'activate',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('تفعيل'),
                  ],
                ),
              ),
            ],
          ],
        ),
        onTap: () => _viewStaffDetails(staff),
      ),
    );
  }

  void _handleMenuAction(String action, Staff staff) async {
    switch (action) {
      case 'view':
        _viewStaffDetails(staff);
        break;
      case 'edit':
        _editStaff(staff);
        break;
      case 'attendance':
        _viewAttendance(staff);
        break;
      case 'terminate':
        _terminateStaff(staff);
        break;
      case 'activate':
        _activateStaff(staff);
        break;
    }
  }

  void _addNewStaff() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StaffFormPage()),
    );
    if (result == true) {
      _loadStaff();
    }
  }

  void _viewStaffDetails(Staff staff) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StaffDetailsPage(staff: staff)),
    );
  }

  void _editStaff(Staff staff) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StaffFormPage(staff: staff)),
    );
    if (result == true) {
      _loadStaff();
    }
  }

  void _viewAttendance(Staff staff) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AttendancePage(staff: staff)),
    );
  }

  void _terminateStaff(Staff staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إنهاء الخدمة'),
        content: Text('هل أنت متأكد من إنهاء خدمة الموظف "${staff.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('إنهاء الخدمة'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.terminateStaff(staff.staffId);
        _loadStaff();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنهاء خدمة الموظف بنجاح')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في إنهاء الخدمة: $e')));
      }
    }
  }

  void _activateStaff(Staff staff) async {
    try {
      await _service.updateStaffInfo(staffId: staff.staffId, status: 'active');
      _loadStaff();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تفعيل الموظف بنجاح')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في تفعيل الموظف: $e')));
    }
  }
}
