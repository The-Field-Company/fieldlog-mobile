import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'connectivity_service.dart';
import 'preferences_service.dart';

class AppVersionService {
  static const defaultUpdateUrl =
      'https://github.com/The-Field-Company/fieldlog-mobile/releases/latest';
  static const unsupportedCode = 'app_version_unsupported';
  static const _httpTimeout = Duration(seconds: 10);

  static String _version = '';
  static String updateUrl = defaultUpdateUrl;
  static final updateRequired = ValueNotifier<bool>(false);
  static final updateAvailable = ValueNotifier<bool>(false);

  static String get version => _version;

  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
    } catch (_) {
      _version = '';
    }
  }

  static Map<String, String> get headers =>
      _version.isEmpty ? const {} : {'X-App-Version': _version};

  static bool isUnsupportedResponse(int statusCode, String body) {
    if (statusCode != 426) return false;
    try {
      final json = jsonDecode(body);
      return json is Map && json['code'] == unsupportedCode;
    } catch (_) {
      return false;
    }
  }

  static bool handleResponse(int statusCode, String body) {
    if (!isUnsupportedResponse(statusCode, body)) return false;
    try {
      final json = jsonDecode(body) as Map;
      _setUpdateUrl(json['update_url']);
    } catch (_) {}
    updateAvailable.value = false;
    updateRequired.value = true;
    return true;
  }

  static Future<void> check() async {
    if (_version.isEmpty || !ConnectivityService.isOnline) return;
    try {
      final serverUrl = await PreferencesService.getServerUrl();
      final response = await http
          .get(Uri.parse('$serverUrl/api/app-version/'), headers: headers)
          .timeout(_httpTimeout);
      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _setUpdateUrl(json['update_url']);
      final min = (json['min_version'] as String?) ?? '';
      final latest = (json['latest_version'] as String?) ?? '';
      final required = min.isNotEmpty && compareVersions(_version, min) < 0;
      updateRequired.value = required;
      updateAvailable.value =
          !required && latest.isNotEmpty && compareVersions(_version, latest) < 0;
    } catch (_) {}
  }

  static Future<void> openUpdatePage() async {
    final uri = Uri.tryParse(updateUrl) ?? Uri.parse(defaultUpdateUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  static void _setUpdateUrl(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      updateUrl = value.trim();
    }
  }

  static int compareVersions(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    final length = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }

  static List<int> _parse(String value) {
    final core = value.trim().split('+').first.split('-').first;
    return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  }
}
