import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:uuid/uuid.dart';

import '../utils/attachment_accepts.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';
import 'preferences_service.dart';
import 'sync_error_service.dart';

class MediaUploadStatus {
  static const queued = 'queued';
  static const uploading = 'uploading';
  static const pausedWifi = 'paused_wifi';
  static const failedPermanent = 'failed_permanent';
}

class PendingUploadItem {
  final String attachmentId;
  final String submissionId;
  final int sessionId;
  final String fieldKey;
  final String localPath;
  final String originalName;
  final String contentType;
  final int fileSize;
  final String s3UploadId;
  final int partSize;
  final String completedPartsJson;
  final String status;
  final int retryCount;
  final String lastError;
  final String createdAt;

  const PendingUploadItem({
    required this.attachmentId,
    required this.submissionId,
    required this.sessionId,
    required this.fieldKey,
    required this.localPath,
    required this.originalName,
    required this.contentType,
    required this.fileSize,
    required this.s3UploadId,
    required this.partSize,
    required this.completedPartsJson,
    required this.status,
    required this.retryCount,
    required this.lastError,
    required this.createdAt,
  });

  factory PendingUploadItem.fromRow(Map<String, dynamic> row) {
    return PendingUploadItem(
      attachmentId: row['id'] as String,
      submissionId: row['submission_id'] as String? ?? '',
      sessionId: (row['session_id'] as num?)?.toInt() ?? 0,
      fieldKey: row['field_key'] as String? ?? '',
      localPath: row['local_path'] as String? ?? '',
      originalName: row['original_name'] as String? ?? '',
      contentType: row['content_type'] as String? ?? '',
      fileSize: (row['file_size'] as num?)?.toInt() ?? 0,
      s3UploadId: row['s3_upload_id'] as String? ?? '',
      partSize: (row['part_size'] as num?)?.toInt() ?? 0,
      completedPartsJson: row['completed_parts_json'] as String? ?? '[]',
      status: row['status'] as String? ?? MediaUploadStatus.queued,
      retryCount: (row['retry_count'] as num?)?.toInt() ?? 0,
      lastError: row['last_error'] as String? ?? '',
      createdAt: row['created_at'] as String? ?? '',
    );
  }

