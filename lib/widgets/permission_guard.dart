import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/user_model.dart';
import '../core/provider/auth_provider.dart';

/// ويدجت لحماية المحتوى بناءً على الصلاحيات
class PermissionGuard extends ConsumerWidget {
  final Permission permission;
  final Widget child;
  final Widget? fallback;
  final bool showUpgradePrompt;

  const PermissionGuard({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.showUpgradePrompt = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPermission = ref.watch(
      authProvider.select((user) => user?.hasPermission(permission) ?? false),
    );

    if (hasPermission) {
      return child;
    }

    if (fallback != null) {
      return fallback!;
    }

    if (showUpgradePrompt) {
      return _buildUpgradePrompt(context);
    }

    return const SizedBox.shrink();
  }

  Widget _buildUpgradePrompt(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 8),
          Text(
            'صلاحية غير متوفرة',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'هذه الميزة تتطلب صلاحية ${_getPermissionDisplayName()}',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _showUpgradeDialog(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('ترقية الحساب'),
          ),
        ],
      ),
    );
  }

  String _getPermissionDisplayName() {
    return PermissionMatrix.getPermissionDisplayName(permission);
  }

  void _showUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ترقية الحساب'),
        content: const Text(
          'للوصول إلى هذه الميزة، يرجى ترقية حسابك إلى باقة أعلى. تواصل مع مدير النظام للمزيد من المعلومات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('يرجى التواصل مع مدير النظام لترقية الحساب'),
                ),
              );
            },
            child: const Text('ترقية الآن'),
          ),
        ],
      ),
    );
  }
}

/// ويدجت لحماية القائمة بناءً على الصلاحيات
class PermissionListGuard extends ConsumerWidget {
  final List<Permission> permissions;
  final bool requireAll;
  final Widget child;
  final Widget? fallback;

  const PermissionListGuard({
    super.key,
    required this.permissions,
    this.requireAll = false,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPermission = ref.watch(
      authProvider.select((user) {
        if (user == null) return false;
        if (requireAll) {
          return permissions.every(user.hasPermission);
        } else {
          return permissions.any(user.hasPermission);
        }
      }),
    );

    if (hasPermission) {
      return child;
    }

    return fallback ?? const SizedBox.shrink();
  }
}
