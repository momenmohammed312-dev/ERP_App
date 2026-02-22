import 'package:flutter/material.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/database/database_singleton.dart';
import 'package:intl/intl.dart';

class VacationsPage extends StatefulWidget {
  final Staff staff;

  const VacationsPage({super.key, required this.staff});

  @override
  State<VacationsPage> createState() => _VacationsPageState();
}

class _VacationsPageState extends State<VacationsPage> {
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
    final db = await DatabaseSingleton.getInstance();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في تحميل سجل الإجازات: $e')));
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

  Widget _buildVacationCard(Vacation vacation) {
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
