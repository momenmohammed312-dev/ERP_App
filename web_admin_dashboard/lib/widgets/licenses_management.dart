import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/license_model.dart';
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
    _loadData();
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
      child: Container(
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
    return Expanded(
      child: Container(
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
                DropdownMenuItem(value: 'trial', child: Text('تجريبي')),
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      license.licenseKey,
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
                          content: Text(AppStrings.copied),
                          backgroundColor: AppColors.successColor,
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: AppStrings.copyLicenseKey,
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
                    final price = LicenseKeyGenerator.getPrice(
                        license.packageType, duration);
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
                  await _dataService.renewLicense(license.id, selectedDuration);
                  if (mounted) {
                    Navigator.pop(context);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStrings.licenseRenewed),
                        backgroundColor: AppColors.successColor,
                      ),
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
                await _dataService.revokeLicense(license.id);
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(AppStrings.licenseRevoked),
                      backgroundColor: AppColors.errorColor,
                    ),
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
