import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class StaffExpensesReport extends StatefulWidget {
  final AppDatabase db;

  const StaffExpensesReport({super.key, required this.db});

  @override
  State<StaffExpensesReport> createState() => _StaffExpensesReportState();
}

class _StaffExpensesReportState extends State<StaffExpensesReport> {
  bool _isLoading = false;
  List<StaffAdvance> _advances = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Basic implementation: fetch all advances for now
      final advances = await widget.db.select(widget.db.staffAdvances).get();
      setState(() {
        _advances = advances;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تقرير مصروفات الموظفين')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _advances.length,
                    itemBuilder: (context, index) {
                      final advance = _advances[index];
                      return ListTile(
                        title: Text('سلفة - موظف ID: ${advance.staffId}'),
                        subtitle: Text(
                          DateFormat('yyyy/MM/dd').format(advance.requestDate),
                        ),
                        trailing: Text(
                          advance.amount.toStringAsFixed(2),
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
