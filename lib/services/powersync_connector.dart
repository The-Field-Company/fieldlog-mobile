import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'auth_service.dart';
import 'preferences_service.dart';

/// PowerSync backend connector mirroring ui/src/services/powersync/connector.js
class FieldLogConnector extends PowerSyncBackendConnector {
  static const _httpTimeout = Duration(seconds: 30);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    try {
      await AuthService.ensureFreshToken();
    } catch (e) {
      // Offline or refresh failed — return null so PowerSync pauses sync
      // and retries when credentials are next requested.
      return null;
    }

    final token = await AuthService.getToken();
    if (token == null) return null;

    final powerSyncUrl = await PreferencesService.getPowerSyncUrl();

    return PowerSyncCredentials(
      endpoint: powerSyncUrl,
      token: token,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    try {
      await AuthService.ensureFreshToken();
    } catch (e) {
      // Offline or refresh failed — leave the transaction in the queue so
      // PowerSync retries it on the next sync cycle.
      return;
    }
    final token = await AuthService.getToken();
    final serverUrl = await PreferencesService.getServerUrl();

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    for (final op in transaction.crud) {
      if (op.table == 'fieldlog_submission') {
        if (op.op != UpdateType.put) continue;

        final record = op.opData;
        final sessionId = record?['session_id'];

        dynamic parsedData;
        try {
          parsedData = jsonDecode(record?['data'] as String? ?? '{}');
        } catch (e) {
          // H4: malformed record data — log and skip rather than silently drop.
          // The transaction will still complete so PowerSync doesn't retry forever.
          if (kDebugMode) {
            debugPrint('[PowerSync] Skipping record ${op.id} — malformed JSON data: $e');
          }
          await Sentry.captureMessage(
            'PowerSync skipped record due to malformed JSON data',
            level: SentryLevel.warning,
            withScope: (scope) => scope.setTag('op_id', op.id),
          );
          continue;
        }

        final url = Uri.parse('$serverUrl/api/sessions/$sessionId/submissions/');
        final body = jsonEncode({
          'id': op.id,
          'submitted_by': record?['submitted_by'] ?? 'Anonymous',
          'data': parsedData,
        });

        // M2: retry transient failures (timeout, 5xx) with exponential backoff.
        // Permanent failures (4xx) throw immediately. After all retries exhausted,
        // throw so PowerSync retries the whole transaction on the next sync cycle.
        await _postWithRetry(
          opId: op.id,
          url: url,
          headers: headers,
          body: body,
        );
      } else if (op.table == 'fieldlog_sessionsubscription') {
        // id is always session_id.toString() (set by the client), so we can
        // recover the session id from op.id for both PUT and DELETE ops.
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
      // All other tables (e.g. fieldlog_session) are server-managed; local
      // writes are optimistic only and do not need to be uploaded.
    }

    await transaction.complete();
  }

  /// POST with exponential backoff for transient errors.
  /// Retries on: network timeout, 5xx server errors.
  /// Throws immediately on: 4xx client errors (permanent).
  /// After [_maxRetries] attempts, throws to let PowerSync handle the retry.
  static const _maxRetries = 3;

  Future<void> _postWithRetry({
    required String opId,
    required Uri url,
    required Map<String, String> headers,
    required String body,
  }) async {
    int attempt = 0;
    final client = SentryHttpClient();
    try {
    while (true) {
      attempt++;
      try {
        final response = await client
            .post(url, headers: headers, body: body)
            .timeout(_httpTimeout);

        // 200 = idempotent duplicate, 201 = new, 409 = conflict (also OK)
        if (response.ok || response.statusCode == 409) return;

        // 4xx = permanent failure (bad request, auth, not found) — don't retry
        if (response.statusCode >= 400 && response.statusCode < 500) {
          final error = Exception('Upload failed (${response.statusCode}) for record $opId: ${response.body}');
          await Sentry.captureException(
            error,
            withScope: (scope) {
              scope.setTag('op_id', opId);
              scope.setTag('http_status', response.statusCode.toString());
            },
          );
          throw error;
        }

        // 5xx = transient server error — fall through to retry logic below
        if (attempt > _maxRetries) {
          final error = Exception('Upload failed after $_maxRetries attempts (${response.statusCode}) for record $opId');
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
          debugPrint('[PowerSync] 5xx on attempt $attempt for $opId (${response.statusCode}), retrying...');
        }
      } on TimeoutException {
        if (attempt > _maxRetries) {
          final error = Exception('Upload timed out after $_maxRetries attempts for record $opId. Will retry on next sync.');
          await Sentry.captureException(
            error,
            withScope: (scope) => scope.setTag('op_id', opId),
          );
          throw error;
        }
        if (kDebugMode) {
          debugPrint('[PowerSync] Timeout on attempt $attempt for $opId, retrying...');
        }
      }

      // Exponential backoff: 1 s, 2 s, 4 s
      await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
    }
    } finally {
      client.close();
    }
  }

  /// Subscribe / unsubscribe with the same retry logic as [_postWithRetry].
  /// Uses POST for subscribe (no body) and DELETE for unsubscribe.
  Future<void> _subscriptionWithRetry({
    required String opId,
    required Uri url,
    required Map<String, String> headers,
    required bool isDelete,
  }) async {
    int attempt = 0;
    final client = SentryHttpClient();
    try {
      while (true) {
        attempt++;
        try {
          final response = isDelete
              ? await client.delete(url, headers: headers).timeout(_httpTimeout)
              : await client.post(url, headers: headers).timeout(_httpTimeout);

          // POST: 200 = already subscribed, 201 = new subscription
          // DELETE: 200/204 = deleted, 404 = already gone (treat as success)
          if (response.ok ||
              response.statusCode == 204 ||
              (isDelete && response.statusCode == 404)) return;

          if (response.statusCode >= 400 && response.statusCode < 500) {
            final error = Exception(
                'Subscription upload failed (${response.statusCode}) for op $opId');
            await Sentry.captureException(error,
                withScope: (scope) {
                  scope.setTag('op_id', opId);
                  scope.setTag('http_status', response.statusCode.toString());
                });
            throw error;
          }

          if (attempt > _maxRetries) {
            throw Exception(
                'Subscription upload failed after $_maxRetries attempts for op $opId');
          }

          if (kDebugMode) {
            debugPrint(
                '[PowerSync] 5xx on attempt $attempt for subscription $opId, retrying...');
          }
        } on TimeoutException {
          if (attempt > _maxRetries) {
            throw Exception(
                'Subscription upload timed out after $_maxRetries attempts for op $opId');
          }
          if (kDebugMode) {
            debugPrint(
                '[PowerSync] Timeout on attempt $attempt for subscription $opId, retrying...');
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