  Map<int, String> parseCompletedParts() {
    try {
      final decoded = jsonDecode(completedPartsJson);
      if (decoded is! List) return {};
      final result = <int, String>{};
      for (final entry in decoded) {
        if (entry is Map) {
          final numPart = (entry['part_number'] as num?)?.toInt();
          final etag = entry['etag'] as String?;
          if (numPart != null && numPart >= 1 && etag != null && etag.isNotEmpty) {
            result[numPart] = etag;
          }
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }
}

class PendingMediaSummary {
  final int queuedCount;
  final int uploadingCount;
  final int pausedWifiCount;
  final int failedCount;
  final String? activeFileName;
  final double? activeProgress;

  const PendingMediaSummary({
    this.queuedCount = 0,
    this.uploadingCount = 0,
    this.pausedWifiCount = 0,
    this.failedCount = 0,
    this.activeFileName,
    this.activeProgress,
  });

  int get pendingTotal => queuedCount + uploadingCount + pausedWifiCount;
  bool get hasActivity => pendingTotal > 0 || failedCount > 0;
  bool get isUploading => uploadingCount > 0;
  bool get isPausedForWifi => pausedWifiCount > 0 && uploadingCount == 0;
}

class StreamingPutResult {
  final int statusCode;
  final String etag;
  const StreamingPutResult({required this.statusCode, required this.etag});
}

class _StreamingSliceRequest extends http.BaseRequest {
  final File file;
  final int start;
  final int end;
  final VoidCallback? onActivity;
  final void Function(int bytesSent)? onBytesSent;

  _StreamingSliceRequest(
    super.method,
    super.url,
    this.file, {
    required this.start,
    required this.end,
    this.onActivity,
    this.onBytesSent,
  });

  @override
  http.ByteStream finalize() {
    super.finalize();
    var sent = 0;
    final stream = file.openRead(start, end).map((chunk) {
      onActivity?.call();
      sent += chunk.length;
      onBytesSent?.call(sent);
      return chunk;
    });
    return http.ByteStream(stream);
  }
}

abstract class MediaUploadStore {
  Future<void> insert(PendingUploadItem item);
  Future<void> insertIfAbsent(PendingUploadItem item);
  Future<void> resetStuckUploading();
  Future<List<PendingUploadItem>> listRunnable();
  Future<List<String>> listAllLocalPaths();
  Future<bool> isSubmissionPendingSync(String submissionId);
  Future<void> updateStatus(
    String attachmentId,
    String status, {
    int? retryCount,
    String? lastError,
  });
  Future<void> saveMultipartState(
    String attachmentId, {
    required String uploadId,
    required int partSize,
    required String completedPartsJson,
  });
  Future<void> markDoneAndRemove(String attachmentId);
  Future<void> retryAllFailed();
  Future<PendingMediaSummary> readSummary({
    String? activeFileName,
    double? activeProgress,
  });
}

class PowerSyncMediaUploadStore implements MediaUploadStore {
  final PowerSyncDatabase db;
  PowerSyncMediaUploadStore(this.db);

  static const insertSql =
      'INSERT OR REPLACE INTO local_pending_uploads ('
      'id, submission_id, session_id, field_key, local_path, original_name, '
      'content_type, file_size, s3_upload_id, part_size, completed_parts_json, '
      'status, retry_count, last_error, created_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  static const insertIfAbsentSql =
      'INSERT OR IGNORE INTO local_pending_uploads ('
      'id, submission_id, session_id, field_key, local_path, original_name, '
      'content_type, file_size, s3_upload_id, part_size, completed_parts_json, '
      'status, retry_count, last_error, created_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  static List<Object?> insertArgs(PendingUploadItem item) => [
        item.attachmentId,
        item.submissionId,
        item.sessionId,
        item.fieldKey,
        item.localPath,
        item.originalName,
        item.contentType,
        item.fileSize,
        item.s3UploadId,
        item.partSize,
        item.completedPartsJson,
        item.status,
        item.retryCount,
        item.lastError,
        item.createdAt,
      ];

  @override
  Future<void> insert(PendingUploadItem item) async {
    await db.execute(insertSql, insertArgs(item));
  }

  @override
  Future<void> insertIfAbsent(PendingUploadItem item) async {
    await db.execute(insertIfAbsentSql, insertArgs(item));
  }

  @override
  Future<void> resetStuckUploading() async {
    await db.execute(
      'UPDATE local_pending_uploads SET status = ? WHERE status = ?',
      [MediaUploadStatus.queued, MediaUploadStatus.uploading],
    );
  }

  @override
  Future<List<PendingUploadItem>> listRunnable() async {
    final rows = await db.getAll(
      'SELECT * FROM local_pending_uploads '
      'WHERE status IN (?, ?) '
      'ORDER BY file_size ASC, created_at ASC',
      [MediaUploadStatus.queued, MediaUploadStatus.pausedWifi],
    );
    return rows.map((r) => PendingUploadItem.fromRow(Map<String, dynamic>.from(r))).toList();
  }

  @override
  Future<List<String>> listAllLocalPaths() async {
    final rows = await db.getAll(
      'SELECT local_path FROM local_pending_uploads',
    );
    return [
      for (final row in rows)
        if ((row['local_path'] as String?)?.isNotEmpty == true)
          row['local_path'] as String,
    ];
  }

  @override
  Future<bool> isSubmissionPendingSync(String submissionId) async {
    if (submissionId.isEmpty) return false;
    try {
      final rows = await db.getAll(
        r"SELECT 1 FROM ps_crud WHERE json_extract(data, '$.type') = 'fieldlog_submission' AND json_extract(data, '$.id') = ? LIMIT 1",
        [submissionId],
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> updateStatus(
    String attachmentId,
    String status, {
    int? retryCount,
    String? lastError,
  }) async {
    if (retryCount != null && lastError != null) {
      await db.execute(
        'UPDATE local_pending_uploads SET status = ?, retry_count = ?, last_error = ? WHERE id = ?',
        [status, retryCount, lastError, attachmentId],
      );
    } else if (retryCount != null) {
      await db.execute(
        'UPDATE local_pending_uploads SET status = ?, retry_count = ? WHERE id = ?',
        [status, retryCount, attachmentId],
      );
    } else if (lastError != null) {
      await db.execute(
        'UPDATE local_pending_uploads SET status = ?, last_error = ? WHERE id = ?',
        [status, lastError, attachmentId],
      );
    } else {
      await db.execute(
        'UPDATE local_pending_uploads SET status = ? WHERE id = ?',
        [status, attachmentId],
      );
    }
  }

  @override
  Future<void> saveMultipartState(
    String attachmentId, {
    required String uploadId,
    required int partSize,
    required String completedPartsJson,
  }) async {
    await db.execute(
      'UPDATE local_pending_uploads '
      'SET s3_upload_id = ?, part_size = ?, completed_parts_json = ? '
      'WHERE id = ?',
      [uploadId, partSize, completedPartsJson, attachmentId],
    );
  }

  @override
  Future<void> markDoneAndRemove(String attachmentId) async {
    await db.execute(
      'DELETE FROM local_pending_uploads WHERE id = ?',
      [attachmentId],
    );
  }

  @override
  Future<void> retryAllFailed() async {
    await db.execute(
      'UPDATE local_pending_uploads SET status = ?, retry_count = 0, last_error = ? '
      'WHERE status = ?',
      [MediaUploadStatus.queued, '', MediaUploadStatus.failedPermanent],
    );
  }

  @override
  Future<PendingMediaSummary> readSummary({
    String? activeFileName,
    double? activeProgress,
  }) async {
    final rows = await db.getAll(
      'SELECT status, COUNT(*) AS cnt FROM local_pending_uploads GROUP BY status',
    );
    var queued = 0;
    var uploading = 0;
    var pausedWifi = 0;
    var failed = 0;
    for (final row in rows) {
      final count = (row['cnt'] as num?)?.toInt() ?? 0;
      switch (row['status'] as String?) {
        case MediaUploadStatus.queued:
          queued = count;
        case MediaUploadStatus.uploading:
          uploading = count;
        case MediaUploadStatus.pausedWifi:
          pausedWifi = count;
        case MediaUploadStatus.failedPermanent:
          failed = count;
      }
    }
    return PendingMediaSummary(
      queuedCount: queued,
      uploadingCount: uploading,
      pausedWifiCount: pausedWifi,
      failedCount: failed,
      activeFileName: uploading > 0 ? activeFileName : null,
      activeProgress: uploading > 0 ? activeProgress : null,
    );
  }
}

abstract class MediaUploadGateway {
  Future<void> ensureFreshToken();
  Future<void> forceRefreshToken();
  Future<Map<String, dynamic>> initUpload({
    required String attachmentId,
    required int sessionId,
    required String fileName,
    required String contentType,
    required int fileSize,
    String? fieldKey,
  });
  Future<List<Map<String, dynamic>>> getPartUrls({
    required String attachmentId,
    required List<int> partNumbers,
  });
  Future<void> confirmUpload({
    required String attachmentId,
    List<Map<String, dynamic>>? parts,
  });
  http.Client createHttpClient();
}

class DefaultMediaUploadGateway implements MediaUploadGateway {
  @override
  Future<void> ensureFreshToken() => AuthService.ensureFreshToken();

  @override
  Future<void> forceRefreshToken() async {
    await AuthService.refreshAccessToken();
  }

  @override
  Future<Map<String, dynamic>> initUpload({
    required String attachmentId,
    required int sessionId,
    required String fileName,
    required String contentType,
    required int fileSize,
    String? fieldKey,
  }) =>
      ApiService.initUpload(
        attachmentId: attachmentId,
        sessionId: sessionId,
        fileName: fileName,
        contentType: contentType,
        fileSize: fileSize,
        fieldKey: fieldKey,
      );

  @override
  Future<List<Map<String, dynamic>>> getPartUrls({
    required String attachmentId,
    required List<int> partNumbers,
  }) =>
      ApiService.getUploadPartUrls(
        attachmentId: attachmentId,
        partNumbers: partNumbers,
      );

  @override
  Future<void> confirmUpload({
    required String attachmentId,
    List<Map<String, dynamic>>? parts,
  }) =>
      ApiService.confirmUpload(attachmentId: attachmentId, parts: parts);

  @override
  http.Client createHttpClient() => SentryHttpClient();
}

class _PausedForWifiException implements Exception {}

class _QueueStoppedException implements Exception {}

class _AuthUnavailableException implements Exception {}

class _TransientNetworkException implements Exception {
  final String message;
  _TransientNetworkException(this.message);
  @override
  String toString() => message;
}

class MediaUploadQueueWorker {
  static const int multipartThresholdBytes = 5 * 1024 * 1024;
  static const int partUrlBatchSize = 5;
  static const Duration _binaryUploadTimeout = Duration(seconds: 300);
  static const Duration _uploadStallTimeout = Duration(seconds: 60);
  static const int _minUploadBytesPerSecond = 4 * 1024;
  static const Duration _uploadDeadlineOverhead = Duration(seconds: 120);

  final MediaUploadStore store;
  final MediaUploadGateway gateway;
  final ConnectivityState Function() readConnectivity;
  final MediaUploadNetworkPolicy Function() readPolicy;
  final void Function(String message) reportUserError;
  final Future<void> Function(Object error, {String? attachmentId, int? statusCode}) reportError;

  final StreamController<PendingMediaSummary> _summaryController =
      StreamController<PendingMediaSummary>.broadcast();
  PendingMediaSummary _summary = const PendingMediaSummary();

  bool _stopped = false;
  bool _draining = false;
  bool _reschedule = false;
  int _transientBackoffAttempt = 0;
  http.Client? _activeClient;
  int? _activeItemFileSize;
  Future<void>? _drainFuture;
  Timer? _retryTimer;

  MediaUploadQueueWorker({
    required this.store,
    required this.gateway,
    required this.readConnectivity,
    required this.readPolicy,
    this.reportUserError = SyncErrorService.report,
    Future<void> Function(Object error, {String? attachmentId, int? statusCode})?
        reportError,
  }) : reportError = reportError ?? _defaultReportError;

  static Future<void> _defaultReportError(
    Object error, {
    String? attachmentId,
    int? statusCode,
  }) async {
    await Sentry.captureException(
      error,
      withScope: (scope) {
        if (attachmentId != null) scope.setTag('attachment_id', attachmentId);
        if (statusCode != null) scope.setTag('http_status', statusCode.toString());
      },
    );
  }

  PendingMediaSummary get currentSummary => _summary;
  Stream<PendingMediaSummary> get summaryStream => _summaryController.stream;

  @visibleForTesting
  static Duration totalUploadDeadlineForBytes(int contentLength) {
    final transferSeconds = contentLength > 0
        ? (contentLength / _minUploadBytesPerSecond).ceil()
        : 0;
    final computed = Duration(seconds: transferSeconds) + _uploadDeadlineOverhead;
    return computed > _binaryUploadTimeout ? computed : _binaryUploadTimeout;
  }

  @visibleForTesting
  static Future<StreamingPutResult> sendStreamingPutAttempt({
    required http.Client client,
    required Uri url,
    required File file,
    required int start,
    required int end,
    String? contentType,
    void Function(int bytesSent)? onBytesSent,
    Duration stallTimeout = _uploadStallTimeout,
    Duration? totalDeadline,
  }) async {
    final contentLength = end - start;
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
        final request = _StreamingSliceRequest(
          'PUT',
          url,
          file,
          start: start,
          end: end,
          onActivity: resetStallTimer,
          onBytesSent: onBytesSent,
        )..contentLength = contentLength;
        if (contentType != null && contentType.isNotEmpty) {
          request.headers['Content-Type'] = contentType;
        }
        final streamedResponse = await client.send(request);
        resetStallTimer();
        await streamedResponse.stream
            .listen((_) => resetStallTimer(), cancelOnError: true)
            .asFuture<void>();
        return StreamingPutResult(
          statusCode: streamedResponse.statusCode,
          etag: (streamedResponse.headers['etag'] ?? '').trim(),
        );
      }();
      attemptFuture.ignore();
      timeoutCompleter.future.ignore();
      return await Future.any<StreamingPutResult>([
        attemptFuture,
        timeoutCompleter.future,
      ]);
    } finally {
      stallTimer?.cancel();
      totalTimer.cancel();
      client.close();
    }
  }

  static bool isPermanentClientStatus(int? statusCode) {
    if (statusCode == null) return false;
    return statusCode >= 400 &&
        statusCode < 500 &&
        statusCode != 401 &&
        statusCode != 408 &&
        statusCode != 426 &&
        statusCode != 429;
  }

  bool _isBlockedByWifiPolicy(int fileSize) {
    final conn = readConnectivity();
    if (conn.isOnWifi) return false;
    return switch (readPolicy()) {
      MediaUploadNetworkPolicy.anyNetwork => false,
      MediaUploadNetworkPolicy.wifiOnlyLarge => fileSize > multipartThresholdBytes,
      MediaUploadNetworkPolicy.wifiOnlyAll => true,
    };
  }

  Future<void> _emitSummary({String? activeFileName, double? activeProgress}) async {
    if (_stopped) return;
    try {
      _summary = await store.readSummary(
        activeFileName: activeFileName,
        activeProgress: activeProgress,
      );
      if (!_summaryController.isClosed) {
        _summaryController.add(_summary);
      }
    } catch (_) {}
  }

  Future<void> enqueue(
    PendingUploadItem item, {
    bool triggerUpload = true,
    bool ifAbsent = false,
  }) async {
    if (ifAbsent) {
      await store.insertIfAbsent(item);
    } else {
      await store.insert(item);
    }
    await _emitSummary();
    if (triggerUpload) trigger();
  }

  Future<void> refreshSummary() => _emitSummary();

  Future<void> retryFailed() async {
    _transientBackoffAttempt = 0;
    await store.retryAllFailed();
    await _emitSummary();
    trigger();
  }

  void trigger({bool resetBackoff = false}) {
    if (_stopped) return;
    if (resetBackoff) _transientBackoffAttempt = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_draining) {
      _reschedule = true;
      return;
    }
    unawaited(drainOnce());
  }

  void onPolicyOrConnectivityChanged() {
    if (_stopped) return;
    final activeSize = _activeItemFileSize;
    if (activeSize != null && _isBlockedByWifiPolicy(activeSize)) {
      _activeClient?.close();
      _activeClient = null;
    }
    if (readConnectivity().isOnline) {
      trigger(resetBackoff: true);
    }
  }

  Future<void> drainOnce() {
    if (_stopped) return Future<void>.value();
    if (_draining) return _drainFuture ?? Future<void>.value();
    _draining = true;
    final future = () async {
      try {
        do {
          _reschedule = false;
          await _processQueue();
        } while (_reschedule && !_stopped);
      } finally {
        _draining = false;
        _drainFuture = null;
        if (!_stopped) {
          await _emitSummary();
        }
      }
    }();
    _drainFuture = future;
    return future;
  }

  Future<void> _processQueue() async {
    final items = await store.listRunnable();
    if (items.isEmpty) return;

    final conn = readConnectivity();
    if (!conn.isOnline) return;

    for (final item in items) {
      if (_stopped) return;
      if (!readConnectivity().isOnline) return;

      if (await store.isSubmissionPendingSync(item.submissionId)) {
        continue;
      }

      if (_isBlockedByWifiPolicy(item.fileSize)) {
        if (item.status != MediaUploadStatus.pausedWifi) {
          await store.updateStatus(item.attachmentId, MediaUploadStatus.pausedWifi);
        }
        continue;
      }

      if (item.status == MediaUploadStatus.pausedWifi) {
        await store.updateStatus(item.attachmentId, MediaUploadStatus.queued);
      }

      final shouldContinue = await _processSingleItem(item);
      if (!shouldContinue) return;
    }
  }

  Future<void> _ensureFreshTokenOrThrow() async {
    if (_stopped) throw _QueueStoppedException();
    try {
      await gateway.ensureFreshToken();
    } catch (_) {
      throw _AuthUnavailableException();
    }
  }

  Future<StreamingPutResult> _sendManagedPut({
    required Uri url,
    required File file,
    required int start,
    required int end,
    String? contentType,
    void Function(int bytesSent)? onBytesSent,
  }) async {
    if (_stopped) throw _QueueStoppedException();
    final client = gateway.createHttpClient();
    _activeClient = client;
    try {
      final result = await sendStreamingPutAttempt(
        client: client,
        url: url,
        file: file,
        start: start,
        end: end,
        contentType: contentType,
        onBytesSent: onBytesSent,
      );
      if (_stopped) throw _QueueStoppedException();
      return result;
    } finally {
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
    }
  }

  Future<bool> _processSingleItem(PendingUploadItem item) async {
    if (_stopped) return false;
    final file = File(item.localPath);
    if (!await file.exists()) {
      const msg = 'Local media file is missing.';
      await store.updateStatus(
        item.attachmentId,
        MediaUploadStatus.failedPermanent,
        lastError: msg,
      );
      await reportError(Exception(msg), attachmentId: item.attachmentId);
      await _emitSummary();
      return true;
    }

    await store.updateStatus(item.attachmentId, MediaUploadStatus.uploading);
    await _emitSummary(activeFileName: item.originalName, activeProgress: 0);

    try {
      await _ensureFreshTokenOrThrow();
      final actualSize = await file.length();
      _activeItemFileSize = actualSize;
      if (_isBlockedByWifiPolicy(actualSize)) {
        throw _PausedForWifiException();
      }
      final init = await gateway.initUpload(
        attachmentId: item.attachmentId,
        sessionId: item.sessionId,
        fileName: item.originalName,
        contentType: item.contentType,
        fileSize: actualSize,
        fieldKey: item.fieldKey,
      );
      if (_stopped) throw _QueueStoppedException();

      final mode = init['mode'] as String? ?? 'single';
      if (mode == 'confirmed') {
        await _finishItem(item, file);
        return true;
      }

      if (_isBlockedByWifiPolicy(actualSize)) {
        throw _PausedForWifiException();
      }

      if (mode == 'multipart') {
        await _uploadMultipart(item, file, actualSize, init);
      } else {
        final uploadUrl = init['upload_url'] as String;
        await _uploadSingle(item, file, actualSize, uploadUrl);
      }

      if (_stopped) throw _QueueStoppedException();
      await _finishItem(item, file);
      return true;
    } on _QueueStoppedException {
      return false;
    } on _PausedForWifiException {
      if (_stopped) return false;
      await store.updateStatus(item.attachmentId, MediaUploadStatus.pausedWifi);
      await _emitSummary();
      return true;
    } on _AuthUnavailableException {
      if (_stopped) return false;
      await store.updateStatus(item.attachmentId, MediaUploadStatus.queued);
      if (readConnectivity().isOnline) {
        _scheduleRetry(++_transientBackoffAttempt);
      }
      return false;
    } on SocketException {
      if (_stopped) return false;
      if (_isBlockedByWifiPolicy(_activeItemFileSize ?? item.fileSize)) {
        await store.updateStatus(item.attachmentId, MediaUploadStatus.pausedWifi);
        await _emitSummary();
        return true;
      }
      await store.updateStatus(item.attachmentId, MediaUploadStatus.queued);
      if (readConnectivity().isOnline) {
        _scheduleRetry(++_transientBackoffAttempt);
      }
      return false;
    } on TimeoutException {
      if (_stopped) return false;
      await store.updateStatus(item.attachmentId, MediaUploadStatus.queued);
      if (readConnectivity().isOnline) {
        _scheduleRetry(++_transientBackoffAttempt);
      }
      return false;
    } on http.ClientException {
      if (_stopped) return false;
      if (_isBlockedByWifiPolicy(_activeItemFileSize ?? item.fileSize)) {
        await store.updateStatus(item.attachmentId, MediaUploadStatus.pausedWifi);
        await _emitSummary();
        return true;
      }
      await store.updateStatus(item.attachmentId, MediaUploadStatus.queued);
      if (readConnectivity().isOnline) {
        _scheduleRetry(++_transientBackoffAttempt);
      }
      return false;
    } on _TransientNetworkException {
      if (_stopped) return false;
      await store.updateStatus(
        item.attachmentId,
        MediaUploadStatus.queued,
        retryCount: item.retryCount + 1,
      );
      if (readConnectivity().isOnline) {
        _scheduleRetry(item.retryCount + 1);
      }
      return false;
    } on ApiException catch (e) {
      if (_stopped) return false;
      if (e.statusCode == 410) {
        await store.saveMultipartState(
          item.attachmentId,
          uploadId: '',
          partSize: 0,
          completedPartsJson: '[]',
        );
        await store.updateStatus(
          item.attachmentId,
          MediaUploadStatus.queued,
          retryCount: item.retryCount + 1,
          lastError: e.message,
        );
        if (readConnectivity().isOnline) {
          _scheduleRetry(item.retryCount + 1);
        }
        return false;
      }
      if (isPermanentClientStatus(e.statusCode)) {
        await store.updateStatus(
          item.attachmentId,
          MediaUploadStatus.failedPermanent,
          lastError: e.message,
        );
        await reportError(
          e,
          attachmentId: item.attachmentId,
          statusCode: e.statusCode,
        );
        reportUserError(
          'Could not upload ${item.originalName}: ${e.message}',
        );
        await _emitSummary();
        return true;
      }

      if (e.statusCode == 401) {
        try {
          await gateway.forceRefreshToken();
        } catch (_) {}
      }

      await store.updateStatus(
        item.attachmentId,
        MediaUploadStatus.queued,
        retryCount: item.retryCount + 1,
        lastError: e.message,
      );
      if (readConnectivity().isOnline) {
        _scheduleRetry(item.retryCount + 1);
      }
      return false;
    } catch (e) {
      if (_stopped) return false;
      await store.updateStatus(
        item.attachmentId,
        MediaUploadStatus.queued,
        retryCount: item.retryCount + 1,
        lastError: e.toString(),
      );
      await reportError(e, attachmentId: item.attachmentId);
      if (readConnectivity().isOnline) {
        _scheduleRetry(item.retryCount + 1);
      }
      return false;
    } finally {
      _activeItemFileSize = null;
    }
  }

  Future<void> _uploadSingle(
    PendingUploadItem item,
    File file,
    int fileSize,
    String uploadUrl,
  ) async {
    var lastReportedProgress = 0.0;
    final result = await _sendManagedPut(
      url: Uri.parse(uploadUrl),
      file: file,
      start: 0,
      end: fileSize,
      contentType: item.contentType,
      onBytesSent: fileSize > 0
          ? (sent) {
              final progress = min(0.95, (sent / fileSize) * 0.95);
              if (progress - lastReportedProgress >= 0.05) {
                lastReportedProgress = progress;
                unawaited(
                  _emitSummary(
                    activeFileName: item.originalName,
                    activeProgress: progress,
                  ),
                );
              }
            }
          : null,
    );
    _checkPutStatus(result.statusCode, item.originalName);
    await _emitSummary(activeFileName: item.originalName, activeProgress: 0.95);
    await _ensureFreshTokenOrThrow();
    await gateway.confirmUpload(attachmentId: item.attachmentId);
  }

  Future<void> _uploadMultipart(
    PendingUploadItem item,
    File file,
    int fileSize,
    Map<String, dynamic> init,
  ) async {
    final uploadId = init['upload_id'] as String;
    final partSize = (init['part_size'] as num).toInt();
    final totalParts = (init['total_parts'] as num).toInt();
    final serverPartsRaw = init['uploaded_parts'] as List<dynamic>? ?? const [];

    final completed = <int, String>{};
    for (final entry in serverPartsRaw) {
      if (entry is Map) {
        final pNum = (entry['part_number'] as num?)?.toInt();
        final etag = entry['etag'] as String?;
        if (pNum != null && pNum >= 1 && etag != null && etag.isNotEmpty) {
          completed[pNum] = etag;
        }
      }
    }

    await store.saveMultipartState(
      item.attachmentId,
      uploadId: uploadId,
      partSize: partSize,
      completedPartsJson: _encodeParts(completed),
    );

    int partLength(int partNumber) =>
        max(0, min(partSize, fileSize - (partNumber - 1) * partSize));
    double progressFor(int bytesDone) =>
        fileSize > 0 ? min(0.95, (bytesDone / fileSize) * 0.95) : 0;

    var doneBytes = completed.keys.fold<int>(0, (sum, n) => sum + partLength(n));
    var lastReportedProgress = progressFor(doneBytes);
    void reportPartBytes(int sentInPart) {
      final progress = progressFor(doneBytes + sentInPart);
      if (progress - lastReportedProgress >= 0.01) {
        lastReportedProgress = progress;
        unawaited(
          _emitSummary(
            activeFileName: item.originalName,
            activeProgress: progress,
          ),
        );
      }
    }

    await _emitSummary(
      activeFileName: item.originalName,
      activeProgress: lastReportedProgress,
    );

    final remaining = <int>[
      for (var n = 1; n <= totalParts; n++)
        if (!completed.containsKey(n)) n,
    ];

    for (var i = 0; i < remaining.length; i += partUrlBatchSize) {
      if (_stopped) throw _QueueStoppedException();
      if (!readConnectivity().isOnline) {
        throw const SocketException('Device offline');
      }
      if (_isBlockedByWifiPolicy(fileSize)) {
        throw _PausedForWifiException();
      }

      final batch = remaining.sublist(i, min(i + partUrlBatchSize, remaining.length));
      await _ensureFreshTokenOrThrow();
      final signed = await gateway.getPartUrls(
        attachmentId: item.attachmentId,
        partNumbers: batch,
      );

      for (final entry in signed) {
        if (_stopped) throw _QueueStoppedException();
        if (!readConnectivity().isOnline) {
          throw const SocketException('Device offline');
        }
        if (_isBlockedByWifiPolicy(fileSize)) {
          throw _PausedForWifiException();
        }

        final partNumber = (entry['part_number'] as num).toInt();
        var partUrl = entry['url'] as String;
        final start = (partNumber - 1) * partSize;
        final end = min(start + partSize, fileSize);

        var result = await _sendManagedPut(
          url: Uri.parse(partUrl),
          file: file,
          start: start,
          end: end,
          onBytesSent: reportPartBytes,
        );

        if (result.statusCode == 403) {
          await _ensureFreshTokenOrThrow();
          final refreshed = await gateway.getPartUrls(
            attachmentId: item.attachmentId,
            partNumbers: [partNumber],
          );
          if (refreshed.isNotEmpty) {
            if (_isBlockedByWifiPolicy(fileSize)) {
              throw _PausedForWifiException();
            }
            partUrl = refreshed.first['url'] as String;
            result = await _sendManagedPut(
              url: Uri.parse(partUrl),
              file: file,
              start: start,
              end: end,
              onBytesSent: reportPartBytes,
            );
          }
        }

        _checkPutStatus(
          result.statusCode,
          '${item.originalName} part $partNumber',
          isMultipartPart: true,
        );
        if (result.etag.isEmpty) {
          throw _TransientNetworkException('Missing ETag for part $partNumber');
        }

        _transientBackoffAttempt = 0;
        completed[partNumber] = result.etag;
        await store.saveMultipartState(
          item.attachmentId,
          uploadId: uploadId,
          partSize: partSize,
          completedPartsJson: _encodeParts(completed),
        );
        doneBytes += end - start;
        lastReportedProgress = progressFor(doneBytes);
        await _emitSummary(
          activeFileName: item.originalName,
          activeProgress: lastReportedProgress,
        );
      }
    }

    if (_stopped) throw _QueueStoppedException();
    await _ensureFreshTokenOrThrow();
    await gateway.confirmUpload(
      attachmentId: item.attachmentId,
      parts: _sortedPartList(completed),
    );
  }

  void _checkPutStatus(
    int statusCode,
    String label, {
    bool isMultipartPart = false,
  }) {
    if (statusCode >= 200 && statusCode < 300) return;
    if (statusCode == 403) {
      throw _TransientNetworkException('Presigned URL expired for $label (403)');
    }
    if (isMultipartPart && statusCode == 404) {
      throw _TransientNetworkException('Multipart upload expired for $label (404)');
    }
    if (isPermanentClientStatus(statusCode)) {
      throw ApiException(
        'Storage rejected $label ($statusCode)',
        statusCode: statusCode,
      );
    }
    throw _TransientNetworkException('Storage returned $statusCode for $label');
  }

  Future<void> _finishItem(PendingUploadItem item, File file) async {
    _transientBackoffAttempt = 0;
    await store.markDoneAndRemove(item.attachmentId);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    await _emitSummary();
  }

  void _scheduleRetry(int retryCount) {
    if (_stopped) return;
    final delaySec = min(60, 2 << min(retryCount, 5));
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delaySec), trigger);
  }

