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

  static Future<Map<String, dynamic>> presignUpload({
    required String fileName,
    required String contentType,
    String? sessionId,
  }) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/uploads/presign/');

    final body = <String, dynamic>{
      'filename': fileName,
      'content_type': contentType,
    };
    if (sessionId != null) body['session_id'] = sessionId;

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
      throw ApiException('Upload presign timed out. Check your connection.');
    } finally {
      client.close();
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException('Upload not authorized.', statusCode: response.statusCode);
    }
    if (response.statusCode >= 500) {
      throw ApiException(
        'Server error during upload presign.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw ApiException('Upload presign failed.', statusCode: response.statusCode);
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> confirmUpload({
    required String attachmentId,
    String? sessionId,
  }) async {
    final serverUrl = await PreferencesService.getServerUrl();
    final url = Uri.parse('$serverUrl/api/uploads/$attachmentId/confirm/');

    final body = <String, dynamic>{};
    if (sessionId != null) body['session_id'] = sessionId;

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
      throw ApiException('Upload not authorized.', statusCode: response.statusCode);
    }
    if (response.statusCode >= 500) {
      throw ApiException(
        'Server error during upload confirm.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw ApiException('Upload could not be confirmed.', statusCode: response.statusCode);
    }
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
