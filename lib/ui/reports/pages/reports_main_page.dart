import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../core/database/app_database.dart';
import '../widgets/reports_shell.dart';
import '../widgets/filter_panel.dart';
import '../widgets/results_table.dart';
import '../widgets/summary_panel.dart';
import '../providers/reports_provider.dart';

class ReportsMainPage extends ConsumerStatefulWidget {
  final AppDatabase db;

  const ReportsMainPage({super.key, required this.db});

  @override
  ConsumerState<ReportsMainPage> createState() => _ReportsMainPageState();
}

class _ReportsMainPageState extends ConsumerState<ReportsMainPage> {
  String _selectedReportType = 'sales';
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _reportTypes = [
    {
      'id': 'sales',
      'title': 'تقارير المبيعات',
      'icon': Icons.shopping_cart,
      'description': 'عرض تقارير المبيعات اليومية والشهرية',
    },
    {
      'id': 'customers',
      'title': 'تقارير العملاء',
      'icon': Icons.people,
      'description': 'عرض تقارير العملاء وحساباتهم',
    },
    {
      'id': 'suppliers',
      'title': 'تقارير الموردين',
      'icon': Icons.business,
      'description': 'عرض تقارير الموردين وحساباتهم',
    },
    {
      'id': 'products',
      'title': 'تقارير المنتجات',
      'icon': Icons.inventory,
      'description': 'عرض تقارير المنتجات والمخزون',
    },
    {
      'id': 'financial',
      'title': 'تقارير مالية',
      'icon': Icons.account_balance,
      'description': 'عرض التقارير المالية والدفعات',
    },
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReportsShell(
      child: Scaffold(
        body: Row(
          children: [
            // Sidebar with report types
            Container(
              width: 300,
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.assessment, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'نوع التقرير',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Report types list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _reportTypes.length,
                      itemBuilder: (context, index) {
                        final reportType = _reportTypes[index];
                        final isSelected =
                            _selectedReportType == reportType['id'];

                        return Card(
                          elevation: isSelected ? 4 : 1,
                          color: isSelected
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1)
                              : null,
                          child: ListTile(
                            leading: Icon(
                              reportType['icon'] as IconData,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                            ),
                            title: Text(
                              reportType['title'] as String,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              reportType['description'] as String,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: () {
                              setState(() {
                                _selectedReportType =
                                    reportType['id'] as String;
                              });
                              // Load data for selected report type
                              ref
                                  .read(reportsProvider.notifier)
                                  .loadReportData(
                                    reportType: _selectedReportType,
                                    db: widget.db,
                                  );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Main content area
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  // Filter panel
                  FilterPanel(
                    reportType: _selectedReportType,
                    onFilterChanged: (filters) {
                      ref.read(reportsProvider.notifier).applyFilters(filters);
                    },
                  ),

                  // Results area
                  Expanded(
                    child: Consumer(
                      builder: (context, ref, child) {
                        final reportsState = ref.watch(reportsProvider);

                        return reportsState.when(
                          loading: () => const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('جاري تحميل البيانات...'),
                              ],
                            ),
                          ),
                          error: (error, stack) => Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'حدث خطأ أثناء تحميل البيانات',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  error.toString(),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    ref
                                        .read(reportsProvider.notifier)
                                        .loadReportData(
                                          reportType: _selectedReportType,
                                          db: widget.db,
                                        );
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          ),
                          data: () => reportsState.data.isEmpty
                              ? _buildEmptyState()
                              : Column(
                                  children: [
                                    // Results table
                                    Expanded(
                                      flex: 3,
                                      child: ResultsTable(
                                        data: reportsState.data,
                                        reportType: _selectedReportType,
                                      ),
                                    ),

                                    // Summary panel
                                    Expanded(
                                      flex: 1,
                                      child: SummaryPanel(
                                        data: reportsState.data,
                                        reportType: _selectedReportType,
                                        onExport: () =>
                                            _exportData(reportsState.data),
                                        onPrint: () =>
                                            _printData(reportsState.data),
                                      ),
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد بيانات حسب الفلتر الحالي',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'جرب تغيير الفلاتر أو اختيار تقرير آخر',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  void _exportData(List<Map<String, dynamic>> data) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export not supported on web platform')),
      );
      return;
    }
    try {
      // Get the directory for saving files
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          '${_selectedReportType}_report_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File('${directory.path}/$fileName');

      // Convert data to CSV format
      final csvData = _convertToCSV(data);

      // Write to file
      await file.writeAsString(csvData);

      final messengerContext = context;
      if (messengerContext.mounted) {
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          SnackBar(
            content: Text('تم تصدير البيانات إلى $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      final messengerContext = context;
      if (messengerContext.mounted) {
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _convertToCSV(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return '';

    // Get headers from first item
    final headers = data.first.keys.toList();

    // Create CSV content
    final csvRows = <String>[];

    // Add headers
    csvRows.add(headers.join(','));

    // Add data rows
    for (final item in data) {
      final row = headers.map((header) {
        final value = item[header]?.toString() ?? '';
        // Escape commas and quotes in values
        return value.contains(',') || value.contains('"')
            ? '"${value.replaceAll('"', '""')}"'
            : value;
      }).toList();
      csvRows.add(row.join(','));
    }

    return csvRows.join('\n');
  }

  void _printData(List<Map<String, dynamic>> data) async {
    try {
      // Get the directory for saving files
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          '${_selectedReportType}_report_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File('${directory.path}/$fileName');

      // Create formatted text content for printing
      final printContent = _convertToPrintFormat(data);

      // Write to file
      await file.writeAsString(printContent);

      final messengerContext = context;
      if (messengerContext.mounted) {
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          SnackBar(
            content: Text('تم حفظ البيانات للطباعة في $fileName'),
            backgroundColor: Colors.green,
          ),
        );

        // Optionally open the file for printing
        // Note: In a real app, you might want to use a printing package
        // or integrate with system print dialog
      }
    } catch (e) {
      final messengerContext = context;
      if (messengerContext.mounted) {
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ البيانات للطباعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _convertToPrintFormat(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return 'لا توجد بيانات للطباعة';

    final buffer = StringBuffer();

    // Add header
    buffer.writeln('=== تقرير $_selectedReportType ===');
    buffer.writeln('التاريخ: ${DateTime.now().toString().split(' ')[0]}');
    buffer.writeln('================================');
    buffer.writeln();

    // Add headers based on report type
    switch (_selectedReportType) {
      case 'sales':
        buffer.writeln('رقم الفاتورة|العميل|التاريخ|المبلغ|الحالة|طريقة الدفع');
        break;
      case 'customers':
        buffer.writeln('اسم العميل|رقم الهاتف|الرصيد|عدد الفواتير|الحالة');
        break;
      case 'suppliers':
        buffer.writeln('اسم المورد|رقم الهاتف|الرصيد|عدد المعاملات|الحالة');
        break;
      case 'products':
        buffer.writeln(
          'اسم المنتج|الكمية|السعر|القيمة الإجمالية|الكمية المباعة|المتبقي',
        );
        break;
      case 'financial':
        buffer.writeln('التاريخ|النوع|الوصف|المبلغ|المرجع');
        break;
      default:
        buffer.writeln('البيانات');
    }

    buffer.writeln('================================');
    buffer.writeln();

    // Add data rows
    for (final item in data) {
      switch (_selectedReportType) {
        case 'sales':
          buffer.writeln(
            '${item['invoiceNumber'] ?? ''}|${item['customerName'] ?? ''}|${item['date'] ?? ''}|${item['totalAmount'] ?? 0}|${item['status'] ?? ''}|${item['paymentMethod'] ?? ''}',
          );
          break;
        case 'customers':
          buffer.writeln(
            '${item['name'] ?? ''}|${item['contact'] ?? ''}|${item['balance'] ?? 0}|${item['totalInvoices'] ?? 0}|${item['status'] ?? ''}',
          );
          break;
        case 'suppliers':
          buffer.writeln(
            '${item['name'] ?? ''}|${item['contact'] ?? ''}|${item['balance'] ?? 0}|${item['totalPurchases'] ?? 0}|${item['status'] ?? ''}',
          );
          break;
        case 'products':
          buffer.writeln(
            '${item['name'] ?? ''}|${item['quantity'] ?? 0}|${item['price'] ?? 0}|${item['totalValue'] ?? 0}|${item['totalSold'] ?? 0}|${item['remaining'] ?? 0}',
          );
          break;
        case 'financial':
          buffer.writeln(
            '${item['date'] ?? ''}|${item['type'] ?? ''}|${item['description'] ?? ''}|${item['amount'] ?? 0}|${item['reference'] ?? ''}',
          );
          break;
        default:
          buffer.writeln(item.toString());
      }
    }

    buffer.writeln();
    buffer.writeln('================================');
    buffer.writeln('تم الطباعة في: ${DateTime.now().toString()}');

    return buffer.toString();
  }
}