  static List<Map<String, dynamic>> _sortedPartList(Map<int, String> parts) {
    final nums = parts.keys.toList()..sort();
    return [
      for (final n in nums) {'part_number': n, 'etag': parts[n]!},
    ];
  }

  static String _encodeParts(Map<int, String> parts) =>
      jsonEncode(_sortedPartList(parts));

  Future<void> dispose() async {
    _stopped = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _activeClient?.close();
    _activeClient = null;
    final pendingDrain = _drainFuture;
    if (pendingDrain != null) {
      try {
        await pendingDrain;
      } catch (_) {}
    }
    await _summaryController.close();
  }
}

class MediaUploadQueueService {
  static MediaUploadQueueWorker? _worker;
  static StreamSubscription<ConnectivityState>? _connectivitySub;
  static StreamSubscription<PendingMediaSummary>? _summaryForwardSub;
  static final StreamController<PendingMediaSummary> _summaryController =
      StreamController<PendingMediaSummary>.broadcast();
  static PendingMediaSummary _latestSummary = const PendingMediaSummary();

  static PendingMediaSummary get currentSummary => _latestSummary;
  static Stream<PendingMediaSummary> get summaryStream => _summaryController.stream;

  static Future<void> start(PowerSyncDatabase db) async {
    await stop();
    await PreferencesService.getMediaUploadPolicy();

    final store = PowerSyncMediaUploadStore(db);
    await store.resetStuckUploading();

    final worker = MediaUploadQueueWorker(
      store: store,
      gateway: DefaultMediaUploadGateway(),
      readConnectivity: () => ConnectivityService.state,
      readPolicy: () => PreferencesService.mediaPolicyNotifier.value,
    );
    _worker = worker;

    _summaryForwardSub = worker.summaryStream.listen((summary) {
      _latestSummary = summary;
      if (!_summaryController.isClosed) {
        _summaryController.add(summary);
      }
    });

    _latestSummary = await store.readSummary();
    if (!_summaryController.isClosed) {
      _summaryController.add(_latestSummary);
    }

    _connectivitySub = ConnectivityService.stateStream.listen((state) {
      _worker?.onPolicyOrConnectivityChanged();
    });
    PreferencesService.mediaPolicyNotifier.addListener(_onPolicyChanged);

    worker.trigger();
  }

