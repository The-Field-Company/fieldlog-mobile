import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';

enum MediaUploadNetworkPolicy {
  anyNetwork,
  wifiOnlyLarge,
  wifiOnlyAll;

  String get storageKey => switch (this) {
        MediaUploadNetworkPolicy.anyNetwork => 'any',
        MediaUploadNetworkPolicy.wifiOnlyLarge => 'wifi_large',
        MediaUploadNetworkPolicy.wifiOnlyAll => 'wifi_all',
      };

  static MediaUploadNetworkPolicy fromStorageKey(String? raw) => switch (raw) {
        'wifi_large' => MediaUploadNetworkPolicy.wifiOnlyLarge,
        'wifi_all' => MediaUploadNetworkPolicy.wifiOnlyAll,
        _ => MediaUploadNetworkPolicy.anyNetwork,
      };
}

class PreferencesService {
  static const _serverUrlKey = 'server_url';
  static const _defaultServerUrl = String.fromEnvironment('SERVER_URL');
  static const _tusUrlKey = 'tus_url';
  static const _defaultTusUrl = String.fromEnvironment('TUS_URL');
  static const _powerSyncUrlKey = 'powersync_url';
  static const _defaultPowerSyncUrl = String.fromEnvironment('POWERSYNC_URL');
  static const _cachedSessionKey = 'cached_session';
  static const _mediaPolicyKey = 'media_upload_network_policy';
  static const _lowCoverageModeKey = 'low_coverage_mode';

  static final ValueNotifier<MediaUploadNetworkPolicy> mediaPolicyNotifier =
      ValueNotifier<MediaUploadNetworkPolicy>(
    MediaUploadNetworkPolicy.anyNetwork,
  );

  static final ValueNotifier<bool> lowCoverageModeNotifier =
      ValueNotifier<bool>(false);

  static Future<bool> getLowCoverageMode() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_lowCoverageModeKey) ?? false;
    lowCoverageModeNotifier.value = enabled;
    return enabled;
  }

  static Future<void> setLowCoverageMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lowCoverageModeKey, enabled);
    lowCoverageModeNotifier.value = enabled;
  }

  static Future<String> getTusUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getString(_tusUrlKey);
    if (override != null && override.isNotEmpty) return override;
    if (_defaultTusUrl.isNotEmpty) return _defaultTusUrl;
    final serverUrl = await getServerUrl();
    if (serverUrl.isEmpty) return '';
    final normalized = serverUrl.replaceAll(RegExp(r'/+$'), '');
    return '$normalized/tus/';
  }

  static Future<void> setTusUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tusUrlKey, url);
  }

  static Future<MediaUploadNetworkPolicy> getMediaUploadPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final policy = MediaUploadNetworkPolicy.fromStorageKey(
      prefs.getString(_mediaPolicyKey),
    );
    mediaPolicyNotifier.value = policy;
    return policy;
  }

  static Future<void> setMediaUploadPolicy(
    MediaUploadNetworkPolicy policy,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mediaPolicyKey, policy.storageKey);
    mediaPolicyNotifier.value = policy;
  }

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
