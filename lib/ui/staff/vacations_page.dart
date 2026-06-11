import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/provider/auth_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/models/user_model.dart';
import 'package:intl/intl.dart';

class VacationsPage extends ConsumerStatefulWidget {
  final Staff staff;

  const VacationsPage({super.key, required this.staff});

  @override
  ConsumerState<VacationsPage> createState() => _VacationsPageState();
}

class _VacationsPageState extends ConsumerState<VacationsPage> {
  late StaffManagementDao _dao;
  List<Vacation> _vacations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = ref.read(appDatabaseProvider);
    _dao = StaffManagementDao(db);
    try {
      final vacations = await _dao.getVacationsByStaff(widget.staff.staffId);
      setState(() {
        _vacations = vacations.reversed.toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في تحميل سجل الإجازات: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _vacations.isEmpty
          ? _buildEmptyState()
          : _buildVacationsList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _requestVacation,
        backgroundColor: Colors.orange,
        tooltip: 'طلب إجازة',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.beach_access, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد طلبات إجازة لهذا الموظف',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildVacationsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _vacations.length,
      itemBuilder: (context, index) {
        final vacation = _vacations[index];
        return _buildVacationCard(vacation);
      },
    );
  }

  Future<void> _approveVacation(Vacation vacation) async {
    final user = ref.read(authProvider);
    if (user == null) return;
    try {
      await _dao.approveVacation(vacation.id, user.fullName);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم قبول الإجازة'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectVacation(Vacation vacation) async {
    final reasonController = TextEditingController();
    final user = ref.read(authProvider);
    if (user == null) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض الإجازة'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'سبب الرفض',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reasonController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('رفض'),
          ),
        ],
      ),
    );

    if (reason != null && reason.isNotEmpty) {
      try {
        await _dao.rejectVacation(vacation.id, user.fullName, reason);
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم رفض الإجازة'), backgroundColor: Colors.orange),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
    reasonController.dispose();
  }

  Widget _buildVacationCard(Vacation vacation) {
    final user = ref.read(authProvider);
    final canApprove = user != null && (user.hasPermission(Permission.manageAttendance));
    final statusColor = _getStatusColor(vacation.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _getVacationTypeText(vacation.vacationType),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    _getStatusText(vacation.status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                _buildInfoColumn(
                  'من',
                  DateFormat('yyyy/MM/dd').format(vacation.startDate),
                ),
                const Spacer(),
                _buildInfoColumn(
                  'إلى',
                  DateFormat('yyyy/MM/dd').format(vacation.endDate),
                ),
                const Spacer(),
                _buildInfoColumn('المدة', '${vacation.totalDays} يوم'),
              ],
            ),
            if (vacation.reason != null && vacation.reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'السبب: ${vacation.reason}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ),
            ],
            if (vacation.status == 'pending' && canApprove) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _approveVacation(vacation),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('قبول'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _rejectVacation(vacation),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('رفض'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      case 'pending':
        return 'قيد الانتظار';
      default:
        return status;
    }
  }

  String _getVacationTypeText(String type) {
    switch (type) {
      case 'annual':
        return 'إجازة سنوية';
      case 'sick':
        return 'إجازة مرضية';
      case 'unpaid':
        return 'إجازة بدون مرتب';
      case 'emergency':
        return 'إجازة عارضة';
      default:
        return type;
    }
  }

  void _requestVacation() {
    // Show request vacation dialog (implementation omitted for brevity, but needed for full flow)
    // For now, we'll just show a snackbar or a simple dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب إجازة جديد'),
        content: const Text(
          'هذه الميزة ستمكن من اختيار التواريخ والنوع والسبب.',
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
