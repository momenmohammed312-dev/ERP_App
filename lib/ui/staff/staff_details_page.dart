import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/theme/madar_colors.dart';
import 'attendance_page.dart';
import 'biometric_enrollment_page.dart';
import 'vacations_page.dart';
import 'advances_page.dart';
import 'payroll_page.dart';
import 'performance_page.dart';
import 'staff_form_page.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../services/staff_management_service.dart';
import '../../core/provider/auth_provider.dart';

class StaffDetailsPage extends ConsumerStatefulWidget {
  final Staff staff;

  const StaffDetailsPage({super.key, required this.staff});

  @override
  ConsumerState<StaffDetailsPage> createState() => _StaffDetailsPageState();
}

class _StaffDetailsPageState extends ConsumerState<StaffDetailsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String? _biometricId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadBiometricMapping();
  }

  Future<void> _loadBiometricMapping() async {
    final dao = ref.read(attendanceDeviceDaoProvider);
    final mappings = await dao.getMappingsForStaff(widget.staff.staffId);
    if (mounted) {
      setState(() {
        _biometricId = mappings.isNotEmpty ? mappings.first.externalUserId : null;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MadarColors.bgDark,
      appBar: AppBar(
        title: const Text('تفاصيل الموظف'),
        backgroundColor: MadarColors.bgDark,
        foregroundColor: MadarColors.textLight,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.fingerprint, color: MadarColors.info),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BiometricEnrollmentPage(staff: widget.staff),
                ),
              );
              _loadBiometricMapping();
            },
            tooltip: 'ربط البصمة',
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: MadarColors.gold),
            onPressed: _editStaff,
            tooltip: 'تعديل',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: MadarColors.error),
            onPressed: _deleteStaff,
            tooltip: 'حذف الموظف',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStaffHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBasicInfoTab(),
                AttendancePage(staff: widget.staff),
                VacationsPage(staff: widget.staff),
                AdvancesPage(staff: widget.staff),
                PayrollPage(staff: widget.staff),
                PerformancePage(staff: widget.staff),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffHeader() {
    final isActive = widget.staff.status == 'active' && widget.staff.isActive;
    final statusColor = isActive ? MadarColors.success : MadarColors.error;
    final statusText = isActive ? 'نشط' : 'غير نشط';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: MadarColors.bgCard,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        border: Border.all(color: MadarColors.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        gradient: const LinearGradient(
          colors: [MadarColors.bgCard, Color(0xFF1E2836)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MadarColors.gold.withValues(alpha: 0.15),
                  border: Border.all(
                    color: MadarColors.gold.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.person,
                  size: 34,
                  color: MadarColors.gold,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.staff.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: MadarColors.textLight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.staff.position.isNotEmpty
                          ? widget.staff.position
                          : 'موظف',
                      style: const TextStyle(
                        fontSize: 14,
                        color: MadarColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildHeaderChip(Icons.badge_outlined, widget.staff.staffId),
              _buildHeaderChip(
                Icons.phone_outlined,
                widget.staff.phone ?? 'لا يوجد هاتف',
              ),
              _buildHeaderChip(
                Icons.attach_money,
                CurrencyHelper.formatCurrency(widget.staff.basicSalary),
                color: MadarColors.gold,
              ),
              _buildHeaderChip(
                Icons.fingerprint,
                _biometricId != null ? 'بصمة: $_biometricId' : 'بدون بصمة',
                color: _biometricId != null ? MadarColors.info : MadarColors.textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip(IconData icon, String label, {Color? color}) {
    final chipColor = color ?? MadarColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MadarColors.bgDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: chipColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: chipColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: MadarColors.bgDark,
      child: TabBar(
        controller: _tabController,
        labelColor: MadarColors.gold,
        unselectedLabelColor: MadarColors.textMuted,
        indicatorColor: MadarColors.gold,
        indicatorWeight: 3,
        dividerColor: MadarColors.border,
        tabs: const [
          Tab(icon: Icon(Icons.info_outline), text: 'المعلومات'),
          Tab(icon: Icon(Icons.schedule_outlined), text: 'الحضور'),
          Tab(icon: Icon(Icons.beach_access_outlined), text: 'الإجازات'),
          Tab(icon: Icon(Icons.payments_outlined), text: 'السلف'),
          Tab(icon: Icon(Icons.receipt_long_outlined), text: 'المرتبات'),
          Tab(icon: Icon(Icons.star_outline), text: 'التقييم'),
        ],
      ),
    );
  }

  Widget _buildBasicInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoSection('المعلومات الشخصية', [
            _buildInfoRow('الاسم الكامل', widget.staff.name),
            _buildInfoRow('الرقم الوظيفي', widget.staff.staffId),
            _buildInfoRow(
              'رقم البصمة بالجهاز',
              _biometricId != null ? '$_biometricId (مسجل في الجهاز)' : 'غير مربوط بجهاز بصمة',
            ),
            _buildInfoRow(
              'الرقم القومي',
              widget.staff.nationalId ?? 'غير محدد',
            ),
            _buildInfoRow('رقم الهاتف', widget.staff.phone ?? 'غير محدد'),
            _buildInfoRow(
              'البريد الإلكتروني',
              widget.staff.email ?? 'غير محدد',
            ),
            _buildInfoRow('العنوان', widget.staff.address ?? 'غير محدد'),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection('معلومات العمل', [
            _buildInfoRow('المنصب', widget.staff.position),
            _buildInfoRow('القسم', widget.staff.department ?? 'غير محدد'),
            _buildInfoRow(
              'نوع التوظيف',
              _getEmploymentTypeText(widget.staff.employmentType),
            ),
            _buildInfoRow(
              'تاريخ التعيين',
              '${widget.staff.hireDate.day}/${widget.staff.hireDate.month}/${widget.staff.hireDate.year}',
            ),
            if (widget.staff.contractEndDate != null)
              _buildInfoRow(
                'تاريخ نهاية العقد',
                '${widget.staff.contractEndDate!.day}/${widget.staff.contractEndDate!.month}/${widget.staff.contractEndDate!.year}',
              ),
            _buildInfoRow(
              widget.staff.employmentType == 'weekly'
                  ? 'الراتب الأسبوعي'
                  : widget.staff.employmentType == 'daily'
                      ? 'اليومية (الراتب اليومي)'
                      : 'الراتب الأساسي',
              CurrencyHelper.formatCurrency(widget.staff.basicSalary),
            ),
            if (widget.staff.hourlyRate != null)
              _buildInfoRow(
                'الساعة بالساعة',
                CurrencyHelper.formatCurrency(widget.staff.hourlyRate!),
              ),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection('معلومات البنك', [
            _buildInfoRow('اسم البنك', widget.staff.bankName ?? 'غير محدد'),
            _buildInfoRow('رقم الحساب', widget.staff.bankAccount ?? 'غير محدد'),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection('معلومات الطوارئ', [
            _buildInfoRow(
              'شخص الطوارئ',
              widget.staff.emergencyContact ?? 'غير محدد',
            ),
            _buildInfoRow(
              'رقم هاتف الطوارئ',
              widget.staff.emergencyPhone ?? 'غير محدد',
            ),
          ]),
          if (widget.staff.notes != null && widget.staff.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoSection('ملاحظات', [
              _buildInfoRow('', widget.staff.notes!),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: MadarColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MadarColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: MadarColors.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: MadarColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: MadarColors.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: MadarColors.textLight,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getEmploymentTypeText(String type) {
    switch (type) {
      case 'full_time':
        return 'دوام كامل (شهري)';
      case 'weekly':
        return 'راتب أسبوعي';
      case 'daily':
        return 'يومية / راتب يومي';
      case 'part_time':
        return 'دوام جزئي';
      case 'contract':
        return 'عقد';
      default:
        return type;
    }
  }

  void _editStaff() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StaffFormPage(staff: widget.staff)),
    );
    if (result == true) {
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  void _deleteStaff() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text(
              'تأكيد حذف الموظف',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من حذف الموظف "${widget.staff.name}" نهائياً؟',
              style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'ملاحظة: سيتم استبعاد الموظف من القوائم وأجهزة البصمة، مع الحفاظ على الأثر المحاسبي لسجلات الرواتب السابقة.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Color(0xFFC9A84C))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final db = ref.read(appDatabaseProvider);
        final dao = StaffManagementDao(db);
        final service = StaffManagementService(dao, db);
        final user = ref.read(authProvider);
        await service.deleteStaff(user, widget.staff.staffId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف الموظف "${widget.staff.name}" بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
