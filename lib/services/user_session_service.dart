import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'license_manager.dart';
import 'audit_service.dart';
import '../core/database/database_singleton.dart';

class UserSessionService {
  static const String _activeSessionsKey = 'active_user_sessions';
  static const String _sessionStartPrefix = 'session_start_';

  static Timer? _cleanupTimer;

  /// Start the session cleanup timer
  static void startSessionCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupExpiredSessions();
    });
  }

  /// Stop the session cleanup timer
  static void stopSessionCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// Check if a new user can be added (within license limit)
  static Future<bool> canAddUser() async {
    try {
      final license = await LicenseManager().getCurrentLicense();
      if (license == null) return false;

      final maxUsers = license.maxUsers;
      final activeSessions = await getActiveSessions();

      debugPrint(
        'User Session Check: ${activeSessions.length}/$maxUsers active',
      );
      return activeSessions.length < maxUsers;
    } catch (e) {
      debugPrint('Error checking user limit: $e');
      return false;
    }
  }

  /// Get remaining user slots
  static Future<int> getRemainingSlots() async {
    try {
      final license = await LicenseManager().getCurrentLicense();
      if (license == null) return 0;

      final maxUsers = license.maxUsers;
      final activeSessions = await getActiveSessions();

      return maxUsers - activeSessions.length;
    } catch (e) {
      debugPrint('Error getting remaining slots: $e');
      return 0;
    }
  }

  /// Check if user can login (concurrent user limit)
  static Future<bool> canUserLogin(String userId) async {
    try {
      // First check if we're at the user limit
      if (!await canAddUser()) {
        // Check if this user is already logged in
        final activeSessions = await getActiveSessions();
        final alreadyLoggedIn = activeSessions.any(
          (session) => session['userId'] == userId,
        );

        if (!alreadyLoggedIn) {
          debugPrint('User $userId blocked: At user limit');
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error checking login permission: $e');
      return false;
    }
  }

  /// Register a user session
  static Future<void> registerUserSession({
    required String userId,
    required String username,
    String? deviceId,
  }) async {
    try {
      final db = await DatabaseSingleton.getInstance();

      final prefs = await SharedPreferences.getInstance();
      final activeSessions = await getActiveSessions();

      // Remove any existing session for this user
      activeSessions.removeWhere((session) => session['userId'] == userId);

      // Add new session
      final newSession = {
        'userId': userId,
        'username': username,
        'deviceId': deviceId ?? 'unknown',
        'loginTime': DateTime.now().toIso8601String(),
        'lastActivity': DateTime.now().toIso8601String(),
      };

      activeSessions.add(newSession);
      await _saveActiveSessions(activeSessions);

      // Store session start time for this user
      await prefs.setString(
        '$_sessionStartPrefix$userId',
        DateTime.now().toIso8601String(),
      );

      // Log the login
      await AuditService.log(
        db: db,
        userId: int.tryParse(userId) ?? 0,
        action: AuditAction.login,
        tableName: 'users',
        recordId: int.tryParse(userId),
        details: {
          'username': username,
          'deviceId': deviceId,
          'login_time': DateTime.now().toIso8601String(),
        },
      );

      debugPrint('User session registered: $username ($userId)');
    } catch (e) {
      debugPrint('Error registering user session: $e');
    }
  }

  /// Update user activity (keep session alive)
  static Future<void> updateActivity(String userId) async {
    try {
      final activeSessions = await getActiveSessions();
      final sessionIndex = activeSessions.indexWhere(
        (session) => session['userId'] == userId,
      );

      if (sessionIndex != -1) {
        activeSessions[sessionIndex]['lastActivity'] = DateTime.now()
            .toIso8601String();
        await _saveActiveSessions(activeSessions);
      }
    } catch (e) {
      debugPrint('Error updating activity: $e');
    }
  }

  /// Logout a user session
  static Future<void> logoutUser(String userId) async {
    try {
      final db = await DatabaseSingleton.getInstance();

      final activeSessions = await getActiveSessions();
      activeSessions.removeWhere((session) => session['userId'] == userId);
      await _saveActiveSessions(activeSessions);

      // Remove session start time
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_sessionStartPrefix$userId');

      // Log the logout
      await AuditService.log(
        db: db,
        userId: int.tryParse(userId) ?? 0,
        action: AuditAction.logout,
        tableName: 'users',
        recordId: int.tryParse(userId),
        details: {'logout_time': DateTime.now().toIso8601String()},
      );

      debugPrint('User logged out: $userId');
    } catch (e) {
      debugPrint('Error logging out user: $e');
    }
  }

  /// Get all active sessions
  static Future<List<Map<String, String>>> getActiveSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionsJson = prefs.getString(_activeSessionsKey);

      if (sessionsJson == null) return [];

      // Parse JSON manually since we don't have dart:convert imported
      final sessions = <Map<String, String>>[];

      // Simple JSON parsing for our specific format
      final entries = sessionsJson.split('|');
      for (final entry in entries) {
        if (entry.isEmpty) continue;

        final parts = entry.split(',');
        final session = <String, String>{};

        for (final part in parts) {
          final keyValue = part.split(':');
          if (keyValue.length == 2) {
            session[keyValue[0]] = keyValue[1];
          }
        }

        if (session.isNotEmpty) {
          sessions.add(session);
        }
      }

      return sessions;
    } catch (e) {
      debugPrint('Error getting active sessions: $e');
      return [];
    }
  }

  /// Get current active user count
  static Future<int> getActiveUserCount() async {
    final sessions = await getActiveSessions();
    return sessions.length;
  }

  /// Get maximum allowed users from license
  static Future<int> getMaxUsers() async {
    try {
      final license = await LicenseManager().getCurrentLicense();
      return license?.maxUsers ?? 1;
    } catch (e) {
      debugPrint('Error getting max users: $e');
      return 1;
    }
  }

  /// Save active sessions to preferences
  static Future<void> _saveActiveSessions(
    List<Map<String, String>> sessions,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Convert to simple string format
      final sessionsString = sessions
          .map((session) {
            return 'userId:${session['userId']},username:${session['username']},deviceId:${session['deviceId']},loginTime:${session['loginTime']},lastActivity:${session['lastActivity']}';
          })
          .join('|');

      await prefs.setString(_activeSessionsKey, sessionsString);
    } catch (e) {
      debugPrint('Error saving active sessions: $e');
    }
  }

  /// Clean up expired sessions (older than 24 hours)
  static Future<void> _cleanupExpiredSessions() async {
    try {
      final db = await DatabaseSingleton.getInstance();

      final activeSessions = await getActiveSessions();
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(hours: 24));

      final validSessions = <Map<String, String>>[];

      for (final session in activeSessions) {
        final lastActivityStr = session['lastActivity'];
        if (lastActivityStr != null) {
          final lastActivity = DateTime.parse(lastActivityStr);
          if (lastActivity.isAfter(cutoff)) {
            validSessions.add(session);
          } else {
            // Log expired session removal
            await AuditService.log(
              db: db,
              userId: int.tryParse(session['userId'] ?? '') ?? 0,
              action: AuditAction.logout,
              tableName: 'users',
              recordId: int.tryParse(session['userId'] ?? ''),
              details: {
                'reason': 'session_expired',
                'last_activity': lastActivityStr,
              },
            );
          }
        }
      }

      if (validSessions.length != activeSessions.length) {
        await _saveActiveSessions(validSessions);
        debugPrint(
          'Cleaned up ${activeSessions.length - validSessions.length} expired sessions',
        );
      }
    } catch (e) {
      debugPrint('Error cleaning up expired sessions: $e');
    }
  }

  /// Force logout all users (admin function)
  static Future<void> logoutAllUsers() async {
    try {
      final activeSessions = await getActiveSessions();

      for (final session in activeSessions) {
        await logoutUser(session['userId']!);
      }

      debugPrint('Force logged out all users');
    } catch (e) {
      debugPrint('Error logging out all users: $e');
    }
  }

  /// Get session statistics
  static Future<Map<String, dynamic>> getSessionStats() async {
    try {
      final activeSessions = await getActiveSessions();
      final maxUsers = await getMaxUsers();

      return {
        'activeUsers': activeSessions.length,
        'maxUsers': maxUsers,
        'remainingSlots': maxUsers - activeSessions.length,
        'isAtLimit': activeSessions.length >= maxUsers,
        'utilizationPercent': maxUsers > 0
            ? (activeSessions.length / maxUsers * 100).round()
            : 0,
      };
    } catch (e) {
      debugPrint('Error getting session stats: $e');
      return {
        'activeUsers': 0,
        'maxUsers': 1,
        'remainingSlots': 1,
        'isAtLimit': false,
        'utilizationPercent': 0,
      };
    }
  }
}
