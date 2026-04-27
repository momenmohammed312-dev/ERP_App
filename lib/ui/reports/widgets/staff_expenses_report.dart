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
  // FIX: staffId is TextColumn (String) not int — was Map<int, String>
  Map<String, String> _staffMap = {};
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final advances = await widget.db.select(widget.db.staffAdvances).get();
      final staffList = await widget.db.select(widget.db.staffTable).get();
      // FIX: build Map<String,String> directly — no broken .cast<int,String>()
      final staffMap = <String, String>{
        for (final s in staffList) s.staffId: s.name,
      };
      setState(() {
        _advances = advances;
        _staffMap = staffMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'خطأ في تحميل البيانات: $e';
      });
    }
  }

  double get _totalAmount =>
      _advances.fold(0.0, (sum, a) => sum + a.amount);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('تقرير مصروفات الموظفين'),
        backgroundColor: bgColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      Text(_errorMessage!,
                          style: TextStyle(color: textColor),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary card
                    if (_advances.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Card(
                          color: cardBg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.payments,
                                      color: Colors.red, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('إجمالي السلف',
                                          style: TextStyle(
                                              color: Colors.red.shade400,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_totalAmount.toStringAsFixed(2)} ج.م',
                                        style: TextStyle(
                                            color: textColor,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('عدد السلف',
                                        style: TextStyle(
                                            color:
                                                textColor.withValues(alpha: 0.6),
                                            fontSize: 12)),
                                    Text('${_advances.length}',
                                        style: TextStyle(
                                            color: textColor,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Advances List
                    Expanded(
                      child: _advances.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inbox_outlined,
                                      size: 64,
                                      color:
                                          textColor.withValues(alpha: 0.3)),
                                  const SizedBox(height: 16),
                                  Text('لا توجد سلف مسجلة',
                                      style: TextStyle(
                                          color:
                                              textColor.withValues(alpha: 0.6),
                                          fontSize: 16)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              itemCount: _advances.length,
                              itemBuilder: (context, index) {
                                final advance = _advances[index];
                                // FIX: lookup by String key now
                                final staffName =
                                    _staffMap[advance.staffId] ?? 'غير معروف';
                                final statusColor =
                                    advance.status == 'paid'
                                        ? Colors.green
                                        : advance.status == 'approved'
                                            ? Colors.blue
                                            : advance.status == 'rejected'
                                                ? Colors.red
                                                : Colors.orange;
                                final statusText =
                                    advance.status == 'paid'
                                        ? 'مدفوع'
                                        : advance.status == 'approved'
                                            ? 'موافق عليه'
                                            : advance.status == 'rejected'
                                                ? 'مرفوض'
                                                : 'معلق';

                                return Card(
                                  color: cardBg,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.blueGrey
                                          .withValues(alpha: 0.2),
                                      child: Text(
                                        staffName.isNotEmpty
                                            ? staffName[0]
                                            : '?',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      'سلفة - $staffName',
                                      style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(
                                          DateFormat('yyyy/MM/dd')
                                              .format(advance.requestDate),
                                          style: TextStyle(
                                              color: textColor
                                                  .withValues(alpha: 0.6),
                                              fontSize: 12),
                                        ),
                                        if (advance.reason != null &&
                                            advance.reason!.isNotEmpty)
                                          Text(
                                            advance.reason!,
                                            style: TextStyle(
                                                color: textColor
                                                    .withValues(alpha: 0.5),
                                                fontSize: 11),
                                          ),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${advance.amount.toStringAsFixed(2)} ج.م',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: statusColor
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            statusText,
                                            style: TextStyle(
                                                color: statusColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
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
