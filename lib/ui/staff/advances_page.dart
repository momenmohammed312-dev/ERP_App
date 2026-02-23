import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/utils/currency_helper.dart';
import 'package:intl/intl.dart';

class AdvancesPage extends ConsumerStatefulWidget {
  final Staff staff;

  const AdvancesPage({super.key, required this.staff});

  @override
  ConsumerState<AdvancesPage> createState() => _AdvancesPageState();
}

class _AdvancesPageState extends ConsumerState<AdvancesPage> {
  late StaffManagementDao _dao;
  List<StaffAdvance> _advances = [];
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
      final advances = await _dao.getAdvancesByStaff(widget.staff.staffId);
      setState(() {
        _advances = advances.reversed.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في تحميل سجل السلف: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _advances.isEmpty
          ? _buildEmptyState()
          : _buildAdvancesList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _requestAdvance,
        backgroundColor: Colors.teal,
        tooltip: 'طلب سلفة',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.money_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد سلف لهذا الموظف',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _advances.length,
      itemBuilder: (context, index) {
        final advance = _advances[index];
        return _buildAdvanceCard(advance);
      },
    );
  }

  Widget _buildAdvanceCard(StaffAdvance advance) {
    final statusColor = _getStatusColor(advance.status);

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
                  CurrencyHelper.formatCurrency(advance.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.teal[700],
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
                    _getStatusText(advance.status),
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
                  'تاريخ الطلب',
                  DateFormat('yyyy/MM/dd').format(advance.requestDate),
                ),
                const Spacer(),
                if (advance.installmentMonths != null)
                  _buildInfoColumn(
                    'الأقساط',
                    '${advance.installmentMonths} شهر',
                  ),
                const Spacer(),
                if (advance.monthlyDeduction != null)
                  _buildInfoColumn(
                    'القسط الشهري',
                    CurrencyHelper.formatCurrency(advance.monthlyDeduction!),
                  ),
              ],
            ),
            if (advance.reason != null && advance.reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'السبب: ${advance.reason}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ),
            ],
            if (advance.paymentDate != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'تاريخ الصرف: ${DateFormat('yyyy/MM/dd').format(advance.paymentDate!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
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
      case 'paid':
        return Colors.blue;
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
      case 'paid':
        return 'تم الصرف';
      default:
        return status;
    }
  }

  void _requestAdvance() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب سلفة جديد'),
        content: const Text(
          'هذه الميزة ستمكن من تحديد المبلغ وعدد الأقساط والسبب.',
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
