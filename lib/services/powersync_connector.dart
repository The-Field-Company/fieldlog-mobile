import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'api_service.dart';
import 'app_version_service.dart';
import 'auth_service.dart';
import 'preferences_service.dart';
import 'sync_error_service.dart';
import '../utils/attachment_accepts.dart';

/// PowerSync backend connector mirroring ui/src/services/powersync/connector.js
class _StreamingFileRequest extends http.BaseRequest {
  final File file;
  final VoidCallback? onActivity;

  _StreamingFileRequest(
    super.method,
    super.url,
    this.file, {
    this.onActivity,
  });

  @override
  http.ByteStream finalize() {
    super.finalize();
    final stream = file.openRead().map((chunk) {
      onActivity?.call();
      return chunk;
    });
    return http.ByteStream(stream);
  }
}

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
    final endpoint = powerSyncUrl.endsWith('/') ? powerSyncUrl : '$powerSyncUrl/';

    return PowerSyncCredentials(
      endpoint: endpoint,
      token: token,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;
    if (AppVersionService.updateRequired.value) return;

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
      ...AppVersionService.headers,
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
          if (kDebugMode) {
            debugPrint('[PowerSync] Keeping record ${op.id} locally — malformed JSON data: $e');
          }
          await Sentry.captureMessage(
            'PowerSync kept record locally due to malformed JSON data',
            level: SentryLevel.warning,
            withScope: (scope) => scope.setTag('op_id', op.id),
          );
          await _saveRejected(
            database,
            id: op.id,
            sessionId: sessionId,
            submittedBy: record?['submitted_by'],
            data: record?['data']?.toString() ?? '',
          );
          continue;
        }

        List<String> filesToDelete = [];
        if (parsedData is Map<String, dynamic>) {
          filesToDelete = await _uploadPendingFiles(parsedData, sessionId);
        }

        final url = Uri.parse('$serverUrl/api/sessions/$sessionId/submissions/');
        final body = jsonEncode({
          'id': op.id,
          'submitted_by': record?['submitted_by'] ?? 'Anonymous',
          'data': parsedData,
        });

        // M2: retry transient failures (timeout, 5xx) with exponential backoff.
        // Permanent failures (4xx) are reported to Sentry and kept locally in
        // rejected_submissions so they can't block the FIFO upload queue.
        // After all retries exhausted, throw so PowerSync retries the whole
        // transaction on the next sync cycle.
        final rejection = await _postWithRetry(
          opId: op.id,
          url: url,
          headers: headers,
          body: body,
        );

        if (rejection != null) {
          await _saveRejected(
            database,
            id: op.id,
            sessionId: sessionId,
            submittedBy: record?['submitted_by'],
            data: jsonEncode(parsedData),
            httpStatus: rejection.statusCode,
            responseBody: rejection.body,
          );
          continue;
        }

        for (final path in filesToDelete) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
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
    }

    await transaction.complete();
  }

  /// POST with exponential backoff for transient errors.
  /// Retries on: network timeout, 5xx server errors.
  /// Throws on: 426 unsupported app version and 401, so the record stays queued.
  /// Returns the response on other 4xx client errors (permanent) so the
  /// caller can keep the record locally. Returns null on success.
  /// After [_maxRetries] attempts, throws to let PowerSync handle the retry.
  static const _maxRetries = 3;
  static const _binaryUploadTimeout = Duration(seconds: 300);
  static const _uploadStallTimeout = Duration(seconds: 60);
  // Minimum sustained upload rate (~512 kbit/s) used to scale the total
  // deadline so progressing large uploads on slow field links can finish.
  static const _minUploadBytesPerSecond = 64 * 1024;
  static const _uploadDeadlineOverhead = Duration(seconds: 120);

  @visibleForTesting
  static Duration totalUploadDeadlineForBytes(int contentLength) {
    final transferSeconds = contentLength > 0
        ? (contentLength / _minUploadBytesPerSecond).ceil()
        : 0;
    final computed =
        Duration(seconds: transferSeconds) + _uploadDeadlineOverhead;
    return computed > _binaryUploadTimeout ? computed : _binaryUploadTimeout;
  }

  /// Executes a single backpressure-aware streaming PUT attempt guarded by both
  /// an inactivity [stallTimeout] (reset on every streamed request/response
  /// chunk and header arrival) and an overall [totalDeadline].
  /// Closes [client] before completing with [TimeoutException] or returning.
  @visibleForTesting
  static Future<int> sendStreamingPutAttempt({
    required http.Client client,
    required Uri url,
    required File file,
    required int contentLength,
    required String contentType,
    Duration stallTimeout = _uploadStallTimeout,
    Duration? totalDeadline,
  }) async {
    final deadline = totalDeadline ?? totalUploadDeadlineForBytes(contentLength);
    final timeoutCompleter = Completer<Never>();
    Timer? stallTimer;
    Timer? totalTimer;

    void failWithTimeout(String reason, Duration duration) {
      if (!timeoutCompleter.isCompleted) {
        timeoutCompleter.completeError(TimeoutException(reason, duration));
      }
      client.close();
    }

    void resetStallTimer() {
      stallTimer?.cancel();
      if (timeoutCompleter.isCompleted) return;
      stallTimer = Timer(
        stallTimeout,
        () => failWithTimeout(
          'Upload stalled for ${stallTimeout.inSeconds}s',
          stallTimeout,
        ),
      );
    }

    totalTimer = Timer(
      deadline,
      () => failWithTimeout(
        'Upload exceeded total deadline of ${deadline.inSeconds}s',
        deadline,
      ),
    );
    resetStallTimer();

    try {
      final attemptFuture = () async {
        final request = _StreamingFileRequest(
          'PUT',
          url,
          file,
          onActivity: resetStallTimer,
        )
          ..headers['Content-Type'] = contentType
          ..contentLength = contentLength;
        final streamedResponse = await client.send(request);
        resetStallTimer();
        await streamedResponse.stream
            .listen((_) => resetStallTimer(), cancelOnError: true)
            .asFuture<void>();
        return streamedResponse.statusCode;
      }();
      // Avoid unhandled async errors if the underlying socket errors after
      // timing out and closing the client.
      attemptFuture.ignore();
      timeoutCompleter.future.ignore();
      return await Future.any<int>([attemptFuture, timeoutCompleter.future]);
    } finally {
      stallTimer?.cancel();
      totalTimer.cancel();
      client.close();
    }
  }

  Future<List<String>> _uploadPendingFiles(
    Map<String, dynamic> data,
    dynamic sessionId,
  ) async {
    final toDelete = <String>[];
    for (final fieldKey in data.keys.toList()) {
      final value = data[fieldKey];
      if (value is! Map<String, dynamic> || !value.containsKey('file_path')) {
        continue;
      }

      final filePath = value['file_path'] as String? ?? '';
      final fileName = value['file_name'] as String? ?? '';
      final originalName = value['original_name'] as String? ?? fileName;
      final fileSize = value['file_size'] as int?;

      final file = File(filePath);
      if (!await file.exists()) {
        await Sentry.captureMessage(
          'PowerSync upload: local file missing, dropping field',
          level: SentryLevel.error,
          withScope: (scope) {
            scope.setTag('field', fieldKey);
            scope.setTag('file_path', filePath);
          },
        );
        data.remove(fieldKey);
        continue;
      }

      final ext = extensionOf(fileName.isNotEmpty ? fileName : filePath);
      final contentType = mimeForExtension(ext);
      final attachmentLabel = isAudioPath(fileName.isNotEmpty ? fileName : filePath)
          ? 'An audio recording'
          : 'A photo';
      if (contentType == null) {
        await Sentry.captureMessage(
          'PowerSync upload: unsupported file extension, dropping field',
          level: SentryLevel.error,
          withScope: (scope) {
            scope.setTag('field', fieldKey);
            scope.setTag('ext', ext);
          },
        );
        SyncErrorService.report(
          'An attachment could not be uploaded — unsupported file type (.$ext). '
          'The submission will be sent without it.',
        );
        data.remove(fieldKey);
        continue;
      }

      final actualSize = await file.length();
      final presign = await ApiService.presignUpload(
        fileName: originalName.isNotEmpty ? originalName : fileName,
        contentType: contentType,
        sessionId: sessionId?.toString(),
      );
      final uploadUrl = presign['upload_url'] as String;
      final attachmentId = presign['attachment_id'] as String;

      try {
        await _putWithRetry(
          url: Uri.parse(uploadUrl),
          file: file,
          contentLength: actualSize,
          contentType: contentType,
          fileName: fileName,
        );
        await ApiService.confirmUpload(
          attachmentId: attachmentId,
          sessionId: sessionId?.toString(),
        );
      } on SocketException {
        rethrow;
      } on Exception {
        SyncErrorService.report(
          '$attachmentLabel in your submission could not be uploaded. '
          'It will retry automatically.',
        );
        rethrow;
      }

      data[fieldKey] = [
        {
          'name': originalName,
          'attachment_id': attachmentId,
          'type': contentType,
          'size': fileSize ?? actualSize,
        },
      ];

      toDelete.add(filePath);
    }
    return toDelete;
  }

  Future<void> _saveRejected(
    PowerSyncDatabase database, {
    required String id,
    required dynamic sessionId,
    required dynamic submittedBy,
    required String data,
    int? httpStatus,
    String? responseBody,
  }) async {
    final trimmedBody = responseBody != null && responseBody.length > 2000
        ? responseBody.substring(0, 2000)
        : responseBody;
    await database.execute(
      'INSERT OR REPLACE INTO rejected_submissions'
      ' (id, session_id, submitted_by, data, http_status, response_body, rejected_at)'
      ' VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        sessionId,
        submittedBy,
        data,
        httpStatus,
        trimmedBody,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Future<http.Response?> _postWithRetry({
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
        if (response.ok || response.statusCode == 409) return null;

        if (AppVersionService.handleResponse(response.statusCode, response.body)) {
          throw Exception('App version unsupported, upload paused for record $opId');
        }

        if (response.statusCode == 401) {
          throw Exception('Upload unauthorized (401) for record $opId. Will retry on next sync.');
        }

        if (response.statusCode >= 400 && response.statusCode < 500) {
          await Sentry.captureMessage(
            'Upload rejected (${response.statusCode}) for record $opId, kept on device',
            level: SentryLevel.error,
            withScope: (scope) {
              scope.setTag('op_id', opId);
              scope.setTag('http_status', response.statusCode.toString());
            },
          );
          return response;
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

  /// Stream file to R2 with retry for transient errors.
  /// Throws immediately on SocketException (offline) so PowerSync can
  /// re-trigger uploadData once connectivity is restored.
  Future<void> _putWithRetry({
    required Uri url,
    required File file,
    required int contentLength,
    required String contentType,
    required String fileName,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      final client = SentryHttpClient();
      try {
        final statusCode = await sendStreamingPutAttempt(
          client: client,
          url: url,
          file: file,
          contentLength: contentLength,
          contentType: contentType,
        );

        if (statusCode >= 200 && statusCode < 300) return;

        if (statusCode >= 400 && statusCode < 500) {
          final error = Exception(
            'R2 PUT failed permanently ($statusCode) for $fileName',
          );
          await Sentry.captureException(
            error,
            withScope: (scope) {
              scope.setTag('file_name', fileName);
              scope.setTag('http_status', statusCode.toString());
            },
          );
          throw error;
        }

        if (attempt > _maxRetries) {
          final error = Exception(
            'R2 PUT failed after $_maxRetries attempts ($statusCode) for $fileName',
          );
          await Sentry.captureException(
            error,
            withScope: (scope) {
              scope.setTag('file_name', fileName);
              scope.setTag('http_status', statusCode.toString());
            },
          );
          throw error;
        }

        if (kDebugMode) {
          debugPrint(
            '[PowerSync] R2 PUT 5xx on attempt $attempt for $fileName ($statusCode), retrying...',
          );
        }
      } on SocketException {
        // Device is offline — do not burn retry attempts.
        // PowerSync retries the transaction when connectivity is restored.
        throw Exception('R2 PUT failed: device offline ($fileName)');
      } on TimeoutException {
        if (attempt > _maxRetries) {
          final error = Exception(
            'R2 PUT timed out after $_maxRetries attempts for $fileName',
          );
          await Sentry.captureException(
            error,
            withScope: (scope) => scope.setTag('file_name', fileName),
          );
          throw error;
        }
        if (kDebugMode) {
          debugPrint(
            '[PowerSync] R2 PUT timeout on attempt $attempt for $fileName, retrying...',
          );
        }
      } finally {
        client.close();
      }

      await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
    }
  }

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

          if (response.ok ||
              response.statusCode == 204 ||
              (isDelete && response.statusCode == 404)) {
            return;
          }

          if (AppVersionService.handleResponse(response.statusCode, response.body)) {
            throw Exception('App version unsupported, subscription upload paused for op $opId');
          }

          if (response.statusCode >= 400 && response.statusCode < 500) {
            await Sentry.captureMessage(
                'Subscription upload rejected (${response.statusCode}) for op $opId, skipping',
                level: SentryLevel.warning,
                withScope: (scope) {
                  scope.setTag('op_id', opId);
                  scope.setTag('http_status', response.statusCode.toString());
                });
            return;
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
