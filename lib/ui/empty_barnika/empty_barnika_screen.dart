import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/empty_barnika_tracking_table.dart';

/// شاشة تتبع وإرجاع البرانيك الفاضية للعملاء.
///
/// مبنية على جدول `EmptyBarnikaTracking` (الجدول المعتمد).
/// الظهور مقيد بـ [AppFeatures.hasEmptyContainerTracking] (vegetable flavor).
class EmptyBarnikaScreen extends StatefulWidget {
  final AppDatabase db;

  const EmptyBarnikaScreen({super.key, required this.db});

  @override
  State<EmptyBarnikaScreen> createState() => _EmptyBarnikaScreenState();
}

class _EmptyBarnikaScreenState extends State<EmptyBarnikaScreen> {
  Map<String, Customer> _customerMap = {};
  bool _loadingCustomers = true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await widget.db.customerDao.getAllActiveCustomers();
      setState(() {
        _customerMap = {for (final c in customers) c.id: c};
        _loadingCustomers = false;
      });
    } catch (_) {
      setState(() => _loadingCustomers = false);
    }
  }

  String _customerName(String customerId) =>
      _customerMap[customerId]?.name ?? 'عميل #$customerId';

  @override
  Widget build(BuildContext context) {
    if (!AppFeatures.hasEmptyContainerTracking) {
      return const Scaffold(
        body: Center(child: Text('هذه الميزة غير مفعلة في النسخة الحالية')),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('البرانيك المستحقة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCustomers,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: StreamBuilder<List<EmptyBarnikaTrackingData>>(
        stream: widget.db.emptyBarnikaTrackingDao.watchAllOutstanding(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('حدث خطأ في تحميل البيانات: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData || _loadingCustomers) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data!;

          // تجميع السجلات المستحقة لكل عميل
          final grouped = <String, List<EmptyBarnikaTrackingData>>{};
          for (final r in records) {
            grouped.putIfAbsent(r.customerId, () => []).add(r);
          }

          if (grouped.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_return_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const Gap(16),
                  Text(
                    'لا توجد برانيك مستحقة حالياً',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          final customers = grouped.keys.toList()
            ..sort((a, b) => _customerName(a).compareTo(_customerName(b)));

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: customers.length,
            itemBuilder: (context, index) {
              final customerId = customers[index];
              final customerRecords = grouped[customerId]!;
              final totalOutstanding = customerRecords.fold<int>(
                0,
                (sum, r) => sum + (r.quantityOut - r.quantityReturned),
              );

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EmptyBarnikaCustomerScreen(
                          db: widget.db,
                          customerId: customerId,
                          customerName: _customerName(customerId),
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(
                            Icons.person,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _customerName(customerId),
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${customerRecords.length} عملية مستحقة',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade700,
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
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: Text(
                            'متبقي: $totalOutstanding',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Gap(8),
                        const Icon(Icons.chevron_left),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// تفاصيل برانيك عميل واحد: سجلات الخروج الفردية مع حالة كل سجل
/// وزرار "تسجيل رجوع" لكل سجل.
class EmptyBarnikaCustomerScreen extends StatefulWidget {
  final AppDatabase db;
  final String customerId;
  final String customerName;

  const EmptyBarnikaCustomerScreen({
    super.key,
    required this.db,
    required this.customerId,
    required this.customerName,
  });

  @override
  State<EmptyBarnikaCustomerScreen> createState() =>
      _EmptyBarnikaCustomerScreenState();
}

class _EmptyBarnikaCustomerScreenState extends State<EmptyBarnikaCustomerScreen> {
  Future<void> _recordReturn(EmptyBarnikaTrackingData record) async {
    final remaining = record.quantityOut - record.quantityReturned;
    if (remaining <= 0) return;

    final controller = TextEditingController();
    final confirmed = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل رجوع برانيك'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'عدد البرانيك المراد رجوعها (المتبقي: $remaining)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Gap(12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'الكمية المرجوعة',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(controller.text.trim());
              if (qty == null || qty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('أدخل كمية صحيحة أكبر من صفر'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (qty > remaining) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('الكمية أكبر من المتبقي ($remaining)'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(qty);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirmed == null || !mounted) return;

    try {
      await widget.db.emptyBarnikaTrackingDao.recordReturn(
        id: record.id,
        quantityReturned: confirmed,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل الرجوع بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تسجيل الرجوع: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case EmptyBarnikaStatus.partial:
        return Colors.blue;
      case EmptyBarnikaStatus.returned:
        return Colors.green;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case EmptyBarnikaStatus.partial:
        return 'جزئي';
      case EmptyBarnikaStatus.returned:
        return 'مرجع';
      default:
        return 'مستحق';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('برانيك — ${widget.customerName}'),
      ),
      body: StreamBuilder<List<EmptyBarnikaTrackingData>>(
        stream: widget.db.emptyBarnikaTrackingDao
            .watchOutstandingByCustomer(widget.customerId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('حدث خطأ في تحميل البيانات: ${snapshot.error}'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data!;

          if (records.isEmpty) {
            return Center(
              child: Text(
                'لا توجد برانيك مستحقة لهذا العميل',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final r = records[index];
              final remaining = r.quantityOut - r.quantityReturned;
              final statusColor = _statusColor(r.status);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              _statusLabel(r.status),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            DateFormat('yyyy/MM/dd HH:mm').format(r.dateOut),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _RecordStat(label: 'خارج', value: r.quantityOut),
                          _RecordStat(
                            label: 'رجع',
                            value: r.quantityReturned,
                          ),
                          _RecordStat(
                            label: 'متبقي',
                            value: remaining,
                            valueColor: remaining > 0
                                ? Colors.orange
                                : Colors.green,
                          ),
                        ],
                      ),
                      if (remaining > 0) ...[
                        const Gap(12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _recordReturn(r),
                            icon: const Icon(Icons.assignment_return),
                            label: const Text('تسجيل رجوع'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RecordStat extends StatelessWidget {
  final String label;
  final int value;
  final Color valueColor;

  const _RecordStat({
    required this.label,
    required this.value,
    this.valueColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const Gap(4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
