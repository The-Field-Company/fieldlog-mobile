import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'connectivity_service.dart';
import 'preferences_service.dart';

class AuthService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _tokenFreshnessMs = 30000;
  static const _httpTimeout = Duration(seconds: 30);

  // Tokens are stored in the OS keychain / keystore, not plaintext SharedPreferences.
  static const _storage = FlutterSecureStorage();

  static Timer? _refreshTimer;
  static Completer<String>? _refreshCompleter;

  // M4: client-side login rate limiting (in-memory, resets on app restart).
  // Server-side rate limiting is the real security control; this improves UX.
  static int _failedLoginAttempts = 0;
  static DateTime? _loginLockedUntil;
  static const _maxLoginAttempts = 3;
  static const _loginLockoutDuration = Duration(seconds: 60);

  static Future<void> login(String username, String password) async {
    // Check lockout before attempting
    if (_loginLockedUntil != null && DateTime.now().isBefore(_loginLockedUntil!)) {
      final remaining = _loginLockedUntil!.difference(DateTime.now()).inSeconds;
      throw Exception('Too many failed attempts. Please wait $remaining seconds before trying again.');
    }

    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/token/');

    final http.Response response;
    try {
      response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw TimeoutException('Connection timed out. Check your network and server address.');
    }

    if (response.statusCode != 200) {
      _failedLoginAttempts++;
      if (_failedLoginAttempts >= _maxLoginAttempts) {
        _loginLockedUntil = DateTime.now().add(_loginLockoutDuration);
        _failedLoginAttempts = 0;
        throw Exception('Too many failed attempts. Please wait 60 seconds before trying again.');
      }
      throw Exception('Invalid username or password');
    }

    // Success — clear any previous lockout state
    _failedLoginAttempts = 0;
    _loginLockedUntil = null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _storage.write(key: _accessTokenKey, value: data['access'] as String);
    await _storage.write(key: _refreshTokenKey, value: data['refresh'] as String);

    scheduleRefresh();

    final loggedInUser = await getUsernameAsync();
    if (loggedInUser != null) {
      await Sentry.configureScope(
        (scope) => scope.setUser(SentryUser(username: loggedInUser)),
      );
    }
  }

  static Future<void> logout() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshCompleter = null;

    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);

    await Sentry.configureScope((scope) => scope.setUser(null));
  }

  static Future<String?> getToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  // H3: check both existence AND expiry so a stored-but-expired token doesn't
  // return true and cause silent 401 errors downstream.
  static Future<bool> isAuthenticated() async {
    final token = await getToken();
    if (token == null) return false;
    return getTokenExp(token) > DateTime.now().millisecondsSinceEpoch;
  }

  static Future<bool> isSessionValid() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return false;
    return getTokenExp(refreshToken) > DateTime.now().millisecondsSinceEpoch;
  }

  static int getTokenExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return 0;
      final payload = parts[1];
      // Add padding for base64
      final normalized = base64.normalize(payload);
      final decoded = utf8.decode(base64.decode(normalized));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      return ((json['exp'] as num) * 1000).toInt();
    } catch (e) {
      // H5: surface parse errors in debug so malformed tokens are not invisible
      if (kDebugMode) debugPrint('[AuthService] Failed to parse token exp: $e');
      return 0;
    }
  }

  static String? getUsername() {
    // Synchronous version using cached token — call after isAuthenticated
    return _cachedUsername;
  }

  static String? _cachedUsername;

  static Future<String?> getUsernameAsync() async {
    final token = await getToken();
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64.normalize(parts[1]);
      final decoded = utf8.decode(base64.decode(normalized));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      _cachedUsername = json['username'] as String?;
      return _cachedUsername;
    } catch (e) {
      // H5: surface parse errors in debug
      if (kDebugMode) debugPrint('[AuthService] Failed to parse username from token: $e');
      return null;
    }
  }

  static Future<void> ensureFreshToken() async {
    final token = await getToken();
    if (token == null) return;

    final remaining = getTokenExp(token) - DateTime.now().millisecondsSinceEpoch;
    if (remaining >= _tokenFreshnessMs) return;

    // If offline, skip the refresh attempt — the token will be refreshed the
    // next time this is called with connectivity (e.g. when PowerSync reconnects).
    if (!ConnectivityService.isOnline) return;

    await refreshAccessToken();
  }

  static Future<String> refreshAccessToken() async {
    // Dedupe concurrent refresh calls
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<String>();
    try {
      final result = await _doRefresh();
      _refreshCompleter!.complete(result);
      return result;
    } catch (e) {
      _refreshCompleter!.completeError(e);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  static Future<String> _doRefresh() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) {
      throw Exception('No refresh token');
    }

    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/token/refresh/');

    final http.Response response;
    try {
      response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refreshToken}),
          )
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw Exception('Token refresh timed out. Check your network connection.');
    }

    if (response.statusCode != 200) {
      throw Exception('Token refresh failed');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final newAccessToken = data['access'] as String;
    await _storage.write(key: _accessTokenKey, value: newAccessToken);

    // Some servers also rotate refresh tokens
    if (data.containsKey('refresh')) {
      await _storage.write(key: _refreshTokenKey, value: data['refresh'] as String);
    }

    // Update cached username
    await getUsernameAsync();

    scheduleRefresh();
    return newAccessToken;
  }

  static void scheduleRefresh() {
    _refreshTimer?.cancel();

    // Fire-and-forget async work inside sync method
    () async {
      final token = await getToken();
      if (token == null) return;

      final delay = getTokenExp(token) - DateTime.now().millisecondsSinceEpoch - 60000;
      _refreshTimer = Timer(
        Duration(milliseconds: delay > 0 ? delay : 0),
        () => refreshAccessToken().catchError((e, st) {
          Sentry.captureException(e, stackTrace: st is StackTrace ? st : null);
          return '';
        }),
      );
    }();
  }

  /// Call on app start to restore session state.
  ///
  /// The refresh token is the single gate: if it's present and unexpired, the
  /// user is allowed into the app regardless of whether the access token has
  /// expired. The access token will be refreshed silently on the next online
  /// interaction (e.g. when PowerSync calls fetchCredentials).
  static Future<bool> initSession() async {
    if (!await isSessionValid()) {
      await logout();
      return false;
    }
    await getUsernameAsync();
    scheduleRefresh();

    if (_cachedUsername != null) {
      await Sentry.configureScope(
        (scope) => scope.setUser(SentryUser(username: _cachedUsername)),
      );
    }
    return true;
  }
}
