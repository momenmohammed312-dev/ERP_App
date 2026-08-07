import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../tables/audit_log_table.dart';

part 'audit_dao.g.dart';

@DriftAccessor(tables: [AuditLog])
class AuditDao extends DatabaseAccessor<AppDatabase> with _$AuditDaoMixin {
  AuditDao(super.db);

  /// Log audit trail
  Future<void> logAudit({
    int? userId,
    required String action,
    required String tableName,
    int? recordId,
    String? details,
  }) async {
    await into(auditLog).insert(
      AuditLogCompanion.insert(
        id: const Uuid().v4(),
        userId: Value(userId),
        action: action,
        tableNameField: tableName,
        recordId: Value(recordId),
        details: Value(details),
        timestamp: DateTime.now(),
        ipAddress: Value(null),
      ),
    );
  }

  /// Get audit logs
  Future<List<AuditLogData>> getAuditLogs({
    int? userId,
    String? tableName,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
  }) async {
    final query = select(auditLog);

    if (userId != null) {
      query.where((tbl) => tbl.userId.equals(userId));
    }

    if (tableName != null) {
      query.where((tbl) => tbl.tableNameField.equals(tableName));
    }

    if (startDate != null) {
      query.where((tbl) => tbl.timestamp.isBiggerOrEqualValue(startDate));
    }

    if (endDate != null) {
      query.where((tbl) => tbl.timestamp.isSmallerOrEqualValue(endDate));
    }

    query.orderBy([(tbl) => OrderingTerm.desc(tbl.timestamp)]);
    query.limit(limit);

    return await query.get();
  }
}