  static void _onPolicyChanged() {
    _worker?.onPolicyOrConnectivityChanged();
  }

  static const _legacyNamespaceUrl = '6ba7b811-9dad-11d1-80b4-00c04fd430c8';

  static Future<List<PendingUploadItem>> extractSubmissionMedia(
    Map<String, dynamic> payload, {
    required String submissionId,
    required int sessionId,
    bool deterministicId = false,
    bool throwOnUnsupported = true,
  }) async {
    const uuid = Uuid();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final items = <PendingUploadItem>[];

    for (final fieldKey in payload.keys.toList()) {
      final value = payload[fieldKey];
      if (value is! Map<String, dynamic> || !value.containsKey('file_path')) {
        continue;
      }

      final filePath = value['file_path'] as String? ?? '';
      final fileName = value['file_name'] as String? ?? '';
      final originalName =
          (value['original_name'] as String?) ??
          (fileName.isNotEmpty ? fileName : filePath.split('/').last);
      final file = File(filePath);
      if (!await file.exists()) {
        payload.remove(fieldKey);
        continue;
      }

      final ext = extensionOf(fileName.isNotEmpty ? fileName : filePath);
      final contentType = mimeForExtension(ext);
      if (contentType == null) {
        if (throwOnUnsupported) {
          throw Exception('Unsupported file type (.$ext)');
        }
        SyncErrorService.report(
          'An attachment could not be uploaded — unsupported file type (.$ext).',
        );
        payload.remove(fieldKey);
        continue;
      }

      final fileSize =
          (value['file_size'] as num?)?.toInt() ?? await file.length();
      final attachmentId = deterministicId
          ? uuid.v5(_legacyNamespaceUrl, 'fieldlog:$submissionId:$fieldKey')
          : uuid.v4();

      items.add(
        PendingUploadItem(
          attachmentId: attachmentId,
          submissionId: submissionId,
          sessionId: sessionId,
          fieldKey: fieldKey,
          localPath: filePath,
          originalName: originalName,
          contentType: contentType,
          fileSize: fileSize,
          s3UploadId: '',
          partSize: 0,
          completedPartsJson: '[]',
          status: MediaUploadStatus.queued,
          retryCount: 0,
          lastError: '',
          createdAt: createdAt,
        ),
      );

      payload[fieldKey] = [
        {
          'attachment_id': attachmentId,
          'name': originalName,
          'type': contentType,
          'size': fileSize,
        },
      ];
    }

    return items;
  }

