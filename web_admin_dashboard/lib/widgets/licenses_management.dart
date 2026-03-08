import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/license_model.dart';
import '../models/client_model.dart';
import '../services/data_service.dart';
import '../utils/constants.dart';

/// Licenses Management Widget - إدارة التراخيص
class LicensesManagement extends StatefulWidget {
  const LicensesManagement({super.key});

  @override
  State<LicensesManagement> createState() => _LicensesManagementState();
}

class _LicensesManagementState extends State<LicensesManagement> {
  final DataService _dataService = DataService();
  final TextEditingController _searchController = TextEditingController();
  List<LicenseRecord> _filteredLicenses = [];
  String _statusFilter = 'all';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _dataService.addListener(_onDataChanged);
    _loadData();
  }

  void _onDataChanged() {
    if (!mounted) return;
    _applyFilters();
    setState(() {});
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _dataService.init();
    _applyFilters();
    setState(() => _isLoading = false);
  }

  void _applyFilters() {
    var licenses = _dataService.getLicenses();

    // Apply status filter
    if (_statusFilter != 'all') {
      licenses = licenses.where((l) {
        switch (_statusFilter) {
          case 'active':
            return l.status == LicenseStatus.active && !l.isExpired;
          case 'expired':
            return l.isExpired || l.status == LicenseStatus.expired;
          case 'trial':
            return l.status == LicenseStatus.trial;
          case 'revoked':
            return l.status == LicenseStatus.revoked;
          case 'expiring':
            return l.isExpiringSoon;
          case 'inactive':
            return l.status == LicenseStatus.inactive;
          case 'suspended':
            return l.status == LicenseStatus.suspended;
          default:
            return true;
        }
      }).toList();
    }

    // Apply search filter
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      licenses = licenses
          .where((l) =>
              l.clientName.toLowerCase().contains(query) ||
              l.licenseKey.toLowerCase().contains(query))
          .toList();
    }

    setState(() {
      _filteredLicenses = licenses;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;
          if (isWide) {
            // Desktop: Column + Expanded grid stays scrollable inside
            return Container(
              color: AppColors.backgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildStatsCards(),
                    const SizedBox(height: 24),
                    _buildFiltersRow(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _buildLicensesGrid(),
                    ),
                  ],
                ),
              ),
            );
          } else {
            // Mobile/Narrow: everything in one scroll — no Expanded
            return Container(
              color: AppColors.backgroundColor,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildStatsCards(),
                    const SizedBox(height: 16),
                    _buildFiltersRow(),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 500,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _buildLicensesGrid(),
                    ),
                  ],
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.licenses,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'إدارة تراخيص البرنامج وتتبع الاشتراكات',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _showPriceManagement,
              icon: const Icon(Icons.settings),
              label: const Text('إدارة الأسعار'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryColor,
                side: const BorderSide(color: AppColors.primaryColor),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _showAddLicenseDialog,
              icon: const Icon(Icons.key),
              label: const Text('توليد وعرض المفتاح'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    final expiringSoon = _dataService.getExpiringSoonLicenses().length;
    final expired = _dataService.getExpiredLicenses().length;

    final cards = <Widget>[
      _buildStatCard(
        'التراخيص النشطة',
        _dataService.activeLicensesCount.toString(),
        Icons.verified,
        AppColors.successColor,
      ),
      _buildStatCard(
        'التجريبية',
        _dataService.trialLicensesCount.toString(),
        Icons.hourglass_bottom,
        AppColors.warningColor,
      ),
      _buildStatCard(
        'ينتهي قريباً',
        expiringSoon.toString(),
        Icons.warning_amber,
        AppColors.warningColor,
      ),
      _buildStatCard(
        'منتهية',
        expired.toString(),
        Icons.cancel,
        AppColors.errorColor,
      ),
      _buildStatCard(
        'إجمالي الإيرادات',
        '${_dataService.totalRevenue.toInt()} ج',
        Icons.attach_money,
        AppColors.accentColor,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        if (isWide) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }

        final width = constraints.maxWidth;
        final crossAxisCount = width >= 600 ? 3 : 2;
        const spacing = 16.0;
        final cardWidth =
            (width - (spacing * (crossAxisCount - 1))) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    return Row(
      children: [
        // Search
        Expanded(
          flex: 2,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => _applyFilters(),
            decoration: InputDecoration(
              hintText: 'بحث بالاسم أو المفتاح...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Status Filter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _statusFilter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('الكل')),
                DropdownMenuItem(value: 'active', child: Text('نشط')),
                DropdownMenuItem(value: 'inactive', child: Text('غير مفعّل')),
                DropdownMenuItem(value: 'trial', child: Text('تجريبي')),
                DropdownMenuItem(value: 'suspended', child: Text('موقوف')),
                DropdownMenuItem(
                    value: 'expiring', child: Text('ينتهي قريباً')),
                DropdownMenuItem(value: 'expired', child: Text('منتهي')),
                DropdownMenuItem(value: 'revoked', child: Text('ملغي')),
              ],
              onChanged: (value) {
                setState(() {
                  _statusFilter = value!;
                  _applyFilters();
                });
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
        ),
      ],
    );
  }

  Widget _buildLicensesGrid() {
    if (_filteredLicenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.key_off, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              AppStrings.noLicenses,
              style: TextStyle(fontSize: 18, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            const Text(
              'قم بإضافة عميل وتوليد ترخيص له',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.4,
      ),
      itemCount: _filteredLicenses.length,
      itemBuilder: (context, index) =>
          _buildLicenseCard(_filteredLicenses[index]),
    );
  }

  Widget _buildLicenseCard(LicenseRecord license) {
    final statusColor = _getStatusColor(license);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: license.isExpiringSoon
              ? AppColors.warningColor.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getPackageColor(license.packageType),
                      radius: 18,
                      child: Text(
                        license.clientName.isNotEmpty
                            ? license.clientName[0]
                            : '?',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          license.clientName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          license.packageDisplayName,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
                _buildStatusBadge(license),
                IconButton(
                  icon: const Icon(Icons.key, size: 20),
                  color: AppColors.primaryColor,
                  tooltip: 'عرض المفتاح الكامل',
                  onPressed: () => _showFullKeyDialog(license),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Spacer(),
            // License Key
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          license.licenseKey.length > 40
                              ? '${license.licenseKey.substring(0, 40)}...'
                              : license.licenseKey,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: license.licenseKey));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم نسخ المفتاح'),
                              backgroundColor: AppColors.successColor,
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'نسخ المفتاح',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '🔗 طافٍ — يُربط عند التفعيل',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.successColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Info Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ينتهي: ${_formatDate(license.expiresAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: license.isExpiringSoon
                            ? AppColors.warningColor
                            : Colors.grey[600],
                        fontWeight: license.isExpiringSoon
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (license.isExpiringSoon)
                      Text(
                        'متبقي ${license.daysRemaining} يوم',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.warningColor,
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    // Warn button
                    if (license.status == LicenseStatus.active &&
                        license.warningCount < 3)
                      IconButton(
                        icon: const Icon(Icons.warning, size: 20),
                        color: Colors.orange,
                        tooltip: 'إرسال تحذير',
                        onPressed: () async {
                          await _dataService.sendWarning(license.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم إرسال التحذير'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                      ),
                    // Suspend button
                    if (license.status == LicenseStatus.active)
                      IconButton(
                        icon: const Icon(Icons.pause, size: 20),
                        color: Colors.deepOrange,
                        tooltip: 'إيقاف الترخيص',
                        onPressed: () => _confirmSuspend(license),
                      ),
                    // Reactivate button
                    if (license.status == LicenseStatus.suspended)
                      IconButton(
                        icon: const Icon(Icons.play_arrow, size: 20),
                        color: Colors.green,
                        tooltip: 'إعادة تفعيل الترخيص',
                        onPressed: () async {
                          await _dataService.reactivateLicense(license.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم إعادة تفعيل الترخيص'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                      ),
                    if (license.status != LicenseStatus.revoked &&
                        !license.isExpired)
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        color: AppColors.successColor,
                        tooltip: AppStrings.renewLicense,
                        onPressed: () => _showRenewDialog(license),
                      ),
                    IconButton(
                      icon: const Icon(Icons.cancel, size: 20),
                      color: AppColors.errorColor,
                      tooltip: AppStrings.revokeLicense,
                      onPressed: license.status == LicenseStatus.revoked
                          ? null
                          : () => _confirmRevoke(license),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(LicenseRecord license) {
    final color = _getStatusColor(license);
    final label = _getStatusLabel(license);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(LicenseRecord license) {
    if (license.status == LicenseStatus.revoked) return AppColors.errorColor;
    if (license.isExpired) return AppColors.errorColor;
    if (license.isExpiringSoon) return AppColors.warningColor;
    if (license.status == LicenseStatus.trial) return AppColors.warningColor;
    return AppColors.successColor;
  }

  String _getStatusLabel(LicenseRecord license) {
    if (license.status == LicenseStatus.revoked) return 'ملغي';
    if (license.isExpired) return 'منتهي';
    if (license.isExpiringSoon) return 'ينتهي قريباً';
    if (license.status == LicenseStatus.trial) return 'تجريبي';
    if (license.status == LicenseStatus.inactive) return 'غير مفعّل';
    if (license.status == LicenseStatus.suspended) return 'موقوف';
    return 'نشط';
  }

  Color _getPackageColor(String packageType) {
    switch (packageType) {
      case 'basic':
        return AppColors.basicColor;
      case 'standard':
        return AppColors.standardColor;
      case 'professional':
        return AppColors.professionalColor;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showRenewDialog(LicenseRecord license) {
    SubscriptionDuration selectedDuration = SubscriptionDuration.monthly;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.refresh, color: AppColors.successColor),
                const SizedBox(width: 12),
                const Text(AppStrings.renewLicense),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تجديد ترخيص: ${license.clientName}'),
                  const SizedBox(height: 16),
                  const Text('مدة التجديد:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...SubscriptionDuration.values
                      .where((d) => d != SubscriptionDuration.trial)
                      .map((duration) {
                    final price =
                        _dataService.getPrice(license.packageType, duration);
                    // ignore: deprecated_member_use
                    return RadioListTile<SubscriptionDuration>(
                      value: duration,
                      // ignore: deprecated_member_use
                      groupValue: selectedDuration,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        setDialogState(() => selectedDuration = value!);
                      },
                      title: Text(_getDurationName(duration)),
                      secondary: Text(
                        '${price.toInt()} ج',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      activeColor: AppColors.successColor,
                      dense: true,
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(AppStrings.cancel),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);

                  try {
                    await _dataService.renewLicense(
                        license.id, selectedDuration);
                    navigator.pop();
                    _loadData();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(AppStrings.licenseRenewed),
                        backgroundColor: AppColors.successColor,
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                          content: Text('خطأ في التجديد: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('تجديد'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.successColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmRevoke(LicenseRecord license) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: AppColors.errorColor),
              const SizedBox(width: 12),
              const Text('تأكيد الإلغاء'),
            ],
          ),
          content: Text(
              'هل أنت متأكد من إلغاء ترخيص "${license.clientName}"؟\nلن يتمكن العميل من استخدام البرنامج.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(AppStrings.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);

                try {
                  await _dataService.revokeLicense(license.id);
                  navigator.pop();
                  _loadData();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(AppStrings.licenseRevoked),
                      backgroundColor: AppColors.errorColor,
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                        content: Text('خطأ: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorColor,
                foregroundColor: Colors.white,
              ),
              child: const Text(AppStrings.revokeLicense),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSuspend(LicenseRecord license) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.pause, color: Colors.deepOrange),
              const SizedBox(width: 12),
              const Text('تأكيد الإيقاف'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'هل أنت متأكد من إيقاف ترخيص "${license.clientName}"؟\nسيتم إيقاف العميل عن استخدام البرنامج.'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'سبب الإيقاف (اختياري)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(AppStrings.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                await _dataService.suspendLicense(license.id,
                    reason: reasonController.text);
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم إيقاف الترخيص'),
                      backgroundColor: Colors.deepOrange,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text('إيقاف'),
            ),
          ],
        ),
      ),
    );
  }

  String _getDurationName(SubscriptionDuration duration) {
    switch (duration) {
      case SubscriptionDuration.trial:
        return 'تجريبي';
      case SubscriptionDuration.monthly:
        return 'شهري';
      case SubscriptionDuration.yearly:
        return 'سنوي';
      case SubscriptionDuration.lifetime:
        return 'مدى الحياة';
    }
  }

  void _showAddLicenseDialog() {
    ClientModel? selectedClient;
    SubscriptionDuration selectedDuration = SubscriptionDuration.monthly;
    final notesController = TextEditingController();
    bool isLoading = false;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.vpn_key_rounded,
                      color: AppColors.primaryColor, size: 28),
                ),
                const SizedBox(width: 16),
                const Text('توليد ترخيص جديد',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      DropdownButtonFormField<ClientModel>(
                        initialValue: selectedClient,
                        decoration: InputDecoration(
                          labelText: 'العميل',
                          prefixIcon:
                              const Icon(Icons.business_center_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        items: _dataService.getClients().map((c) {
                          return DropdownMenuItem(
                              value: c, child: Text(c.name));
                        }).toList(),
                        onChanged: (value) =>
                            setDialogState(() => selectedClient = value),
                        validator: (value) =>
                            value == null ? 'يرجى اختيار العميل' : null,
                      ),
                      const SizedBox(height: 16),
                      if (selectedClient != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor.withAlpha(15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.primaryColor.withAlpha(40)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.inventory_2,
                                  size: 20, color: AppColors.primaryColor),
                              const SizedBox(width: 8),
                              Text(
                                'الباقة الحالية للعميل: ',
                                style: TextStyle(
                                    color: Colors.grey[800],
                                    fontWeight: FontWeight.w500),
                              ),
                              Text(
                                selectedClient!.packageDisplayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryColor),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      DropdownButtonFormField<SubscriptionDuration>(
                        initialValue: selectedDuration,
                        decoration: InputDecoration(
                          labelText: 'المدة الزمنية',
                          prefixIcon: const Icon(Icons.timer_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        items: SubscriptionDuration.values.map((d) {
                          return DropdownMenuItem(
                              value: d, child: Text(_getDurationName(d)));
                        }).toList(),
                        onChanged: (value) =>
                            setDialogState(() => selectedDuration = value!),
                      ),
                      const SizedBox(height: 16),
                      if (selectedClient != null)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.shade50,
                                Colors.green.shade100
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('إجمالي التكلفة:',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green)),
                              Text(
                                '${_dataService.getPrice(selectedClient!.packageType, selectedDuration).toInt()} ج.م',
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'ملاحظات (اختياري)',
                          prefixIcon: const Icon(Icons.notes),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('إلغاء', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: (selectedClient == null || isLoading)
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setDialogState(() => isLoading = true);
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);

                          try {
                            final license = await _dataService.generateLicense(
                              clientId: selectedClient!.id,
                              clientName: selectedClient!.name,
                              packageType: selectedClient!.packageType,
                              duration: selectedDuration,
                              notes: notesController.text,
                            );

                            navigator.pop();
                            _loadData(); // Need to call from parent widget state
                            _showGeneratedKeyDialog(license);

                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('تم إنشاء الترخيص بنجاح'),
                                backgroundColor: AppColors.successColor,
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isLoading = false);
                            messenger.showSnackBar(
                              SnackBar(
                                  content: Text('حدث خطأ: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: AppColors.primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.vpn_key, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('توليد وعرض المفتاح',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGeneratedKeyDialog(LicenseRecord license) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.key, color: AppColors.successColor),
              const SizedBox(width: 12),
              const Expanded(child: Text('تم توليد المفتاح بنجاح')),
            ],
          ),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'هذا المفتاح طافٍ (Floating) ولم يُربط بأي جهاز بعد. '
                    'سيتم ربطه تلقائياً بالجهاز الأول الذي يُفعَّل عليه.',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: SelectableText(
                      license.licenseKey,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: license.licenseKey));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم نسخ المفتاح إلى الحافظة'),
                    backgroundColor: AppColors.successColor,
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('نسخ المفتاح'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullKeyDialog(LicenseRecord license) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.key, color: AppColors.primaryColor),
              const SizedBox(width: 12),
              const Expanded(child: Text('المفتاح الكامل')),
            ],
          ),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'مفتاح الترخيص للعميل: ${license.clientName}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: SelectableText(
                      license.licenseKey,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: license.licenseKey));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم نسخ المفتاح إلى الحافظة'),
                    backgroundColor: AppColors.successColor,
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('نسخ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPriceManagement() {
    final prices = Map<String, double>.from(_dataService.packagePrices);
    final basicController =
        TextEditingController(text: prices['basic']?.toInt().toString());
    final standardController =
        TextEditingController(text: prices['standard']?.toInt().toString());
    final professionalController =
        TextEditingController(text: prices['professional']?.toInt().toString());

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إدارة أسعار الباقات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: basicController,
                decoration: const InputDecoration(
                    labelText: 'سعر الباقة الأساسية (شهري)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: standardController,
                decoration: const InputDecoration(
                    labelText: 'سعر الباقة القياسية (شهري)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: professionalController,
                decoration: const InputDecoration(
                    labelText: 'سعر الباقة الاحترافية (شهري)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Text(
                'ملاحظة: يتم حساب الأسعار السنوية (سعر 10 أشهر) ومدى الحياة (سعر سنتين) تلقائياً.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newPrices = {
                  'basic': double.tryParse(basicController.text) ?? 250.0,
                  'standard': double.tryParse(standardController.text) ?? 400.0,
                  'professional':
                      double.tryParse(professionalController.text) ?? 600.0,
                };
                await _dataService.updatePackagePrices(newPrices);
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تحديث الأسعار بنجاح')),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dataService.removeListener(_onDataChanged);
    _searchController.dispose();
    super.dispose();
  }
}
