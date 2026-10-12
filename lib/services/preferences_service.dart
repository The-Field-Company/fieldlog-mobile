import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';

class PreferencesService {
  static const _serverUrlKey = 'server_url';
  static const _defaultServerUrl = String.fromEnvironment('SERVER_URL');
  static const _powerSyncUrlKey = 'powersync_url';
  static const _defaultPowerSyncUrl = String.fromEnvironment('POWERSYNC_URL');
  static const _cachedSessionKey = 'cached_session';

  static Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey) ?? _defaultServerUrl;
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url);
  }

  static Future<String> getPowerSyncUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_powerSyncUrlKey) ?? _defaultPowerSyncUrl;
  }

  static Future<void> setPowerSyncUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_powerSyncUrlKey, url);
  }

  static Future<void> cacheSession(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedSessionKey, jsonEncode(session.toJson()));
  }

  static Future<Session?> getCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedSessionKey);
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) debugPrint('[PreferencesService] Failed to restore cached session: $e');
      return null;
    }
  }

  static Future<void> clearCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedSessionKey);
  }
}
