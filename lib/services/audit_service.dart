import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/database/app_database.dart';

enum AuditAction {
  create,
  read,
  update,
  delete,
  login,
  logout,
  export,
  print,
  licenseActivate,
  licenseDeactivate,
}

class AuditService {
  /// Log an action
  static Future<void> log({
    required AppDatabase db,
    int? userId,
    required AuditAction action,
    required String tableName,
    int? recordId,
    Map<String, dynamic>? details,
  }) async {
    try {
      final auditDao = db.auditDao;
      await auditDao.logAudit(
        userId: userId,
        action: action.toString().split('.').last,
        tableName: tableName,
        recordId: recordId,
        details: details != null ? jsonEncode(details) : null,
      );
    } catch (e) {
      debugPrint('Audit logging failed: $e');
      // Don't throw - audit failure shouldn't break app
    }
  }

  /// Get audit logs
  static Future<List<AuditLogData>> getAuditLogs({
    required AppDatabase db,
    int? userId,
    String? tableName,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
  }) async {
    try {
      final auditDao = db.auditDao;
      return await auditDao.getAuditLogs(
        userId: userId,
        tableName: tableName,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
      );
    } catch (e) {
      debugPrint('Error getting audit logs: $e');
      return [];
    }
  }
}
