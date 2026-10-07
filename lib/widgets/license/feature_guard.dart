import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../config/license_config.dart';
import '../../core/provider/license_provider.dart';

/// Wraps widgets or pages that require specific licensed modules.
///
/// If [hideWhenLocked] is true, the widget disappears completely when the feature is disabled.
/// Otherwise, it shows [lockedWidget] or a friendly upgrade card.
class FeatureGuard extends ConsumerWidget {
  final String featureName;
  final Widget child;
  final Widget? lockedWidget;
  final bool hideWhenLocked;

  const FeatureGuard({
    super.key,
    required this.featureName,
    required this.child,
    this.lockedWidget,
    this.hideWhenLocked = false,
  });

  /// Factory constructor to support legacy calls with `feature:` parameter
  factory FeatureGuard.named({
    Key? key,
    required String feature,
    required Widget child,
    Widget? lockedWidget,
    bool hideWhenLocked = false,
  }) {
    return FeatureGuard(
      key: key,
      featureName: feature,
      lockedWidget: lockedWidget,
      hideWhenLocked: hideWhenLocked,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Free version flavor/build — always unlocked
    if (LicenseConfig.isFreeVersion) {
      return child;
    }

    // 2. Fundamental core features always available without license restrictions
    const coreFeatures = [
      'pos',
      'cash_sales',
      'inventory',
      'reports',
    ];
    if (coreFeatures.contains(featureName)) {
      return child;
    }

    // 3. Dynamic check against the server-granted lease features via Riverpod
    final isEnabled = ref.watch(isFeatureEnabledProvider(featureName));
    if (isEnabled) {
      return child;
    }

    if (hideWhenLocked) {
      return const SizedBox.shrink();
    }

    return lockedWidget ?? _buildLockedWidget(context);
  }

  Widget _buildLockedWidget(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'هذه الميزة غير مفعلة',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'موديول "$featureName" غير مشمول في ترخيصك الحالي.\nتواصل مع الإدارة لتفعيله على حسابك.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showUpgradeDialog(context),
              icon: const Icon(Icons.support_agent),
              label: const Text('طلب تفعيل الموديول'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('طلب تفعيل الميزة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('لتفعيل ميزة "$featureName" على جهازك:'),
            const SizedBox(height: 12),
            const Text(
              'تواصل مع الدعم الفني، وسيتم تفعيل الميزة فوراً من السيرفر دون الحاجة لإعادة تثبيت البرنامج.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
