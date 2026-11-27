import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'auth_service.dart';
import 'media_upload_queue_service.dart';
import 'preferences_service.dart';

class FieldLogConnector extends PowerSyncBackendConnector {
  static const _httpTimeout = Duration(seconds: 30);
  static const _maxRetries = 3;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    try {
      await AuthService.ensureFreshToken();
    } catch (_) {
      return null;
    }

    final token = await AuthService.getToken();
    if (token == null) return null;

    final powerSyncUrl = await PreferencesService.getPowerSyncUrl();
    final endpoint =
        powerSyncUrl.endsWith('/') ? powerSyncUrl : '$powerSyncUrl/';

    return PowerSyncCredentials(endpoint: endpoint, token: token);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    try {
      await AuthService.ensureFreshToken();
    } catch (_) {
      return;
    }
    final token = await AuthService.getToken();
    final serverUrl = await PreferencesService.getServerUrl();

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    var syncedSubmission = false;
    var enqueuedLegacyMedia = false;

    for (final op in transaction.crud) {
      if (op.table == 'fieldlog_submission') {
        syncedSubmission = true;
        if (op.op != UpdateType.put) continue;

        final record = op.opData;
        final sessionId = record?['session_id'];

        dynamic parsedData;
        try {
          parsedData = jsonDecode(record?['data'] as String? ?? '{}');
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[PowerSync] Skipping record ${op.id} — malformed JSON data: $e',
            );
          }
          await Sentry.captureMessage(
            'PowerSync skipped record due to malformed JSON data',
            level: SentryLevel.warning,
            withScope: (scope) => scope.setTag('op_id', op.id),
          );
          continue;
        }

        if (parsedData is Map<String, dynamic>) {
          final migrated = await _migrateLegacyPendingFiles(
            parsedData,
            submissionId: op.id,
            sessionId: (sessionId as num?)?.toInt() ?? 0,
          );
          if (migrated) enqueuedLegacyMedia = true;
        }

        final url = Uri.parse('$serverUrl/api/sessions/$sessionId/submissions/');
        final body = jsonEncode({
          'id': op.id,
          'submitted_by': record?['submitted_by'] ?? 'Anonymous',
          'data': parsedData,
        });

        await _postWithRetry(
          opId: op.id,
          url: url,
          headers: headers,
          body: body,
        );
      } else if (op.table == 'fieldlog_sessionsubscription') {
        final sessionId = op.op == UpdateType.delete
            ? int.tryParse(op.id)
            : int.tryParse(op.opData?['session_id']?.toString() ?? '');
        if (sessionId == null) continue;

        final url = Uri.parse('$serverUrl/api/sessions/$sessionId/subscribe/');
        await _subscriptionWithRetry(
          opId: op.id,
          url: url,
          headers: headers,
          isDelete: op.op == UpdateType.delete,
        );
      }
    }

    await transaction.complete();
    if (syncedSubmission || enqueuedLegacyMedia) {
      MediaUploadQueueService.trigger();
    }
  }

  Future<bool> _migrateLegacyPendingFiles(
    Map<String, dynamic> data, {
    required String submissionId,
    required int sessionId,
  }) async {
    final items = await MediaUploadQueueService.extractSubmissionMedia(
      data,
      submissionId: submissionId,
      sessionId: sessionId,
      deterministicId: true,
      throwOnUnsupported: false,
    );
    for (final item in items) {
      await MediaUploadQueueService.enqueueItem(
        item,
        triggerUpload: false,
        ifAbsent: true,
      );
    }
    return items.isNotEmpty;
  }

  Future<void> _refreshAuthHeader(Map<String, String> headers) async {
    try {
      final refreshed = await AuthService.refreshAccessToken();
      headers['Authorization'] = 'Bearer $refreshed';
    } catch (_) {}
  }

  Future<void> _postWithRetry({
    required String opId,
    required Uri url,
    required Map<String, String> headers,
    required String body,
  }) async {
    var attempt = 0;
    final requestHeaders = Map<String, String>.from(headers);
    final client = SentryHttpClient();
    try {
      while (true) {
        attempt++;
        try {
          final response = await client
              .post(url, headers: requestHeaders, body: body)
              .timeout(_httpTimeout);

          // 200 = idempotent duplicate, 201 = new, 409 = already exists
          if (response.ok || response.statusCode == 409) return;

          if (MediaUploadQueueWorker.isPermanentClientStatus(
            response.statusCode,
          )) {
            await Sentry.captureMessage(
              'Submission rejected (${response.statusCode}) for record $opId, skipping',
              level: SentryLevel.error,
              withScope: (scope) {
                scope.setTag('op_id', opId);
                scope.setTag('http_status', response.statusCode.toString());
              },
            );
            return;
          }

          if (response.statusCode == 401) {
            await _refreshAuthHeader(requestHeaders);
          }

          if (attempt >= _maxRetries) {
            final error = Exception(
              'Submission upload failed after $_maxRetries attempts (${response.statusCode}) for record $opId',
            );
            await Sentry.captureException(
              error,
              withScope: (scope) {
                scope.setTag('op_id', opId);
                scope.setTag('http_status', response.statusCode.toString());
              },
            );
            throw error;
          }

          if (kDebugMode) {
            debugPrint(
              '[PowerSync] Transient ${response.statusCode} on attempt $attempt for $opId, retrying...',
            );
          }
        } on TimeoutException {
          if (attempt >= _maxRetries) {
            final error = Exception(
              'Submission upload timed out after $_maxRetries attempts for record $opId.',
            );
            await Sentry.captureException(
              error,
              withScope: (scope) => scope.setTag('op_id', opId),
            );
            throw error;
          }
        }

        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    } finally {
      client.close();
    }
  }

  Future<void> _subscriptionWithRetry({
    required String opId,
    required Uri url,
    required Map<String, String> headers,
    required bool isDelete,
  }) async {
    var attempt = 0;
    final requestHeaders = Map<String, String>.from(headers);
    final client = SentryHttpClient();
    try {
      while (true) {
        attempt++;
        try {
          final response = isDelete
              ? await client.delete(url, headers: requestHeaders).timeout(_httpTimeout)
              : await client.post(url, headers: requestHeaders).timeout(_httpTimeout);

          if (response.ok ||
              response.statusCode == 204 ||
              (isDelete && response.statusCode == 404)) {
            return;
          }

          if (MediaUploadQueueWorker.isPermanentClientStatus(
            response.statusCode,
          )) {
            await Sentry.captureMessage(
              'Subscription upload rejected (${response.statusCode}) for op $opId, skipping',
              level: SentryLevel.warning,
              withScope: (scope) {
                scope.setTag('op_id', opId);
                scope.setTag('http_status', response.statusCode.toString());
              },
            );
            return;
          }

          if (response.statusCode == 401) {
            await _refreshAuthHeader(requestHeaders);
          }

          if (attempt >= _maxRetries) {
            throw Exception(
              'Subscription upload failed after $_maxRetries attempts for op $opId',
            );
          }
        } on TimeoutException {
          if (attempt >= _maxRetries) {
            throw Exception(
              'Subscription upload timed out after $_maxRetries attempts for op $opId',
            );
          }
        }

        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    } finally {
      client.close();
    }
  }
}

extension on http.Response {
  bool get ok => statusCode >= 200 && statusCode < 300;
}
