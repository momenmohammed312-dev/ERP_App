import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GoogleDriveAuthException implements Exception {
  final String message;
  GoogleDriveAuthException(this.message);
  @override
  String toString() => message;
}

class GoogleDriveAuthService {
  static const String _keyAccessToken = 'gdrive_access_token';
  static const String _keyRefreshToken = 'gdrive_refresh_token';
  static const String _keyTokenExpiry = 'gdrive_token_expiry';
  static const String _keyUserEmail = 'gdrive_user_email';
  static const String _keyUserDisplayName = 'gdrive_user_display_name';
  static const String _keyClientId = 'gdrive_client_id';
  static const String _keyClientSecret = 'gdrive_client_secret';

  // Default fallback Desktop Client ID for MADAR ERP Desktop (can be customized per installation)
  static const String defaultClientId = '1092837465012-madar-desktop-client.apps.googleusercontent.com';
  static const String defaultClientSecret = 'GOCSPX-madar-desktop-secret';

  static final List<String> requiredScopes = [
    drive.DriveApi.driveFileScope,
    'https://www.googleapis.com/auth/userinfo.email',
  ];

  final FlutterSecureStorage _storage;
  final http.Client _baseClient;

  AutoRefreshingAuthClient? _authenticatedClient;
  String? _currentUserEmail;
  String? _currentUserDisplayName;
  bool _isInitialized = false;

  GoogleDriveAuthService({
    FlutterSecureStorage? storage,
    http.Client? httpClient,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _baseClient = httpClient ?? http.Client();

  bool get isAuthenticated => _authenticatedClient != null;
  String? get currentUserEmail => _currentUserEmail;
  String? get currentUserDisplayName => _currentUserDisplayName;
  AutoRefreshingAuthClient? get client => _authenticatedClient;

  Future<bool> isSignedIn() async {
    if (!_isInitialized) {
      await initialize();
    }
    return isAuthenticated;
  }

  Future<String?> getUserEmail() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _currentUserEmail;
  }

  Future<String?> getUserDisplayName() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _currentUserDisplayName;
  }

  // ════════════════════════════════════════════════════════════════════════
  // 1. التهيئة واستعادة الجلسة السابقة (Initialization & Session Restore)
  // ════════════════════════════════════════════════════════════════════════

  Future<bool> initialize() async {
    if (_isInitialized && _authenticatedClient != null) {
      return true;
    }

    try {
      final refreshToken = await _storage.read(key: _keyRefreshToken);
      final accessToken = await _storage.read(key: _keyAccessToken);
      final expiryStr = await _storage.read(key: _keyTokenExpiry);
      _currentUserEmail = await _storage.read(key: _keyUserEmail);
      _currentUserDisplayName = await _storage.read(key: _keyUserDisplayName);

      if (refreshToken != null && refreshToken.isNotEmpty) {
        final clientId = await getClientId();
        final clientSecret = await getClientSecret();
        final id = ClientId(clientId, clientSecret);

        final tokenType = 'Bearer';
        final expiry = expiryStr != null
            ? DateTime.tryParse(expiryStr) ?? DateTime.now().toUtc()
            : DateTime.now().toUtc();

        final credentials = AccessCredentials(
          AccessToken(tokenType, accessToken ?? '', expiry),
          refreshToken,
          requiredScopes,
        );

        _authenticatedClient = autoRefreshingClient(
          id,
          credentials,
          _baseClient,
        );

        _isInitialized = true;
        return true;
      }
    } catch (e) {
      debugPrint('Google Drive session restore notice: $e');
    }

    _isInitialized = true;
    return false;
  }

  // ════════════════════════════════════════════════════════════════════════
  // 2. تسجيل الدخول وربط حساب العميل (Interactive Sign-In / OAuth 2.0 PKCE)
  // ════════════════════════════════════════════════════════════════════════

