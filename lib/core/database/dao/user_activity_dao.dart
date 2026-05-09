import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/tables.dart';

part 'user_activity_dao.g.dart';

@DriftAccessor(tables: [UserActivityLog])
class UserActivityDao extends DatabaseAccessor<AppDatabase>
    with _$UserActivityDaoMixin {
  UserActivityDao(super.db);

  /// Log user activity
  Future<int> logActivity({
    required int userId,
    required String action,
    required String description,
    String? entityType,
    int? entityId,
    String? oldValue,
    String? newValue,
    String? ipAddress,
    String? sessionId,
  }) {
    final companion = UserActivityLogCompanion(
      userId: Value(userId),
      action: Value(action),
      description: Value(description),
      entityType: entityType != null ? Value(entityType) : const Value.absent(),
      entityId: entityId != null ? Value(entityId) : const Value.absent(),
      oldValue: oldValue != null ? Value(oldValue) : const Value.absent(),
      newValue: newValue != null ? Value(newValue) : const Value.absent(),
      ipAddress: ipAddress != null ? Value(ipAddress) : const Value.absent(),
      sessionId: sessionId != null ? Value(sessionId) : const Value.absent(),
      timestamp: Value(DateTime.now()),
    );

    return into(userActivityLog).insert(companion);
  }

  /// Get activity logs for a user
  Future<List<UserActivityLogData>> getUserActivityLogs(
    int userId, {
    int? limit,
    DateTime? since,
  }) {
    var query = select(userActivityLog)
      ..where((log) => log.userId.equals(userId))
      ..orderBy([(log) => OrderingTerm.desc(log.timestamp)]);

    if (since != null) {
      query = query..where((log) => log.timestamp.isBiggerThanValue(since));
    }

    if (limit != null) {
      query = query..limit(limit);
    }

    return query.get();
  }

  /// Get recent activity logs
  Future<List<UserActivityLogData>> getRecentActivityLogs({
    int limit = 50,
    String? action,
    String? entityType,
  }) {
    var query = select(userActivityLog)
      ..orderBy([(log) => OrderingTerm.desc(log.timestamp)])
      ..limit(limit);

    if (action != null) {
      query = query..where((log) => log.action.equals(action));
    }

    if (entityType != null) {
      query = query..where((log) => log.entityType.equals(entityType));
    }

    return query.get();
  }

  /// Get activity logs for a specific entity
  Future<List<UserActivityLogData>> getEntityActivityLogs(
    String entityType,
    int entityId,
  ) {
    return (select(userActivityLog)
          ..where(
            (log) =>
                log.entityType.equals(entityType) &
                log.entityId.equals(entityId),
          )
          ..orderBy([(log) => OrderingTerm.desc(log.timestamp)]))
        .get();
  }

  /// Delete old activity logs (cleanup)
  Future<int> deleteOldLogs(Duration maxAge) {
    final cutoffDate = DateTime.now().subtract(maxAge);
    return (delete(
      userActivityLog,
    )..where((log) => log.timestamp.isSmallerThanValue(cutoffDate))).go();
  }

  /// Get activity statistics
  Future<Map<String, int>> getActivityStatistics({
    DateTime? since,
    int? userId,
  }) async {
    var query = selectOnly(userActivityLog)
      ..addColumns([userActivityLog.action, userActivityLog.action.count()]);

    if (since != null) {
      query = query..where(userActivityLog.timestamp.isBiggerThanValue(since));
    }

    if (userId != null) {
      query = query..where(userActivityLog.userId.equals(userId));
    }

    query = query..groupBy([userActivityLog.action]);

    final results = await query.get();

    return {
      for (final row in results)
        row.read(userActivityLog.action)!: row.read(
          userActivityLog.action.count(),
        )!,
    };
  }
}
