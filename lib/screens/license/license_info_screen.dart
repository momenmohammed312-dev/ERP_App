import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/license_manager.dart';

class LicenseInfoScreen extends StatefulWidget {
  const LicenseInfoScreen({super.key});

  @override
  State<LicenseInfoScreen> createState() => _LicenseInfoScreenState();
}

class _LicenseInfoScreenState extends State<LicenseInfoScreen> {
  License? _license;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLicenseInfo();
  }

  Future<void> _loadLicenseInfo() async {
    final licenseManager = LicenseManager();
    final license = await licenseManager.getCurrentLicense();

    setState(() {
      _license = license;
      _isLoading = false;
    });
  }

  Color _getStatusColor() {
    if (_license == null) return Colors.grey;

    if (_license!.isExpired) return Colors.red;
    if (_license!.daysRemaining < 30) return Colors.orange;
    return Colors.green;
  }

  IconData _getStatusIcon() {
    if (_license == null) return Icons.error_outline;

    if (_license!.isExpired) return Icons.error;
    if (_license!.daysRemaining < 30) return Icons.warning;
    return Icons.check_circle;
  }

  String _getStatusText() {
    if (_license == null) return 'لا توجد رخصة';

    if (_license!.isExpired) return 'منتهية الصلاحية';
    if (_license!.daysRemaining < 30) return 'تنتهي قريباً';
    return 'سارية المفعول';
  }

  String _getDurationText() {
    if (_license == null) return 'غير محدد';

    final days = _license!.daysRemaining;
    if (days >= 36500) return 'مدى الحياة';

    final years = days ~/ 365;
    final remainingDays = days % 365;

    if (years > 0) {
      return '$years سنة و $remainingDays يوم';
    } else {
      return '$days يوم';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معلومات الرخصة'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLicenseInfo,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _license == null
          ? _buildNoLicenseScreen()
          : _buildLicenseInfoScreen(),
    );
  }

  Widget _buildNoLicenseScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            Text(
              'لا توجد رخصة نشطة',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'يرجى تفعيل الرخصة لاستخدام النظام',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.go('/activation'),
              icon: const Icon(Icons.key),
              label: const Text('تفعيل الرخصة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseInfoScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Card
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getStatusColor().withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getStatusIcon(),
                      color: _getStatusColor(),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getStatusText(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'حالة الرخصة الحالية',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // License Details Grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.5,
            children: [
              _buildDetailCard(
                'نوع الرخصة',
                _license!.licenseType.toUpperCase(),
                Icons.category,
                Colors.blue,
              ),
              _buildDetailCard(
                'المدة المتبقية',
                _getDurationText(),
                Icons.access_time,
                Colors.green,
              ),
              _buildDetailCard(
                'عدد المستخدمين',
                '${_license!.maxUsers} مستخدم',
                Icons.people,
                Colors.orange,
              ),
              _buildDetailCard(
                'تاريخ الانتهاء',
                _license!.expiryDate.toString().split(' ')[0],
                Icons.event,
                _license!.daysRemaining < 30 ? Colors.red : Colors.purple,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Features Section
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'الميزات المتاحة',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _license!.features.map((feature) {
                      return Chip(
                        label: Text(
                          _getFeatureDisplayName(feature),
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: Colors.blue.shade100,
                        side: BorderSide(color: Colors.blue.shade300),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Warning Card (if expiring soon)
          if (_license!.daysRemaining < 30 && !_license!.isExpired)
            Card(
              color: Colors.orange.shade50,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Colors.orange.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تنبيه انتهاء الرخصة',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'تبقى ${_license!.daysRemaining} يوم على انتهاء الرخصة. يرجى التجديد قبل انتهاء الصلاحية.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Lifetime Indicator
          if (_license!.daysRemaining >= 36500)
            Card(
              color: Colors.green.shade50,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.all_inclusive,
                      color: Colors.green.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'رخصة مدى الحياة',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'هذه الرخصة صالحة لمدى الحياة ولا تحتاج للتجديد',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _getFeatureDisplayName(String feature) {
    final featureNames = {
      'pos': 'نقاط البيع',
      'inventory': 'إدارة المخزون',
      'customers': 'إدارة العملاء',
      'suppliers': 'إدارة الموردين',
      'reports': 'التقارير',
      'accounting': 'المحاسبة',
      'users': 'إدارة المستخدمين',
      'backup': 'النسخ الاحتياطي',
      'export': 'تصدير البيانات',
      'admin': 'صلاحيات المدير',
    };

    return featureNames[feature] ?? feature;
  }
}
