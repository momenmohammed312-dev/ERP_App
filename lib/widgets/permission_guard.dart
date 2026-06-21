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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 12),
          Text(
            'غير مصرح',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'لا تملك صلاحية الوصول لهذه الميزة.\n'
            'تواصل مع مدير النظام.',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
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
