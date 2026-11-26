import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import '../models/session.dart';
import 'preferences_service.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  static const _httpTimeout = Duration(seconds: 30);

  static Future<Map<String, String>> _authHeaders() async {
    final headers = <String, String>{'Accept': 'application/json'};
    final token = await AuthService.getToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<Session> getSession(String sessionId) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/sessions/$sessionId/');

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .get(url, headers: await _authHeaders())
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Request timed out. Check your connection and try again.');
    } finally {
      client.close();
    }

    if (response.statusCode == 404) {
      throw ApiException('Session not found. Please check the session ID and try again.', statusCode: 404);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException('This session requires authentication.', statusCode: response.statusCode);
    }
    if (response.statusCode >= 500) {
      throw ApiException('The server is temporarily unavailable. Please try again later.', statusCode: response.statusCode);
    }
    if (response.statusCode != 200) {
      throw ApiException('Something went wrong. Please try again.', statusCode: response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return Session.fromJson(json);
  }

  static Future<List<Session>> getSubscriptions() async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/subscriptions/');

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .get(url, headers: await _authHeaders())
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Request timed out. Check your connection and try again.');
    } finally {
      client.close();
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException('Authentication required.', statusCode: response.statusCode);
    }
    if (response.statusCode >= 500) {
      throw ApiException('The server is temporarily unavailable. Please try again later.', statusCode: response.statusCode);
    }
    if (response.statusCode != 200) {
      throw ApiException('Something went wrong. Please try again.', statusCode: response.statusCode);
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => Session.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<List<Session>> getPublicSessions() async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/sessions/?is_public=true');

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .get(url, headers: await _authHeaders())
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Request timed out. Check your connection and try again.');
    } finally {
      client.close();
    }

    if (response.statusCode >= 500) {
      throw ApiException('The server is temporarily unavailable. Please try again later.', statusCode: response.statusCode);
    }
    if (response.statusCode != 200) {
      throw ApiException('Something went wrong. Please try again.', statusCode: response.statusCode);
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => Session.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> subscribeToSession(int sessionId) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/sessions/$sessionId/subscribe/');

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .post(url, headers: await _authHeaders())
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Request timed out. Check your connection and try again.');
    } finally {
      client.close();
    }

    if (response.statusCode == 403) {
      throw ApiException('This session is not open for subscriptions.', statusCode: 403);
    }
    if (response.statusCode >= 500) {
      throw ApiException('The server is temporarily unavailable. Please try again later.', statusCode: response.statusCode);
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException('Something went wrong. Please try again.', statusCode: response.statusCode);
    }
  }

  static String _errorDetail(http.Response response, String fallback) {
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map && parsed['detail'] is String) {
        return parsed['detail'] as String;
      }
    } catch (_) {}
    return fallback;
  }

  static Future<Map<String, dynamic>> initUpload({
    required String attachmentId,
    required int sessionId,
    required String fileName,
    required String contentType,
    required int fileSize,
    String? fieldKey,
  }) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/uploads/init/');

    final body = <String, dynamic>{
      'purpose': 'submission',
      'attachment_id': attachmentId,
      'session_id': sessionId,
      'filename': fileName,
      'content_type': contentType,
      'size': fileSize,
    };
    if (fieldKey != null && fieldKey.isNotEmpty) {
      body['field_key'] = fieldKey;
    }

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              ...await _authHeaders(),
            },
            body: jsonEncode(body),
          )
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Upload init timed out. Check your connection.');
    } finally {
      client.close();
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        _errorDetail(response, 'Upload not authorized.'),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 500) {
      throw ApiException(
        'Server error during upload init.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(response, 'Upload initialization failed.'),
        statusCode: response.statusCode,
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getUploadPartUrls({
    required String attachmentId,
    required List<int> partNumbers,
  }) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/uploads/$attachmentId/part-url/');

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              ...await _authHeaders(),
            },
            body: jsonEncode({'part_numbers': partNumbers}),
          )
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Fetching part URLs timed out.');
    } finally {
      client.close();
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        _errorDetail(response, 'Upload not authorized.'),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 500) {
      throw ApiException(
        'Server error fetching part URLs.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(response, 'Could not fetch part upload URLs.'),
        statusCode: response.statusCode,
      );
    }

    final parsed = jsonDecode(response.body) as Map<String, dynamic>;
    final list = parsed['part_urls'] as List<dynamic>? ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> confirmUpload({
    required String attachmentId,
    List<Map<String, dynamic>>? parts,
  }) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/uploads/$attachmentId/confirm/');

    final body = <String, dynamic>{};
    if (parts != null) body['parts'] = parts;

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              ...await _authHeaders(),
            },
            body: jsonEncode(body),
          )
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Upload confirm timed out. Check your connection.');
    } finally {
      client.close();
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        _errorDetail(response, 'Upload not authorized.'),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 500) {
      throw ApiException(
        'Server error during upload confirm.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        _errorDetail(response, 'Upload could not be confirmed.'),
        statusCode: response.statusCode,
      );
    }
  }

  static Future<Map<String, dynamic>> getInvite(String token) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/invite/$token/');

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .get(url, headers: await _authHeaders())
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Request timed out.');
    } finally {
      client.close();
    }

    if (response.statusCode == 404) throw ApiException('Invalid invite link.', statusCode: 404);
    if (response.statusCode == 410) throw ApiException('This invite link has expired.', statusCode: 410);
    if (response.statusCode != 200) throw ApiException('Something went wrong.', statusCode: response.statusCode);

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> acceptInvite(String token) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/invite/$token/accept/');

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .post(url, headers: await _authHeaders())
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Request timed out.');
    } finally {
      client.close();
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException('Authentication required.', statusCode: response.statusCode);
    }
    if (response.statusCode == 410) throw ApiException('This invite link has expired.', statusCode: 410);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException('Something went wrong.', statusCode: response.statusCode);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> unsubscribeFromSession(int sessionId) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/sessions/$sessionId/subscribe/');

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .delete(url, headers: await _authHeaders())
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Request timed out. Check your connection and try again.');
    } finally {
      client.close();
    }

    if (response.statusCode >= 500) {
      throw ApiException('The server is temporarily unavailable. Please try again later.', statusCode: response.statusCode);
    }
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException('Something went wrong. Please try again.', statusCode: response.statusCode);
    }
  }

  static Future<void> createSubmission(
    int sessionId,
    Map<String, dynamic> data, {
    String submittedBy = 'Anonymous',
  }) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/sessions/$sessionId/submissions/');

    final http.Response response;
    final client = SentryHttpClient();
    try {
      response = await client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'submitted_by': submittedBy,
              'data': data,
            }),
          )
          .timeout(_httpTimeout);
    } on TimeoutException {
      throw ApiException('Request timed out. Check your connection and try again.');
    } finally {
      client.close();
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException('This session is no longer accepting public submissions.', statusCode: response.statusCode);
    }
    if (response.statusCode == 404) {
      throw ApiException('Session not found. It may have been deleted.', statusCode: 404);
    }
    if (response.statusCode >= 500) {
      throw ApiException('The server is temporarily unavailable. Please try again later.', statusCode: response.statusCode);
    }
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw ApiException('Something went wrong. Please try again.', statusCode: response.statusCode);
    }
  }
}
