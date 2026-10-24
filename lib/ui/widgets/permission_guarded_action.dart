import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';

/// زرار محمي بصلاحية، **بيبان دايماً**.
///
/// **ليه مش بيختفي؟** الإصدارين الأولين كانوا بيعملوا `SizedBox.shrink()` أو
/// `onPressed: null` لما المستخدم ماعندوش الصلاحية، والنتيجة إن المستخدم بيشوف
/// إن الميزة "مش موجودة" من غير أي تفسير — أو بيشوف زرار مش شغال وميعرفش ليه.
/// دلوقتي الزرار موجود دايماً، والتحقق بيحصل **داخل الديالوج** مع رسالة بتقول
/// بالظبط: دورك إيه والصلاحية الناقصة إيه.
class PermissionGuardedAction extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;
  final Color? foregroundColor;

  const PermissionGuardedAction({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: label,
        style: TextButton.styleFrom(foregroundColor: foregroundColor),
      );

  /// اسم الدور بالعربي — للرسائل.
  static String roleName(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'مدير عام';
      case UserRole.manager:
        return 'مدير';
      case UserRole.cashier:
        return 'كاشير';
      case UserRole.accountant:
        return 'محاسب';
      case UserRole.viewer:
        return 'مشاهد';
    }
  }

  /// يفحص الصلاحية ويبني رسالة واضحة للمفialog.
  /// بيترجع `null` لو المستخدم عنده الصلاحية.
  static String? check(
    BuildContext context,
    WidgetRef ref, {
    required Permission permission,
    required String permissionLabel,
  }) {
    final user = ref.read(authProvider);
    if (user != null && user.hasPermission(permission)) return null;
    final who = user == null
        ? 'اللي مش مسجّل دخول'
        : '${user.username} (${roleName(user.role)})';
    return 'محتاج صلاحية "$permissionLabel".\nالدور الحالي: $who';
  }
}

/// نفس الفكرة بس لأيقونة (زي أزرار صف التقارير).
class PermissionGuardedIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final double size;
  final Color color;
  final String tooltip;

  const PermissionGuardedIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    this.size = 20,
    this.color = Colors.red,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icon, size: size, color: color),
        onPressed: onPressed,
        tooltip: tooltip,
      );
}