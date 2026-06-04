import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class AuditService {
  static Future<void> log({
    required AppDatabase db,
    required String action,
    required String tableName,
    int? recordId,
    String? details,
    dynamic oldValue,
    dynamic newValue,
  }) async {
    final logId = DateTime.now().millisecondsSinceEpoch.toString();
    
    await db.into(db.auditLog).insert(
      AuditLogCompanion.insert(
        id: logId,
        action: action,
        tableNameField: tableName,
        recordId: Value(recordId),
        details: Value(details),
        oldValue: Value(oldValue != null ? jsonEncode(oldValue) : null),
        newValue: Value(newValue != null ? jsonEncode(newValue) : null),
        timestamp: DateTime.now(),
      ),
    );
  }
}
