import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'license_manager.dart';
import '../core/utils/logger.dart';

class SessionService {
  static const String _sessionKeyPrefix = 'user_session_';
  static const String _activeSessionsKey = 'active_sessions';
  static const Duration _sessionTimeout = Duration(hours: 8); // 8 hours
  static const Duration _cleanupInterval = Duration(
    hours: 1,
  ); // Check every hour

  static Timer? _cleanupTimer;

  /// Start session cleanup timer
  static void startSessionCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      cleanupExpiredSessions();
    });
  }

  /// Stop session cleanup timer
  static void stopSessionCleanup() {
    _cleanupTimer?.cancel();
  }

  /// Create new user session
  static Future<String> createSession(int userId, String username) async {
    try {
      // Check concurrent user limit
      final canCreateSession = await checkConcurrentUserLimit();
      if (!canCreateSession) {
        throw Exception('Maximum concurrent users limit reached');
      }

      // Generate session ID
      final sessionId = _generateSessionId();

      // Create session data
      final sessionData = {
        'session_id': sessionId,
        'user_id': userId,
        'username': username,
        'created_at': DateTime.now().toIso8601String(),
        'last_activity': DateTime.now().toIso8601String(),
        'ip_address': 'localhost', // In real app, get actual IP
        'device_info': 'Desktop App',
      };

      // Save session
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_sessionKeyPrefix$sessionId',
        jsonEncode(sessionData),
      );

      // Add to active sessions list
      await _addActiveSession(sessionId);

      AppLogger.i('✅ Session created for user: $username ($sessionId)');
      return sessionId;
    } catch (e) {
      AppLogger.e('Session creation failed', e);
      rethrow;
    }
  }

  /// Validate session
  static Future<bool> validateSession(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionJson = prefs.getString('$_sessionKeyPrefix$sessionId');

      if (sessionJson == null) {
        return false;
      }

      final sessionData = jsonDecode(sessionJson) as Map<String, dynamic>;
      final lastActivity = DateTime.parse(
        sessionData['last_activity'] as String,
      );

      // Check if session expired
      if (DateTime.now().difference(lastActivity) > _sessionTimeout) {
        await destroySession(sessionId);
        return false;
      }

      // Update last activity
      sessionData['last_activity'] = DateTime.now().toIso8601String();
      await prefs.setString(
        '$_sessionKeyPrefix$sessionId',
        jsonEncode(sessionData),
      );

      return true;
    } catch (e) {
      AppLogger.e('Session validation error', e);
      return false;
    }
  }

  /// Destroy session
  static Future<void> destroySession(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Remove session data
      await prefs.remove('$_sessionKeyPrefix$sessionId');

      // Remove from active sessions
      await _removeActiveSession(sessionId);

      AppLogger.i('🗑️ Session destroyed: $sessionId');
    } catch (e) {
      AppLogger.e('Session destruction error', e);
    }
  }

  /// Get active sessions count
  static Future<int> getActiveSessionCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeSessionsJson = prefs.getStringList(_activeSessionsKey) ?? [];

      int validSessions = 0;

      for (final sessionId in activeSessionsJson) {
        if (await validateSession(sessionId)) {
          validSessions++;
        } else {
          await _removeActiveSession(sessionId);
        }
      }

      return validSessions;
    } catch (e) {
      AppLogger.e('Error getting active session count', e);
      return 0;
    }
  }

  /// Get all active sessions
  static Future<List<Map<String, dynamic>>> getActiveSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeSessionsJson = prefs.getStringList(_activeSessionsKey) ?? [];

      final sessions = <Map<String, dynamic>>[];

      for (final sessionId in activeSessionsJson) {
        final sessionJson = prefs.getString('$_sessionKeyPrefix$sessionId');
        if (sessionJson != null) {
          final sessionData = jsonDecode(sessionJson) as Map<String, dynamic>;
          final lastActivity = DateTime.parse(
            sessionData['last_activity'] as String,
          );

          // Check if session is still valid
          if (DateTime.now().difference(lastActivity) <= _sessionTimeout) {
            sessions.add(sessionData);
          } else {
            await destroySession(sessionId);
          }
        }
      }

      return sessions;
    } catch (e) {
      AppLogger.e('Error getting active sessions', e);
      return [];
    }
  }

  /// Check concurrent user limit
  static Future<bool> checkConcurrentUserLimit() async {
    try {
      // Get current license
      final licenseManager = LicenseManager();
      final license = await licenseManager.getCurrentLicense();

      if (license == null) {
        return false; // No license = no access
      }

      // Get active session count
      final activeCount = await getActiveSessionCount();

      // Check against license limit
      if (activeCount >= license.maxUsers) {
        AppLogger.w(
          '❌ Concurrent user limit reached: $activeCount/${license.maxUsers}',
        );
        return false;
      }

      AppLogger.i(
        '✅ Concurrent user check passed: $activeCount/${license.maxUsers}',
      );
      return true;
    } catch (e) {
      AppLogger.e('Concurrent user limit check error', e);
      return false;
    }
  }

  /// Force logout inactive users
  static Future<void> forceLogoutInactiveUsers() async {
    try {
      final sessions = await getActiveSessions();
      final now = DateTime.now();

      for (final session in sessions) {
        final lastActivity = DateTime.parse(session['last_activity'] as String);

        if (now.difference(lastActivity) > _sessionTimeout) {
          await destroySession(session['session_id'] as String);
          AppLogger.i(
            '🔐 Force logged out inactive user: ${session['username']}',
          );
        }
      }
    } catch (e) {
      AppLogger.e('Force logout error', e);
    }
  }

  /// Cleanup expired sessions
  static Future<void> cleanupExpiredSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith(_sessionKeyPrefix)) {
          final sessionJson = prefs.getString(key);
          if (sessionJson != null) {
            final sessionData = jsonDecode(sessionJson) as Map<String, dynamic>;
            final lastActivity = DateTime.parse(
              sessionData['last_activity'] as String,
            );

            if (DateTime.now().difference(lastActivity) > _sessionTimeout) {
              final sessionId = key.substring(_sessionKeyPrefix.length);
              await destroySession(sessionId);
            }
          }
        }
      }
    } catch (e) {
      AppLogger.e('Session cleanup error', e);
    }
  }

  /// Get session statistics
  static Future<Map<String, dynamic>> getSessionStatistics() async {
    try {
      final sessions = await getActiveSessions();
      final licenseManager = LicenseManager();
      final license = await licenseManager.getCurrentLicense();

      final now = DateTime.now();
      final recentSessions = sessions.where((session) {
        final lastActivity = DateTime.parse(session['last_activity'] as String);
        return now.difference(lastActivity) < Duration(hours: 1);
      }).length;

      return {
        'active_sessions': sessions.length,
        'max_users': license?.maxUsers ?? 0,
        'recent_activity': recentSessions,
        'license_type': license?.licenseType ?? 'none',
        'utilization_percent': license != null
            ? ((sessions.length / license.maxUsers) * 100).toStringAsFixed(1)
            : '0',
        'sessions': sessions
            .map(
              (session) => {
                'username': session['username'],
                'user_id': session['user_id'],
                'created_at': session['created_at'],
                'last_activity': session['last_activity'],
                'session_duration': _calculateSessionDuration(
                  session['created_at'] as String,
                ),
              },
            )
            .toList(),
      };
    } catch (e) {
      AppLogger.e('Session statistics error', e);
      return {};
    }
  }

  /// Generate unique session ID
  static String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999);
    final data = '$timestamp-$random';
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 32);
  }

  /// Add session to active list
  static Future<void> _addActiveSession(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeSessions = prefs.getStringList(_activeSessionsKey) ?? [];

      if (!activeSessions.contains(sessionId)) {
        activeSessions.add(sessionId);
        await prefs.setStringList(_activeSessionsKey, activeSessions);
      }
    } catch (e) {
      AppLogger.e('Error adding active session', e);
    }
  }

  /// Remove session from active list
  static Future<void> _removeActiveSession(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeSessions = prefs.getStringList(_activeSessionsKey) ?? [];

      activeSessions.remove(sessionId);
      await prefs.setStringList(_activeSessionsKey, activeSessions);
    } catch (e) {
      AppLogger.e('Error removing active session', e);
    }
  }

  /// Calculate session duration
  static String _calculateSessionDuration(String createdAt) {
    try {
      final created = DateTime.parse(createdAt);
      final duration = DateTime.now().difference(created);

      if (duration.inHours > 0) {
        return '${duration.inHours}h ${duration.inMinutes % 60}m';
      } else {
        return '${duration.inMinutes}m';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}