  static Future<void> enqueueItem(
    PendingUploadItem item, {
    bool triggerUpload = true,
    bool ifAbsent = false,
  }) async {
    final worker = _worker;
    if (worker == null) {
      throw StateError('MediaUploadQueueService has not been started.');
    }
    await worker.enqueue(
      item,
      triggerUpload: triggerUpload,
      ifAbsent: ifAbsent,
    );
  }

  static Future<void> notifyEnqueued({bool triggerUpload = true}) async {
    final worker = _worker;
    if (worker == null) return;
    await worker.refreshSummary();
    if (triggerUpload) worker.trigger();
  }

  static Future<void> enqueue({
    required String attachmentId,
    required String submissionId,
    required int sessionId,
    required String fieldKey,
    required String localPath,
    required String originalName,
    required String contentType,
    required int fileSize,
    bool triggerUpload = true,
    bool ifAbsent = false,
  }) async {
    await enqueueItem(
      PendingUploadItem(
        attachmentId: attachmentId,
        submissionId: submissionId,
        sessionId: sessionId,
        fieldKey: fieldKey,
        localPath: localPath,
        originalName: originalName,
        contentType: contentType,
        fileSize: fileSize,
        s3UploadId: '',
        partSize: 0,
        completedPartsJson: '[]',
        status: MediaUploadStatus.queued,
        retryCount: 0,
        lastError: '',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
      triggerUpload: triggerUpload,
      ifAbsent: ifAbsent,
    );
  }

  static Future<void> cleanupLocalFilesForLogout(PowerSyncDatabase db) async {
    try {
      final store = PowerSyncMediaUploadStore(db);
      final paths = await store.listAllLocalPaths();
      for (final path in paths) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<void> retryFailed() async {
    await _worker?.retryFailed();
  }

  static void trigger() {
    _worker?.trigger();
  }

  static Future<void> stop() async {
    PreferencesService.mediaPolicyNotifier.removeListener(_onPolicyChanged);
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _summaryForwardSub?.cancel();
    _summaryForwardSub = null;
    final worker = _worker;
    _worker = null;
    if (worker != null) {
      await worker.dispose();
    }
    _latestSummary = const PendingMediaSummary();
    if (!_summaryController.isClosed) {
      _summaryController.add(_latestSummary);
    }
  }
}
