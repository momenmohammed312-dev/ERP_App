import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/customer/customer_statement_screen.dart';
import 'package:pos_offline_desktop/ui/supplier/supplier_statement_screen.dart';

class ConsolidatedAccountsScreen extends ConsumerStatefulWidget {
  const ConsolidatedAccountsScreen({super.key});

  @override
  ConsumerState<ConsolidatedAccountsScreen> createState() =>
      _ConsolidatedAccountsScreenState();
}

class _ConsolidatedAccountsScreenState
    extends ConsumerState<ConsolidatedAccountsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showOnlyWithBalance = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final customers = await db.ledgerDao.getAllCustomerBalances();
      final suppliers = await db.ledgerDao.getAllSupplierBalances();

      setState(() {
        _customers = customers;
        _suppliers = suppliers;
        _isLoading = false;
      });
    } catch (e, st) {
      AppLogger.e('Failed to load balances', e, st);
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('أرصدة الحسابات الموحدة'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'العملاء (لينا)', icon: Icon(Icons.people_alt)),
            Tab(text: 'الموردين (علينا)', icon: Icon(Icons.business_center)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث البيانات',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          _buildFilters(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBalanceList(_customers, 'Customer'),
                      _buildBalanceList(_suppliers, 'Supplier'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    double totalReceivables = 0.0;
    double totalPayables = 0.0;

    for (var c in _customers) {
      final b = (c['balance'] as num?)?.toDouble() ?? 0.0;
      if (b > 0) totalReceivables += b;
    }
    for (var s in _suppliers) {
      final b = (s['balance'] as num?)?.toDouble() ?? 0.0;
      if (b > 0) totalPayables += b;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          _buildSummaryCard(
            'إجمالي ديون العملاء (لنا)',
            totalReceivables,
            Colors.green,
            Icons.trending_up,
          ),
          const Gap(16),
          _buildSummaryCard(
            'إجمالي ديون الموردين (علينا)',
            totalPayables,
            Colors.red,
            Icons.trending_down,
          ),
          const Gap(16),
          _buildSummaryCard(
            'صافي المركز المالي',
            totalReceivables - totalPayables,
            Colors.blue,
            Icons.account_balance,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    double amount,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color),
              ),
              const Gap(16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Gap(4),
                  Text(
                    '${amount.toStringAsFixed(2)} ج.م',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'بحث بالاسم أو رقم الهاتف...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) =>
                  setState(() => _searchQuery = val.toLowerCase()),
            ),
          ),
          const Gap(16),
          FilterChip(
            label: const Text('أرصدة غير صفرية فقط'),
            selected: _showOnlyWithBalance,
            onSelected: (val) => setState(() => _showOnlyWithBalance = val),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceList(List<Map<String, dynamic>> items, String type) {
    final filtered = items.where((item) {
      final name = (item['name'] as String? ?? '').toLowerCase();
      final phone = (item['phone'] as String? ?? '').toLowerCase();
      final balance = (item['balance'] as num?)?.toDouble() ?? 0.0;

      final matchesSearch =
          name.contains(_searchQuery) || phone.contains(_searchQuery);
      final matchesBalance = !_showOnlyWithBalance || balance.abs() > 0.01;

      return matchesSearch && matchesBalance;
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('لا توجد بيانات تطابق البحث'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final item = filtered[index];
        final balance = (item['balance'] as num?)?.toDouble() ?? 0.0;
        final color = balance > 0
            ? (type == 'Customer' ? Colors.green : Colors.red)
            : (balance < 0
                  ? (type == 'Customer' ? Colors.red : Colors.green)
                  : Colors.grey);

        return ListTile(
          leading: CircleAvatar(child: Text(item['name'][0])),
          title: Text(
            item['name'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(item['phone'] ?? 'بدون هاتف'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${balance.abs().toStringAsFixed(2)} ج.م',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                balance > 0
                    ? (type == 'Customer' ? 'لنا' : 'علينا')
                    : (balance < 0
                          ? (type == 'Customer' ? 'علينا' : 'لنا')
                          : 'متعادل'),
                style: TextStyle(fontSize: 10, color: color),
              ),
            ],
          ),
          onTap: () {
            if (type == 'Customer') {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CustomerStatementScreen(
                    customer: Customer(
                      id: item['id'] as String,
                      name: item['name'] as String,
                      phone: item['phone'] as String?,
                      address: null,
                      gstinNumber: null,
                      email: null,
                      openingBalance: (item['openingBalance'] as num?)?.toDouble() ?? 0.0,
                      totalDebt: (item['totalDebt'] as num?)?.toDouble() ?? 0.0,
                      totalPaid: (item['totalPaid'] as num?)?.toDouble() ?? 0.0,
                      createdAt: null,
                      updatedAt: null,
                      notes: null,
                      isActive: true,
                      status: 'Active',
                    ),
                  ),
                ),
              );
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SupplierStatementScreen(
                    supplier: Supplier(
                      id: item['id'] as String,
                      name: item['name'] as String,
                      phone: item['phone'] as String?,
                      address: null,
                      openingBalance: (item['openingBalance'] as num?)?.toDouble() ?? 0.0,
                      createdAt: DateTime.now(),
                      status: 'Active',
                    ),
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}
