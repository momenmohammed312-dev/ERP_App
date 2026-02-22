import 'package:flutter/material.dart';
import '../../core/database/app_database.dart';
import '../../core/utils/currency_helper.dart';
import 'attendance_page.dart';
import 'vacations_page.dart';
import 'advances_page.dart';
import 'payroll_page.dart';
import 'performance_page.dart';
import 'staff_form_page.dart';

class StaffDetailsPage extends StatefulWidget {
  final Staff staff;

  const StaffDetailsPage({super.key, required this.staff});

  @override
  State<StaffDetailsPage> createState() => _StaffDetailsPageState();
}

class _StaffDetailsPageState extends State<StaffDetailsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تفاصيل الموظف'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editStaff,
            tooltip: 'تعديل',
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
    final statusColor = isActive ? Colors.green : Colors.red;
    final statusText = isActive ? 'نشط' : 'غير نشط';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[700]!, Colors.blue[500]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Colors.blue[700]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.staff.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      widget.staff.position,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.badge, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.staff.staffId,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(width: 24),
              Icon(Icons.phone, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.staff.phone ?? 'لا يوجد',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(width: 24),
              Icon(Icons.attach_money, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                CurrencyHelper.formatCurrency(widget.staff.basicSalary),
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.blue[700],
        unselectedLabelColor: Colors.grey[600],
        indicatorColor: Colors.blue[700],
        tabs: const [
          Tab(icon: Icon(Icons.info), text: 'المعلومات'),
          Tab(icon: Icon(Icons.schedule), text: 'الحضور'),
          Tab(icon: Icon(Icons.beach_access), text: 'الإجازات'),
          Tab(icon: Icon(Icons.money), text: 'السلف'),
          Tab(icon: Icon(Icons.payment), text: 'المرتبات'),
          Tab(icon: Icon(Icons.star), text: 'التقييم'),
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
              'الراتب الأساسي',
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.blue[700],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.grey[800])),
          ),
        ],
      ),
    );
  }

  String _getEmploymentTypeText(String type) {
    switch (type) {
      case 'full_time':
        return 'دوام كامل';
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
}
