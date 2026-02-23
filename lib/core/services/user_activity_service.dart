import '../database/app_database.dart';
import '../database/dao/user_activity_dao.dart';

class UserActivityService {
  final UserActivityDao _activityDao;

  UserActivityService(AppDatabase database)
    : _activityDao = UserActivityDao(database);

  /// Log user login
  Future<void> logLogin(
    int userId, {
    String? ipAddress,
    String? sessionId,
  }) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'login',
      description: 'User logged in',
      ipAddress: ipAddress,
      sessionId: sessionId,
    );
  }

  /// Log user logout
  Future<void> logLogout(int userId, {String? sessionId}) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'logout',
      description: 'User logged out',
      sessionId: sessionId,
    );
  }

  /// Log user creation
  Future<void> logUserCreated(
    int createdBy,
    int newUserId,
    String username,
  ) async {
    await _activityDao.logActivity(
      userId: createdBy,
      action: 'create_user',
      description: 'Created new user: $username',
      entityType: 'User',
      entityId: newUserId,
    );
  }

  /// Log user update
  Future<void> logUserUpdated(int updatedBy, int userId, String changes) async {
    await _activityDao.logActivity(
      userId: updatedBy,
      action: 'update_user',
      description: 'Updated user profile: $changes',
      entityType: 'User',
      entityId: userId,
    );
  }

  /// Log user deletion
  Future<void> logUserDeleted(
    int deletedBy,
    int userId,
    String username,
  ) async {
    await _activityDao.logActivity(
      userId: deletedBy,
      action: 'delete_user',
      description: 'Deleted user: $username',
      entityType: 'User',
      entityId: userId,
    );
  }

  /// Log sale creation
  Future<void> logSaleCreated(int userId, int invoiceId, double amount) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'create_sale',
      description:
          'Created sale invoice #$invoiceId for ${amount.toStringAsFixed(2)} ج.م',
      entityType: 'Invoice',
      entityId: invoiceId,
    );
  }

  /// Log sale update
  Future<void> logSaleUpdated(int userId, int invoiceId, String changes) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'update_sale',
      description: 'Updated sale invoice #$invoiceId: $changes',
      entityType: 'Invoice',
      entityId: invoiceId,
    );
  }

  /// Log sale deletion
  Future<void> logSaleDeleted(int userId, int invoiceId, double amount) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'delete_sale',
      description:
          'Deleted sale invoice #$invoiceId for ${amount.toStringAsFixed(2)} ج.م',
      entityType: 'Invoice',
      entityId: invoiceId,
    );
  }

  /// Log customer creation
  Future<void> logCustomerCreated(
    int userId,
    int customerId,
    String customerName,
  ) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'create_customer',
      description: 'Created new customer: $customerName',
      entityType: 'Customer',
      entityId: customerId,
    );
  }

  /// Log customer update
  Future<void> logCustomerUpdated(
    int userId,
    int customerId,
    String changes,
  ) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'update_customer',
      description: 'Updated customer: $changes',
      entityType: 'Customer',
      entityId: customerId,
    );
  }

  /// Log product creation
  Future<void> logProductCreated(
    int userId,
    int productId,
    String productName,
  ) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'create_product',
      description: 'Created new product: $productName',
      entityType: 'Product',
      entityId: productId,
    );
  }

  /// Log product update
  Future<void> logProductUpdated(
    int userId,
    int productId,
    String changes,
  ) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'update_product',
      description: 'Updated product: $changes',
      entityType: 'Product',
      entityId: productId,
    );
  }

  /// Log day opened
  Future<void> logDayOpened(int userId) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'open_day',
      description: 'Opened the business day',
    );
  }

  /// Log day closed
  Future<void> logDayClosed(int userId) async {
    await _activityDao.logActivity(
      userId: userId,
      action: 'close_day',
      description: 'Closed the business day',
    );
  }

  /// Get user activity logs
  Future<List<UserActivityLogData>> getUserActivityLogs(
    int userId, {
    int? limit,
    DateTime? since,
  }) {
    return _activityDao.getUserActivityLogs(userId, limit: limit, since: since);
  }

  /// Get recent activity logs
  Future<List<UserActivityLogData>> getRecentActivityLogs({
    int limit = 50,
    String? action,
    String? entityType,
  }) {
    return _activityDao.getRecentActivityLogs(
      limit: limit,
      action: action,
      entityType: entityType,
    );
  }

  /// Get activity statistics
  Future<Map<String, int>> getActivityStatistics({
    DateTime? since,
    int? userId,
  }) {
    return _activityDao.getActivityStatistics(since: since, userId: userId);
  }

  /// Cleanup old logs
  Future<int> cleanupOldLogs(Duration maxAge) {
    return _activityDao.deleteOldLogs(maxAge);
  }
}
