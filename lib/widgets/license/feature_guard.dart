import 'package:flutter/material.dart';
import '../../services/license_manager.dart';

class FeatureGuard extends StatelessWidget {
  final String featureName;
  final Widget child;
  final Widget? lockedWidget;

  const FeatureGuard({
    super.key,
    required this.featureName,
    required this.child,
    this.lockedWidget,
  });

  @override
  Widget build(BuildContext context) {
    // For development: temporarily bypass license check for common features
    final bypassFeatures = [
      'suppliers',
      'pos',
      'inventory',
      'customers',
      'reports',
    ];
    if (bypassFeatures.contains(featureName)) {
      return child;
    }

    return FutureBuilder<bool>(
      future: LicenseManager().isFeatureEnabled(featureName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasData && snapshot.data == true) {
          return child;
        }

        return lockedWidget ?? _buildLockedWidget(context);
      },
    );
  }

  Widget _buildLockedWidget(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'الميزة مقفولة',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'قم بترقية رخصتك للوصول إلى هذه الميزة',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              // Show upgrade dialog or contact support
              _showUpgradeDialog(context);
            },
            child: const Text('ترقية الرخصة'),
          ),
        ],
      ),
    );
  }

  void _showUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الترقية مطلوبة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ميزة "$featureName" تتطلب ترقية الرخصة.'),
            const SizedBox(height: 16),
            const Text('تواصل مع الدعم لخيارات الترقية:'),
            const SizedBox(height: 8),
            const SelectableText(
              'البريد الإلكتروني: support@yourcompany.com\nالهاتف: +20 XXX XXX XXXX',
              style: TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }
}
