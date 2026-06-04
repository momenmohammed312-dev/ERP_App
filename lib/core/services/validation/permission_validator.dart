import 'package:pos_offline_desktop/core/models/user_model.dart';

class PermissionValidator {
  static void requirePermission(User? user, Permission permission, [String? action]) {
    if (user == null) {
      throw PermissionException('يجب تسجيل الدخول أولاً');
    }
    if (!user.hasPermission(permission)) {
      throw PermissionException(
        action != null
            ? 'لا تملك صلاحية ${PermissionMatrix.getPermissionDisplayName(permission)} لـ $action'
            : 'لا تملك صلاحية ${PermissionMatrix.getPermissionDisplayName(permission)}',
      );
    }
  }

  static bool hasPermission(User? user, Permission permission) {
    return user != null && user.hasPermission(permission);
  }
}

class PermissionException implements Exception {
  final String message;
  PermissionException(this.message);

  @override
  String toString() => message;
}
