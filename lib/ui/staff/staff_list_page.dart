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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final goldColor = const Color(0xFFC9A84C);
    final borderColor = isDark ? const Color(0xFF30363D) : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('إدارة الموظفين'),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
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
          _buildSearchBar(textColor, subTextColor, goldColor, cardBg, borderColor, isDark),
          _buildStatsCards(textColor, goldColor, cardBg, borderColor),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: goldColor))
                : _filteredStaffList.isEmpty
                ? _buildEmptyState(textColor, subTextColor, goldColor)
                : _buildStaffList(textColor, subTextColor, goldColor, cardBg, borderColor, isDark),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewStaff,
        backgroundColor: goldColor,
        foregroundColor: const Color(0xFF0D1117),
        tooltip: 'إضافة موظف جديد',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchBar(Color textColor, Color subTextColor, Color goldColor, Color cardBg, Color borderColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: textColor),
        decoration: InputDecoration(
          hintText: 'البحث بالاسم، المنصب، أو الرقم الوظيفي...',
          hintStyle: TextStyle(color: subTextColor),
          prefixIcon: Icon(Icons.search, color: goldColor),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: subTextColor),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          filled: true,
          fillColor: cardBg,
        ),
      ),
    );
  }

  Widget _buildStatsCards(Color textColor, Color goldColor, Color cardBg, Color borderColor) {
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
          _buildStatCard('$activeStaff', 'موظف نشط', Colors.green, cardBg, borderColor),
          const SizedBox(width: 8),
          _buildStatCard('$totalStaff', 'إجمالي الموظفين', goldColor, cardBg, borderColor),
          const SizedBox(width: 8),
          _buildStatCard(totalSalary.toStringAsFixed(0), 'إجمالي المرتبات', Colors.tealAccent, cardBg, borderColor),
        ],
      ),
    );
  }

  Widget _buildStatCard(String value, String label, Color color, Color cardBg, Color borderColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color textColor, Color subTextColor, Color goldColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: subTextColor),
          const SizedBox(height: 16),
          Text(
            'لا يوجد موظفين',
            style: TextStyle(fontSize: 22, color: textColor),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على زر الإضافة لإنشاء موظف جديد',
            style: TextStyle(color: subTextColor),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addNewStaff,
            icon: const Icon(Icons.add),
            label: const Text('إضافة موظف جديد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: goldColor,
              foregroundColor: const Color(0xFF0D1117),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffList(Color textColor, Color subTextColor, Color goldColor, Color cardBg, Color borderColor, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _filteredStaffList.length,
      itemBuilder: (context, index) {
        final staff = _filteredStaffList[index];
        return _buildStaffCard(staff, textColor, subTextColor, goldColor, cardBg, borderColor, isDark);
      },
    );
  }

  Widget _buildStaffCard(Staff staff, Color textColor, Color subTextColor, Color goldColor, Color cardBg, Color borderColor, bool isDark) {
    final isActive = staff.status == 'active' && staff.isActive;
    final statusColor = isActive ? Colors.green : Colors.redAccent;
    final statusText = isActive ? 'نشط' : 'غير نشط';

    return Card(
      color: cardBg,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.green.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.15),
          child: Icon(
            Icons.person,
            color: isActive ? Colors.green : Colors.redAccent,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                staff.name,
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withValues(alpha: 0.5)),
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
            Text(staff.position, style: TextStyle(color: subTextColor)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.badge, size: 16, color: subTextColor),
                const SizedBox(width: 4),
                Text(staff.staffId, style: TextStyle(color: subTextColor)),
                const SizedBox(width: 16),
                Icon(Icons.phone, size: 16, color: subTextColor),
                const SizedBox(width: 4),
                Text(staff.phone ?? 'لا يوجد', style: TextStyle(color: subTextColor)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.attach_money, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'المرتب الأساسي: ${staff.basicSalary.toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          color: cardBg,
          iconColor: subTextColor,
          onSelected: (value) => _handleMenuAction(value, staff),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, color: goldColor),
                  const SizedBox(width: 8),
                  Text('عرض التفاصيل', style: TextStyle(color: textColor)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text('تعديل', style: TextStyle(color: textColor)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'attendance',
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('سجل الحضور', style: TextStyle(color: textColor)),
                ],
              ),
            ),
            if (isActive) ...[
              PopupMenuItem(
                value: 'terminate',
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text('إنهاء الخدمة', style: TextStyle(color: textColor)),
                  ],
                ),
              ),
            ] else ...[
              PopupMenuItem(
                value: 'activate',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('تفعيل', style: TextStyle(color: textColor)),
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
        backgroundColor: const Color(0xFF161B22),
        title: const Text('تأكيد إنهاء الخدمة'),
        content: Text(
          'هل أنت متأكد من إنهاء خدمة الموظف "${staff.name}"؟',
          style: const TextStyle(color: Color(0xFFE6EDF3)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Color(0xFFC9A84C))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنهاء الخدمة: $e')),
        );
      }
    }
  }

  void _activateStaff(Staff staff) async {
    try {
      await _service.updateStaffInfo(staffId: staff.staffId, status: 'active');
      _loadStaff();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تفعيل الموظف بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تفعيل الموظف: $e')),
      );
    }
  }
}
