import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/ui/supplier/widgets/supplier_summary_item.dart';
import 'package:pos_offline_desktop/ui/supplier/widgets/supplier_form_dialog.dart';

class SupplierPage extends StatefulWidget {
  final AppDatabase db;

  const SupplierPage({super.key, required this.db});

  @override
  State<SupplierPage> createState() => _SupplierPageState();
}

class _SupplierPageState extends State<SupplierPage> {
  List<Supplier> suppliers = [];
  List<Supplier> filteredSuppliers = [];
  Map<String, double> supplierBalances = {};
  final TextEditingController _searchController = TextEditingController();
  final ExportService _exportService = ExportService();
  bool _isLoading = true;
  String? _error;
  // FIX: added missing summary metrics
  double _paidThisMonth = 0.0;
  int _activeSuppliers = 0;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final allSuppliers = await widget.db.supplierDao.getAllSuppliers();
      if (mounted) {
        setState(() {
          suppliers = allSuppliers;
          filteredSuppliers = allSuppliers;
          _error = null;
        });
        await _loadSupplierBalances();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'فشل تحميل بيانات الموردين: $e');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في تحميل الموردين: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSupplierBalances() async {
    final balances = <String, double>{};
    int activeCount = 0;
    for (final supplier in suppliers) {
      try {
        final balance = await widget.db.ledgerDao.getRunningBalance(
          'Supplier',
          supplier.id,
        );
        balances[supplier.id] = balance;
      } catch (e) {
        balances[supplier.id] = supplier.openingBalance;
      }
      if (supplier.status == 'Active' ||
          supplier.status == 'active' ||
          supplier.status == 'نشط') {
        activeCount++;
      }
    }

    // FIX: calculate paid this month from purchases table
    double paidThisMonth = 0.0;
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final rows = await widget.db.customSelect(
        '''
        SELECT COALESCE(SUM(paid_amount), 0.0) AS total
        FROM purchases
        WHERE created_at >= ?
          AND (is_deleted = 0 OR is_deleted IS NULL)
        ''',
        variables: [Variable.withDateTime(startOfMonth)],
      ).getSingle();
      paidThisMonth = (rows.data['total'] as num?)?.toDouble() ?? 0.0;
    } catch (_) {}

    if (mounted) {
      setState(() {
        supplierBalances = balances;
        _paidThisMonth = paidThisMonth;
        _activeSuppliers = activeCount;
      });
    }
  }

  void _searchSuppliers(String query) {
    if (query.isEmpty) {
      setState(() => filteredSuppliers = List.from(suppliers));
      return;
    }

    final lowerQuery = query.toLowerCase();
    final filtered = suppliers.where((supplier) {
      return supplier.name.toLowerCase().contains(lowerQuery) ||
          (supplier.phone ?? '').toLowerCase().contains(lowerQuery) ||
          (supplier.address ?? '').toLowerCase().contains(lowerQuery);
    }).toList();

    setState(() => filteredSuppliers = filtered);
  }

  Future<void> _showAddEditSupplierDialog({Supplier? supplier}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SupplierFormDialog(
        database: widget.db,
        supplier: supplier,
      ),
    );

    if (result == true) {
      await _loadSuppliers();
    }
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المورد ${supplier.name}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.db.supplierDao.deleteSupplier(supplier.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم حذف المورد بنجاح')));
          _loadSuppliers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('فشل حذف المورد: $e')));
        }
      }
    }
  }

  Future<void> _exportToExcel() async {
    try {
      final headers = ['الاسم', 'الهاتف', 'العنوان', 'الرصيد', 'الحالة'];
      final columns = ['name', 'phone', 'address', 'balance', 'status'];

      final data = suppliers.map((supplier) {
        return {
          'name': supplier.name,
          'phone': supplier.phone ?? '',
          'address': supplier.address ?? '',
          'balance':
              supplierBalances[supplier.id]?.toStringAsFixed(2) ?? '0.00',
          'status': supplier.status == 'Active' ? 'نشط' : 'غير نشط',
        };
      }).toList();

      await _exportService.exportToExcel(
        title: 'كشف الموردين',
        headers: headers,
        columns: columns,
        data: data,
        fileName: 'suppliers_export',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تصدير البيانات بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الموردين'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditSupplierDialog(),
            tooltip: 'إضافة مورد جديد',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportToExcel,
            tooltip: 'تصدير إلى إكسل',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSuppliers,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadSuppliers,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن مورد...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _searchSuppliers('');
                              },
                            )
                          : null,
                    ),
                    onChanged: _searchSuppliers,
                  ),
                ),

                // Summary Cards
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Text(
                        'ملخص الموردين',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SupplierSummaryItem(
                          title: 'إجمالي الموردين',
                          value: suppliers.length.toString(),
                          icon: Icons.people,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SupplierSummaryItem(
                          title: 'الديون المستحقة',
                          value:
                              '${supplierBalances.values.where((b) => b > 0).fold(0.0, (sum, b) => sum + b).toStringAsFixed(2)} ج.م',
                          icon: Icons.money_off,
                          color: Colors.red,
                        ),
                      ),
                      // FIX: added missing cards
                      const SizedBox(width: 16),
                      Expanded(
                        child: SupplierSummaryItem(
                          title: 'المدفوع في الشهر',
                          value: '${_paidThisMonth.toStringAsFixed(2)} ج.م',
                          icon: Icons.payments,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SupplierSummaryItem(
                          title: 'موردون نشطون',
                          value: _activeSuppliers.toString(),
                          icon: Icons.check_circle,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                ),

                // Supplier List
                Expanded(
                  child: filteredSuppliers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.business,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'لا توجد موردين ${_searchController.text.isNotEmpty ? 'مطابقين للبحث' : 'مسجلين'}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              if (_searchController.text.isEmpty)
                                TextButton(
                                  onPressed: () => _showAddEditSupplierDialog(),
                                  child: const Text('إضافة مورد جديد'),
                                ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            border: TableBorder.all(
                              color: Colors.grey.shade300,
                            ),
                            columnSpacing: 24,
                            headingRowColor: WidgetStateColor.resolveWith(
                              (states) => Colors.grey.shade100,
                            ),
                            columns: const [
                              DataColumn(label: Text('م')),
                              DataColumn(label: Text('اسم المورد')),
                              DataColumn(label: Text('الهاتف')),
                              DataColumn(label: Text('العنوان')),
                              DataColumn(label: Text('الرصيد')),
                              DataColumn(label: Text('الحالة')),
                              DataColumn(label: Text('الإجراءات')),
                            ],
                            rows: filteredSuppliers.map((supplier) {
                              final balance =
                                  supplierBalances[supplier.id] ?? 0.0;
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text('${suppliers.indexOf(supplier) + 1}'),
                                  ),
                                  DataCell(Text(supplier.name)),
                                  DataCell(Text(supplier.phone ?? '')),
                                  DataCell(Text(supplier.address ?? '')),
                                  DataCell(
                                    Text(
                                      '${balance.toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                        color: balance >= 0
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      supplier.status == 'Active'
                                          ? 'نشط'
                                          : 'غير نشط',
                                      style: TextStyle(
                                        color: supplier.status == 'Active'
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () =>
                                              _showAddEditSupplierDialog(
                                                supplier: supplier,
                                              ),
                                          tooltip: 'تعديل',
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () =>
                                              _deleteSupplier(supplier),
                                          tooltip: 'حذف',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