  Future<bool> signIn({
    void Function(String authUrl)? onPromptUrl,
  }) async {
    try {
      final clientId = await getClientId();
      final clientSecret = await getClientSecret();
      final id = ClientId(clientId, clientSecret);

      // Loopback authentication on localhost
      final authClient = await clientViaUserConsent(
        id,
        requiredScopes,
        (url) async {
          debugPrint('🌐 يرجى فتح الرابط لتسجيل الدخول بجوجل: $url');
          if (onPromptUrl != null) {
            onPromptUrl(url);
          } else {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
        baseClient: _baseClient,
      );

      _authenticatedClient = authClient;

      // حفظ الرموز بأمان في خزنة النظام
      final creds = authClient.credentials;
      await _saveCredentials(creds);

      // استخراج معلومات حساب العميل
      await _fetchUserInfo(authClient);

      return true;
    } catch (e) {
      debugPrint('❌ فشل تسجيل الدخول بجوجل: $e');
      throw GoogleDriveAuthException('تعذر ربط حساب Google Drive: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 3. تسجيل الخروج وإلغاء صلاحية الربط (Sign-Out & Token Revocation)
  // ════════════════════════════════════════════════════════════════════════

  Future<void> signOut() async {
    try {
      final token = await _storage.read(key: _keyRefreshToken) ??
          await _storage.read(key: _keyAccessToken);

      if (token != null && token.isNotEmpty) {
        // Revoke token via Google endpoint
        try {
          final revokeUri = Uri.parse('https://oauth2.googleapis.com/revoke?token=$token');
          await _baseClient.post(revokeUri);
        } catch (_) {}
      }

      _authenticatedClient?.close();
      _authenticatedClient = null;
      _currentUserEmail = null;
      _currentUserDisplayName = null;

      await _storage.delete(key: _keyAccessToken);
      await _storage.delete(key: _keyRefreshToken);
      await _storage.delete(key: _keyTokenExpiry);
      await _storage.delete(key: _keyUserEmail);
      await _storage.delete(key: _keyUserDisplayName);

      debugPrint('🔒 تم تسجيل الخروج وإلغاء ربط Google Drive بنجاح');
    } catch (e) {
      debugPrint('Notice during sign-out: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 4. إدارة إعدادات Client ID (Configurable Credentials)
  // ════════════════════════════════════════════════════════════════════════

  Future<String> getClientId() async {
    final custom = await _storage.read(key: _keyClientId);
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return defaultClientId;
  }

  Future<String> getClientSecret() async {
    final custom = await _storage.read(key: _keyClientSecret);
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return defaultClientSecret;
  }

  Future<void> setCustomClientCredentials(String clientId, String clientSecret) async {
    await _storage.write(key: _keyClientId, value: clientId.trim());
    await _storage.write(key: _keyClientSecret, value: clientSecret.trim());
  }

  // ════════════════════════════════════════════════════════════════════════
  // 5. دوال مساعدة خاصة (Private Helpers)
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _saveCredentials(AccessCredentials creds) async {
    await _storage.write(key: _keyAccessToken, value: creds.accessToken.data);
    if (creds.refreshToken != null && creds.refreshToken!.isNotEmpty) {
      await _storage.write(key: _keyRefreshToken, value: creds.refreshToken!);
    }
    await _storage.write(
      key: _keyTokenExpiry,
      value: creds.accessToken.expiry.toUtc().toIso8601String(),
    );
  }

  Future<void> _fetchUserInfo(http.Client authClient) async {
    try {
      final response = await authClient.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _currentUserEmail = data['email'] as String?;
        _currentUserDisplayName = data['name'] as String?;

        if (_currentUserEmail != null) {
          await _storage.write(key: _keyUserEmail, value: _currentUserEmail!);
        }
        if (_currentUserDisplayName != null) {
          await _storage.write(key: _keyUserDisplayName, value: _currentUserDisplayName!);
        }
      }
    } catch (e) {
      debugPrint('Notice: Failed to fetch user profile info: $e');
    }
  }

  @visibleForTesting
  void setMockClient(AutoRefreshingAuthClient client, {String? email, String? name}) {
    _authenticatedClient = client;
    _currentUserEmail = email ?? 'test-customer@gmail.com';
    _currentUserDisplayName = name ?? 'عميل تجريبي';
    _isInitialized = true;
  }
}
