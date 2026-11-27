import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fieldlog_mobile/services/api_service.dart';
import 'package:fieldlog_mobile/services/audio_service.dart';
import 'package:fieldlog_mobile/services/connectivity_service.dart';
import 'package:fieldlog_mobile/services/media_upload_queue_service.dart';
import 'package:fieldlog_mobile/services/preferences_service.dart';
import 'package:fieldlog_mobile/widgets/field_widgets/file_field_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _InMemoryUploadStore implements MediaUploadStore {
  final Map<String, PendingUploadItem> rows = {};
  final Set<String> pendingSubmissions = {};

  @override
  Future<void> insert(PendingUploadItem item) async {
    rows[item.attachmentId] = item;
  }

  @override
  Future<void> insertIfAbsent(PendingUploadItem item) async {
    rows.putIfAbsent(item.attachmentId, () => item);
  }

  @override
  Future<List<String>> listAllLocalPaths() async {
    return [for (final r in rows.values) r.localPath];
  }

  @override
  Future<bool> isSubmissionPendingSync(String submissionId) async {
    return pendingSubmissions.contains(submissionId);
  }

  @override
  Future<void> resetStuckUploading() async {
    for (final entry in rows.entries.toList()) {
      if (entry.value.status == MediaUploadStatus.uploading) {
        await updateStatus(entry.key, MediaUploadStatus.queued);
      }
    }
  }

  @override
  Future<List<PendingUploadItem>> listRunnable() async {
    final list = rows.values
        .where(
          (i) =>
              i.status == MediaUploadStatus.queued ||
              i.status == MediaUploadStatus.pausedWifi,
        )
        .toList();
    list.sort((a, b) {
      final sizeCmp = a.fileSize.compareTo(b.fileSize);
      return sizeCmp != 0 ? sizeCmp : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  @override
  Future<void> updateStatus(
    String attachmentId,
    String status, {
    int? retryCount,
    String? lastError,
  }) async {
    final cur = rows[attachmentId];
    if (cur == null) return;
    rows[attachmentId] = PendingUploadItem(
      attachmentId: cur.attachmentId,
      submissionId: cur.submissionId,
      sessionId: cur.sessionId,
      fieldKey: cur.fieldKey,
      localPath: cur.localPath,
      originalName: cur.originalName,
      contentType: cur.contentType,
      fileSize: cur.fileSize,
      s3UploadId: cur.s3UploadId,
      partSize: cur.partSize,
      completedPartsJson: cur.completedPartsJson,
      tusUploadUrl: cur.tusUploadUrl,
      uploadedOffset: cur.uploadedOffset,
      status: status,
      retryCount: retryCount ?? cur.retryCount,
      lastError: lastError ?? cur.lastError,
      createdAt: cur.createdAt,
    );
  }

  @override
  Future<void> saveMultipartState(
    String attachmentId, {
    required String uploadId,
    required int partSize,
    required String completedPartsJson,
  }) async {
    final cur = rows[attachmentId];
    if (cur == null) return;
    rows[attachmentId] = PendingUploadItem(
      attachmentId: cur.attachmentId,
      submissionId: cur.submissionId,
      sessionId: cur.sessionId,
      fieldKey: cur.fieldKey,
      localPath: cur.localPath,
      originalName: cur.originalName,
      contentType: cur.contentType,
      fileSize: cur.fileSize,
      s3UploadId: uploadId,
      partSize: partSize,
      completedPartsJson: completedPartsJson,
      tusUploadUrl: cur.tusUploadUrl,
      uploadedOffset: cur.uploadedOffset,
      status: cur.status,
      retryCount: cur.retryCount,
      lastError: cur.lastError,
      createdAt: cur.createdAt,
    );
  }

  @override
  Future<void> saveTusState(
    String attachmentId, {
    required String tusUploadUrl,
    required int uploadedOffset,
  }) async {
    final cur = rows[attachmentId];
    if (cur == null) return;
    rows[attachmentId] = PendingUploadItem(
      attachmentId: cur.attachmentId,
      submissionId: cur.submissionId,
      sessionId: cur.sessionId,
      fieldKey: cur.fieldKey,
      localPath: cur.localPath,
      originalName: cur.originalName,
      contentType: cur.contentType,
      fileSize: cur.fileSize,
      s3UploadId: cur.s3UploadId,
      partSize: cur.partSize,
      completedPartsJson: cur.completedPartsJson,
      tusUploadUrl: tusUploadUrl,
      uploadedOffset: uploadedOffset,
      status: cur.status,
      retryCount: cur.retryCount,
      lastError: cur.lastError,
      createdAt: cur.createdAt,
    );
  }

  @override
  Future<void> markDoneAndRemove(String attachmentId) async {
    rows.remove(attachmentId);
  }

  @override
  Future<void> retryAllFailed() async {
    for (final entry in rows.entries.toList()) {
      if (entry.value.status == MediaUploadStatus.failedPermanent) {
        await updateStatus(
          entry.key,
          MediaUploadStatus.queued,
          retryCount: 0,
          lastError: '',
        );
      }
    }
  }

  @override
  Future<PendingMediaSummary> readSummary({
    String? activeFileName,
    double? activeProgress,
  }) async {
    var queued = 0;
    var uploading = 0;
    var paused = 0;
    var failed = 0;
    for (final item in rows.values) {
      switch (item.status) {
        case MediaUploadStatus.queued:
          queued++;
        case MediaUploadStatus.uploading:
          uploading++;
        case MediaUploadStatus.pausedWifi:
          paused++;
        case MediaUploadStatus.failedPermanent:
          failed++;
      }
    }
    return PendingMediaSummary(
      queuedCount: queued,
      uploadingCount: uploading,
      pausedWifiCount: paused,
      failedCount: failed,
      activeFileName: uploading > 0 ? activeFileName : null,
      activeProgress: uploading > 0 ? activeProgress : null,
    );
  }
}

class _FakeHttpClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest req) handler;
  final void Function()? onClose;
  _FakeHttpClient(this.handler, {this.onClose});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);

  @override
  void close() {
    onClose?.call();
    super.close();
  }
}

class _FakeGateway implements MediaUploadGateway {
  final Future<Map<String, dynamic>> Function(String id, int size) onInit;
  final Future<List<Map<String, dynamic>>> Function(String id, List<int> parts)
      onPartUrls;
  final Future<void> Function(String id, List<Map<String, dynamic>>? parts)
      onConfirm;
  final Future<http.StreamedResponse> Function(http.BaseRequest req) onPut;
  final Future<void> Function()? onForceRefresh;
  final void Function()? onClientClose;
  final String? tusEndpoint;

  _FakeGateway({
    required this.onInit,
    required this.onPartUrls,
    required this.onConfirm,
    required this.onPut,
    this.onForceRefresh,
    this.onClientClose,
    this.tusEndpoint,
  });

  @override
  Future<void> ensureFreshToken() async {}

  @override
  Future<void> forceRefreshToken() async {
    await onForceRefresh?.call();
  }

  @override
  Future<String?> getAccessToken() async => 'jwt-token';

  @override
  Future<String?> getTusEndpoint() async => tusEndpoint;

  @override
  Future<Map<String, dynamic>> initUpload({
    required String attachmentId,
    required int sessionId,
    required String fileName,
    required String contentType,
    required int fileSize,
    String? fieldKey,
  }) =>
      onInit(attachmentId, fileSize);

  @override
  Future<List<Map<String, dynamic>>> getPartUrls({
    required String attachmentId,
    required List<int> partNumbers,
  }) =>
      onPartUrls(attachmentId, partNumbers);

  @override
  Future<void> confirmUpload({
    required String attachmentId,
    List<Map<String, dynamic>>? parts,
  }) =>
      onConfirm(attachmentId, parts);

  @override
  http.Client createHttpClient() =>
      _FakeHttpClient(onPut, onClose: onClientClose);
}

PendingUploadItem _item(
  String id,
  File file, {
  String name = 'clip.m4a',
  String contentType = 'audio/mp4',
}) {
  return PendingUploadItem(
    attachmentId: id,
    submissionId: 'sub-1',
    sessionId: 1,
    fieldKey: 'media',
    localPath: file.path,
    originalName: name,
    contentType: contentType,
    fileSize: file.lengthSync(),
    s3UploadId: '',
    partSize: 0,
    completedPartsJson: '[]',
    status: MediaUploadStatus.queued,
    retryCount: 0,
    lastError: '',
    createdAt: '2026-11-26T00:00:00Z',
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('media_queue_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'resumes multipart upload at part 4 after network drop without re-uploading parts 1-3',
    () async {
      // 5 parts of 100 KB each = 500 KB (server controls part_size).
      const partSize = 100 * 1024;
      final file = File('${tempDir.path}/video.mp4')
        ..writeAsBytesSync(List<int>.filled(5 * partSize, 42));

      final store = _InMemoryUploadStore();
      final uploadedParts = <int>[];
      final serverParts = <int, String>{};
      List<Map<String, dynamic>>? confirmedParts;
      var dropOnPart4 = true;

      final gateway = _FakeGateway(
        onInit: (id, size) async => {
          'attachment_id': id,
          'mode': 'multipart',
          'upload_id': 'u-1',
          'part_size': partSize,
          'total_parts': 5,
          'uploaded_parts': [
            for (final e in serverParts.entries)
              {'part_number': e.key, 'etag': e.value},
          ],
        },
        onPartUrls: (id, parts) async => [
          for (final p in parts)
            {'part_number': p, 'url': 'https://s3.test/part/$p'},
        ],
        onPut: (req) async {
          final partNum = int.parse(req.url.pathSegments.last);
          final bytes = await req.finalize().fold<int>(0, (s, c) => s + c.length);
          expect(bytes, partSize);
          if (partNum == 4 && dropOnPart4) {
            dropOnPart4 = false;
            throw const SocketException('2G signal lost');
          }
          uploadedParts.add(partNum);
          serverParts[partNum] = '"etag-$partNum"';
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'etag': '"etag-$partNum"'},
          );
        },
        onConfirm: (id, parts) async {
          confirmedParts = parts;
        },
      );

      final userErrors = <String>[];
      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: userErrors.add,
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-resume', file));

      // Pass 1: drops on part 4. Parts 1-3 persisted, zero retries burned, no error toast.
      await worker.drainOnce();
      expect(uploadedParts, [1, 2, 3]);
      expect(store.rows['att-resume']!.status, MediaUploadStatus.queued);
      expect(store.rows['att-resume']!.retryCount, 0);
      expect(store.rows['att-resume']!.parseCompletedParts().keys, {1, 2, 3});
      expect(userErrors, isEmpty);

      // Pass 2: reconnects and resumes at part 4 (parts 1-3 NOT re-uploaded).
      await worker.drainOnce();
      expect(uploadedParts, [1, 2, 3, 4, 5]);
      expect(confirmedParts, hasLength(5));
      expect(store.rows, isEmpty);
      expect(file.existsSync(), isFalse);
    },
  );

  test(
    'reports byte-level progress within multipart parts',
    () async {
      const partSize = 512 * 1024;
      final file = File('${tempDir.path}/clip.wav')
        ..writeAsBytesSync(List<int>.filled(2 * partSize, 7));

      final store = _InMemoryUploadStore();
      final gateway = _FakeGateway(
        onInit: (id, size) async => {
          'attachment_id': id,
          'mode': 'multipart',
          'upload_id': 'u-progress',
          'part_size': partSize,
          'total_parts': 2,
          'uploaded_parts': const [],
        },
        onPartUrls: (id, parts) async => [
          for (final p in parts)
            {'part_number': p, 'url': 'https://s3.test/part/$p'},
        ],
        onPut: (req) async {
          final partNum = int.parse(req.url.pathSegments.last);
          await req.finalize().drain<void>();
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'etag': '"etag-$partNum"'},
          );
        },
        onConfirm: (id, parts) async {},
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      final progress = <double>[];
      final sub = worker.summaryStream.listen((s) {
        final p = s.activeProgress;
        if (p != null) progress.add(p);
      });
      addTearDown(sub.cancel);

      await store.insert(
        _item('att-progress', file, name: 'clip.wav', contentType: 'audio/wav'),
      );
      await worker.drainOnce();
      await Future<void>.delayed(Duration.zero);

      expect(store.rows, isEmpty);
      expect(progress.any((p) => p > 0 && p < 0.475), isTrue);
      expect(progress.any((p) => p > 0.475 && p < 0.95), isTrue);
      expect(progress.every((p) => p <= 0.95), isTrue);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    },
  );

  test(
    'refreshes expired part URL on 403 mid-upload without restarting',
    () async {
      const partSize = 64 * 1024;
      final file = File('${tempDir.path}/long.m4a')
        ..writeAsBytesSync(List<int>.filled(2 * partSize, 9));
      final store = _InMemoryUploadStore();
      var part2Calls = 0;
      var refreshedPart2 = false;

      final gateway = _FakeGateway(
        onInit: (id, size) async => {
          'attachment_id': id,
          'mode': 'multipart',
          'upload_id': 'u-2',
          'part_size': partSize,
          'total_parts': 2,
          'uploaded_parts': const [],
        },
        onPartUrls: (id, parts) async {
          if (parts.length == 1 && parts.first == 2) {
            refreshedPart2 = true;
          }
          return [
            for (final p in parts)
              {
                'part_number': p,
                'url':
                    'https://s3.test/part/$p?v=${refreshedPart2 ? "fresh" : "old"}',
              },
          ];
        },
        onPut: (req) async {
          final p = int.parse(req.url.pathSegments.last);
          await req.finalize().drain<void>();
          if (p == 2) {
            part2Calls++;
            if (req.url.queryParameters['v'] == 'old') {
              return http.StreamedResponse(const Stream.empty(), 403);
            }
          }
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'etag': '"e$p"'},
          );
        },
        onConfirm: (_, _) async {},
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-403', file));
      await worker.drainOnce();

      expect(refreshedPart2, isTrue);
      expect(part2Calls, 2);
      expect(store.rows, isEmpty);
    },
  );

  test(
    'Wi-Fi-only (>5 MB) pauses large files on cellular while uploading small photos immediately',
    () async {
      final smallPhoto = File('${tempDir.path}/small.jpg')
        ..writeAsBytesSync(List<int>.filled(1024, 1));
      final largeAudio = File('${tempDir.path}/large.m4a')
        ..writeAsBytesSync(List<int>.filled(6 * 1024 * 1024, 2));

      final store = _InMemoryUploadStore();
      var isOnWifi = false;
      final uploaded = <String>[];

      final gateway = _FakeGateway(
        onInit: (id, size) async => {
          'attachment_id': id,
          'mode': 'single',
          'upload_url': 'https://s3.test/single/$id',
        },
        onPartUrls: (_, _) async => const [],
        onPut: (req) async {
          await req.finalize().drain<void>();
          uploaded.add(req.url.pathSegments.last);
          return http.StreamedResponse(const Stream.empty(), 200);
        },
        onConfirm: (_, _) async {},
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            ConnectivityState(isOnline: true, isOnWifi: isOnWifi),
        readPolicy: () => MediaUploadNetworkPolicy.wifiOnlyLarge,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-large', largeAudio, name: 'large.m4a'));
      await store.insert(
        _item(
          'att-small',
          smallPhoto,
          name: 'small.jpg',
          contentType: 'image/jpeg',
        ),
      );

      // Cellular: small photo uploads immediately, large file pauses for Wi-Fi.
      await worker.drainOnce();
      expect(uploaded, ['att-small']);
      expect(store.rows['att-large']!.status, MediaUploadStatus.pausedWifi);
      expect(worker.currentSummary.isPausedForWifi, isTrue);

      // Wi-Fi restored: large file now uploads.
      isOnWifi = true;
      await worker.drainOnce();
      expect(uploaded, ['att-small', 'att-large']);
      expect(store.rows, isEmpty);
    },
  );

  test(
    'permanent 4xx on one attachment never blocks other attachments in queue',
    () async {
      final badFile = File('${tempDir.path}/bad.jpg')
        ..writeAsBytesSync(List<int>.filled(512, 1));
      final goodFile = File('${tempDir.path}/good.jpg')
        ..writeAsBytesSync(List<int>.filled(1024, 2));

      final store = _InMemoryUploadStore();
      final confirmed = <String>[];
      final userErrors = <String>[];

      final gateway = _FakeGateway(
        onInit: (id, size) async {
          if (id == 'att-bad') {
            throw ApiException('Content type not allowed.', statusCode: 400);
          }
          return {
            'attachment_id': id,
            'mode': 'single',
            'upload_url': 'https://s3.test/single/$id',
          };
        },
        onPartUrls: (_, _) async => const [],
        onPut: (req) async {
          await req.finalize().drain<void>();
          return http.StreamedResponse(const Stream.empty(), 200);
        },
        onConfirm: (id, _) async => confirmed.add(id),
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: userErrors.add,
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-bad', badFile, name: 'bad.jpg'));
      await store.insert(_item('att-good', goodFile, name: 'good.jpg'));

      await worker.drainOnce();

      expect(store.rows['att-bad']!.status, MediaUploadStatus.failedPermanent);
      expect(confirmed, ['att-good']);
      expect(store.rows.containsKey('att-good'), isFalse);
      expect(userErrors, hasLength(1));
    },
  );

  test(
    'dispose() mid-multipart upload does not delete local file or remove queue row',
    () async {
      const partSize = 64 * 1024;
      final file = File('${tempDir.path}/keep.m4a')
        ..writeAsBytesSync(List<int>.filled(3 * partSize, 5));
      final store = _InMemoryUploadStore();
      var confirmCalled = false;
      final part1Started = Completer<void>();

      late MediaUploadQueueWorker worker;
      final gateway = _FakeGateway(
        onInit: (id, size) async => {
          'attachment_id': id,
          'mode': 'multipart',
          'upload_id': 'u-stop',
          'part_size': partSize,
          'total_parts': 3,
          'uploaded_parts': const [],
        },
        onPartUrls: (id, parts) async => [
          for (final p in parts)
            {'part_number': p, 'url': 'https://s3.test/part/$p'},
        ],
        onPut: (req) async {
          await req.finalize().drain<void>();
          if (!part1Started.isCompleted) part1Started.complete();
          // Trigger dispose right after part 1 finishes, before part 2 starts.
          unawaited(worker.dispose());
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'etag': '"e1"'},
          );
        },
        onConfirm: (_, _) async {
          confirmCalled = true;
        },
      );

      worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );

      await store.insert(_item('att-stop', file));
      await worker.drainOnce();

      expect(confirmCalled, isFalse);
      expect(file.existsSync(), isTrue);
      expect(store.rows.containsKey('att-stop'), isTrue);
    },
  );

  test(
    'extractSubmissionMedia deterministicId produces stable UUIDs across retries',
    () async {
      final file = File('${tempDir.path}/legacy.jpg')
        ..writeAsBytesSync(List<int>.filled(512, 3));

      final payload1 = <String, dynamic>{
        'photo': {
          'file_path': file.path,
          'file_name': 'legacy.jpg',
          'original_name': 'legacy.jpg',
          'file_size': 512,
        },
      };
      final payload2 = <String, dynamic>{
        'photo': {
          'file_path': file.path,
          'file_name': 'legacy.jpg',
          'original_name': 'legacy.jpg',
          'file_size': 512,
        },
      };

      final items1 = await MediaUploadQueueService.extractSubmissionMedia(
        payload1,
        submissionId: 'sub-legacy-1',
        sessionId: 7,
        deterministicId: true,
        throwOnUnsupported: false,
      );
      final items2 = await MediaUploadQueueService.extractSubmissionMedia(
        payload2,
        submissionId: 'sub-legacy-1',
        sessionId: 7,
        deterministicId: true,
        throwOnUnsupported: false,
      );

      expect(items1, hasLength(1));
      expect(items2, hasLength(1));
      expect(items1.first.attachmentId, items2.first.attachmentId);

      final store = _InMemoryUploadStore();
      await store.insertIfAbsent(items1.first);
      await store.insertIfAbsent(items2.first);
      expect(store.rows, hasLength(1));
    },
  );

  test(
    '404 NoSuchUpload on multipart part is treated as transient and restarts cleanly via /init/',
    () async {
      const partSize = 64 * 1024;
      final file = File('${tempDir.path}/expired7d.m4a')
        ..writeAsBytesSync(List<int>.filled(2 * partSize, 4));
      final store = _InMemoryUploadStore();
      var initCalls = 0;
      var return404Once = true;
      var confirmed = false;

      final gateway = _FakeGateway(
        onInit: (id, size) async {
          initCalls++;
          return {
            'attachment_id': id,
            'mode': 'multipart',
            'upload_id': 'u-$initCalls',
            'part_size': partSize,
            'total_parts': 2,
            'uploaded_parts': const [],
          };
        },
        onPartUrls: (id, parts) async => [
          for (final p in parts)
            {'part_number': p, 'url': 'https://s3.test/part/$p'},
        ],
        onPut: (req) async {
          final p = int.parse(req.url.pathSegments.last);
          await req.finalize().drain<void>();
          if (return404Once) {
            return404Once = false;
            return http.StreamedResponse(const Stream.empty(), 404);
          }
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'etag': '"e$p"'},
          );
        },
        onConfirm: (_, _) async {
          confirmed = true;
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-404', file));

      // First pass gets 404 NoSuchUpload -> stays queued (NOT failed_permanent).
      await worker.drainOnce();
      expect(store.rows['att-404']!.status, MediaUploadStatus.queued);
      expect(confirmed, isFalse);

      // Second pass calls /init/ -> gets new upload_id and completes.
      await worker.drainOnce();
      expect(initCalls, 2);
      expect(confirmed, isTrue);
      expect(store.rows, isEmpty);
    },
  );

  test(
    '401 triggers forceRefreshToken and preserves item as queued',
    () async {
      final file = File('${tempDir.path}/skew.jpg')
        ..writeAsBytesSync(List<int>.filled(512, 8));
      final store = _InMemoryUploadStore();
      var refreshed = false;

      final gateway = _FakeGateway(
        onInit: (id, size) async {
          throw ApiException('Token expired', statusCode: 401);
        },
        onPartUrls: (_, _) async => const [],
        onPut: (_) async => http.StreamedResponse(const Stream.empty(), 200),
        onConfirm: (_, _) async {},
        onForceRefresh: () async {
          refreshed = true;
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-401', file, name: 'skew.jpg'));
      await worker.drainOnce();

      expect(refreshed, isTrue);
      expect(store.rows['att-401']!.status, MediaUploadStatus.queued);
    },
  );

  test(
    '426 Upgrade Required is not permanent and preserves item as queued',
    () async {
      expect(MediaUploadQueueWorker.isPermanentClientStatus(426), isFalse);

      final file = File('${tempDir.path}/gate.jpg')
        ..writeAsBytesSync(List<int>.filled(512, 5));
      final store = _InMemoryUploadStore();

      final gateway = _FakeGateway(
        onInit: (id, size) async {
          throw ApiException('Update required', statusCode: 426);
        },
        onPartUrls: (_, _) async => const [],
        onPut: (_) async => http.StreamedResponse(const Stream.empty(), 200),
        onConfirm: (_, _) async {},
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-426', file, name: 'gate.jpg'));
      await worker.drainOnce();

      expect(store.rows['att-426']!.status, MediaUploadStatus.queued);
    },
  );

  test(
    '410 Gone on confirm clears multipart state and retries cleanly via init',
    () async {
      final file = File('${tempDir.path}/expired.m4a')
        ..writeAsBytesSync(List<int>.filled(512, 6));
      final store = _InMemoryUploadStore();
      var initCalls = 0;
      var return410Once = true;
      var confirmed = false;

      final gateway = _FakeGateway(
        onInit: (id, size) async {
          initCalls++;
          return {
            'attachment_id': id,
            'mode': 'multipart',
            'upload_id': 'u-$initCalls',
            'part_size': 256,
            'total_parts': 2,
            'uploaded_parts': const [],
          };
        },
        onPartUrls: (_, parts) async => [
          for (final p in parts)
            {'part_number': p, 'url': 'https://s3.test/part/$p'},
        ],
        onPut: (req) async {
          final p = int.parse(req.url.pathSegments.last);
          await req.finalize().drain<void>();
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'etag': '"e$p"'},
          );
        },
        onConfirm: (_, _) async {
          if (return410Once) {
            return410Once = false;
            throw ApiException('Multipart upload expired.', statusCode: 410);
          }
          confirmed = true;
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-410', file, name: 'expired.m4a'));
      await worker.drainOnce();
      expect(store.rows['att-410']!.status, MediaUploadStatus.queued);
      expect(store.rows['att-410']!.s3UploadId, isEmpty);
      expect(confirmed, isFalse);

      await worker.drainOnce();
      expect(initCalls, 2);
      expect(confirmed, isTrue);
      expect(store.rows, isEmpty);
    },
  );

  test(
    'media upload waits until parent submission leaves ps_crud before confirming',
    () async {
      final file = File('${tempDir.path}/gated.jpg')
        ..writeAsBytesSync(List<int>.filled(512, 7));
      final store = _InMemoryUploadStore();
      store.pendingSubmissions.add('sub-1');
      var initCalls = 0;

      final gateway = _FakeGateway(
        onInit: (id, size) async {
          initCalls++;
          return {
            'attachment_id': id,
            'mode': 'single',
            'upload_url': 'https://s3.test/single/$id',
          };
        },
        onPartUrls: (_, _) async => const [],
        onPut: (req) async {
          await req.finalize().drain<void>();
          return http.StreamedResponse(const Stream.empty(), 200);
        },
        onConfirm: (_, _) async {},
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-gated', file, name: 'gated.jpg'));
      await worker.drainOnce();
      expect(initCalls, 0);
      expect(store.rows['att-gated']!.status, MediaUploadStatus.queued);
      expect(file.existsSync(), isTrue);

      store.pendingSubmissions.remove('sub-1');
      await worker.drainOnce();
      expect(initCalls, 1);
      expect(store.rows, isEmpty);
      expect(file.existsSync(), isFalse);
    },
  );

  test(
    'switching to Wi-Fi only mid-transfer aborts in-flight PUT and pauses for Wi-Fi',
    () async {
      final file = File('${tempDir.path}/inflight.jpg')
        ..writeAsBytesSync(List<int>.filled(1024, 9));
      final store = _InMemoryUploadStore();
      var policy = MediaUploadNetworkPolicy.anyNetwork;
      final putStarted = Completer<void>();
      final putNeverCompletes = Completer<http.StreamedResponse>();
      var clientClosed = false;

      final gateway = _FakeGateway(
        onInit: (id, size) async => {
          'attachment_id': id,
          'mode': 'single',
          'upload_url': 'https://s3.test/single/$id',
        },
        onPartUrls: (_, _) async => const [],
        onPut: (req) {
          if (!putStarted.isCompleted) putStarted.complete();
          return putNeverCompletes.future;
        },
        onConfirm: (_, _) async {},
        onClientClose: () {
          clientClosed = true;
          if (!putNeverCompletes.isCompleted) {
            putNeverCompletes.completeError(http.ClientException('aborted'));
          }
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: false),
        readPolicy: () => policy,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-abort', file, name: 'inflight.jpg'));
      final drainFuture = worker.drainOnce();
      await putStarted.future;

      policy = MediaUploadNetworkPolicy.wifiOnlyAll;
      worker.onPolicyOrConnectivityChanged();
      await drainFuture;

      expect(clientClosed, isTrue);
      expect(store.rows['att-abort']!.status, MediaUploadStatus.pausedWifi);
    },
  );

  test(
    'switching to Wi-Fi only during initUpload pauses single upload before PUT',
    () async {
      final file = File('${tempDir.path}/init-race.jpg')
        ..writeAsBytesSync(List<int>.filled(1024, 5));
      final store = _InMemoryUploadStore();
      var policy = MediaUploadNetworkPolicy.anyNetwork;
      var putCalls = 0;

      final gateway = _FakeGateway(
        onInit: (id, size) async {
          policy = MediaUploadNetworkPolicy.wifiOnlyAll;
          return {
            'attachment_id': id,
            'mode': 'single',
            'upload_url': 'https://s3.test/single/$id',
          };
        },
        onPartUrls: (_, _) async => const [],
        onPut: (req) async {
          putCalls++;
          return http.StreamedResponse(const Stream.empty(), 200);
        },
        onConfirm: (_, _) async {},
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: false),
        readPolicy: () => policy,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-init-race', file, name: 'init-race.jpg'));
      await worker.drainOnce();

      expect(putCalls, 0);
      expect(store.rows['att-init-race']!.status, MediaUploadStatus.pausedWifi);
    },
  );

  test(
    'tus resumes from exact Upload-Offset after mid-chunk SocketException using 256 KiB chunks in Low Coverage Mode',
    () async {
      final totalBytes = 700 * 1024;
      final file = File('${tempDir.path}/voice_2g.m4a')
        ..writeAsBytesSync(List<int>.generate(totalBytes, (i) => i & 0xff));
      final store = _InMemoryUploadStore();
      var serverOffset = 0;
      var dropChunk2 = true;
      final patchSizes = <int>[];
      var headCount = 0;
      var postCount = 0;
      final assembled = <int>[];

      final gateway = _FakeGateway(
        tusEndpoint: 'https://fieldlog.test/tus/',
        onInit: (_, _) async => throw StateError('legacy init should not be called'),
        onPartUrls: (_, _) async => const [],
        onConfirm: (_, _) async {},
        onPut: (req) async {
          if (req.method == 'POST') {
            postCount++;
            expect(req.headers['Tus-Resumable'], '1.0.0');
            expect(req.headers['Upload-Length'], '$totalBytes');
            expect(req.headers['Authorization'], 'Bearer jwt-token');
            expect(req.headers['Upload-Metadata'], contains('attachment_id '));
            await req.finalize().drain<void>();
            return http.StreamedResponse(
              const Stream.empty(),
              201,
              headers: {
                'tus-resumable': '1.0.0',
                'location': 'https://fieldlog.test/tus/submissions/att-tus-1.m4a+mp1',
              },
            );
          }
          if (req.method == 'HEAD') {
            headCount++;
            await req.finalize().drain<void>();
            return http.StreamedResponse(
              const Stream.empty(),
              200,
              headers: {
                'tus-resumable': '1.0.0',
                'upload-offset': '$serverOffset',
                'upload-length': '$totalBytes',
              },
            );
          }
          if (req.method == 'PATCH') {
            final reqOffset = int.parse(req.headers['Upload-Offset']!);
            final body = await req.finalize().expand((c) => c).toList();
            if (reqOffset == 256 * 1024 && dropChunk2) {
              dropChunk2 = false;
              throw const SocketException('2G tower drop mid-chunk');
            }
            expect(reqOffset, serverOffset);
            patchSizes.add(body.length);
            assembled.addAll(body);
            serverOffset += body.length;
            return http.StreamedResponse(
              const Stream.empty(),
              204,
              headers: {
                'tus-resumable': '1.0.0',
                'upload-offset': '$serverOffset',
              },
            );
          }
          throw StateError('Unexpected method ${req.method}');
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        readLowCoverageMode: () => true,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-tus-1', file));

      await worker.drainOnce();
      expect(postCount, 1);
      expect(headCount, 0);
      expect(patchSizes, [256 * 1024]);
      expect(store.rows['att-tus-1']!.status, MediaUploadStatus.queued);
      expect(store.rows['att-tus-1']!.uploadedOffset, 256 * 1024);
      expect(
        store.rows['att-tus-1']!.tusUploadUrl,
        'https://fieldlog.test/tus/submissions/att-tus-1.m4a+mp1',
      );

      await worker.drainOnce();
      expect(postCount, 1);
      expect(headCount, 1);
      expect(patchSizes, [256 * 1024, 256 * 1024, 188 * 1024]);
      expect(assembled, List<int>.generate(totalBytes, (i) => i & 0xff));
      expect(store.rows, isEmpty);
      expect(file.existsSync(), isFalse);
    },
  );

  test(
    'tus reconciles 409 Conflict offset mismatch via HEAD and restarts cleanly on 404/410 expired upload',
    () async {
      final totalBytes = 512 * 1024;
      final file = File('${tempDir.path}/reconcile.m4a')
        ..writeAsBytesSync(List<int>.filled(totalBytes, 7));
      final store = _InMemoryUploadStore();
      var serverOffset = 256 * 1024;
      var return410Once = true;
      var return409Once = true;
      var postCalls = 0;

      final gateway = _FakeGateway(
        tusEndpoint: 'https://fieldlog.test/tus/',
        onInit: (_, _) async => throw StateError('unexpected legacy init'),
        onPartUrls: (_, _) async => const [],
        onConfirm: (_, _) async {},
        onPut: (req) async {
          await req.finalize().drain<void>();
          if (req.method == 'HEAD') {
            if (return410Once) {
              return410Once = false;
              return http.StreamedResponse(
                const Stream.empty(),
                410,
                headers: {'tus-resumable': '1.0.0'},
              );
            }
            return http.StreamedResponse(
              const Stream.empty(),
              200,
              headers: {
                'tus-resumable': '1.0.0',
                'upload-offset': '$serverOffset',
              },
            );
          }
          if (req.method == 'POST') {
            postCalls++;
            serverOffset = 0;
            return http.StreamedResponse(
              const Stream.empty(),
              201,
              headers: {
                'tus-resumable': '1.0.0',
                'location': 'https://fieldlog.test/tus/submissions/fresh-$postCalls.m4a+mp',
              },
            );
          }
          if (req.method == 'PATCH') {
            final reqOffset = int.parse(req.headers['Upload-Offset']!);
            if (return409Once) {
              return409Once = false;
              serverOffset = 256 * 1024;
              return http.StreamedResponse(
                const Stream.empty(),
                409,
                headers: {'tus-resumable': '1.0.0'},
              );
            }
            expect(reqOffset, serverOffset);
            serverOffset += 256 * 1024;
            return http.StreamedResponse(
              const Stream.empty(),
              204,
              headers: {
                'tus-resumable': '1.0.0',
                'upload-offset': '$serverOffset',
              },
            );
          }
          throw StateError('Unexpected ${req.method}');
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: false),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(
        PendingUploadItem(
          attachmentId: 'att-410-409',
          submissionId: 'sub-1',
          sessionId: 1,
          fieldKey: 'recording',
          localPath: file.path,
          originalName: 'reconcile.m4a',
          contentType: 'audio/mp4',
          fileSize: totalBytes,
          s3UploadId: '',
          partSize: 0,
          completedPartsJson: '[]',
          tusUploadUrl: 'https://fieldlog.test/tus/expired-url',
          uploadedOffset: 128 * 1024,
          status: MediaUploadStatus.queued,
          retryCount: 0,
          lastError: '',
          createdAt: '2026-11-26T00:00:00Z',
        ),
      );

      await worker.drainOnce();
      expect(postCalls, 1);
      expect(serverOffset, totalBytes);
      expect(store.rows, isEmpty);
    },
  );

  test(
    'tus upload reported complete by HEAD is only removed after the server confirms it',
    () async {
      final totalBytes = 300 * 1024;
      final file = File('${tempDir.path}/finished_on_tusd.m4a')
        ..writeAsBytesSync(List<int>.filled(totalBytes, 5));
      final store = _InMemoryUploadStore();
      final confirmCalls = <String>[];
      var confirmFails = true;
      var patchCalls = 0;

      final gateway = _FakeGateway(
        tusEndpoint: 'https://fieldlog.test/tus/',
        onInit: (_, _) async => throw StateError('legacy init should not be called'),
        onPartUrls: (_, _) async => const [],
        onConfirm: (id, parts) async {
          confirmCalls.add(id);
          expect(parts, isNull);
          if (confirmFails) {
            confirmFails = false;
            throw ApiException('Server error during upload confirm.', statusCode: 502);
          }
        },
        onPut: (req) async {
          await req.finalize().drain<void>();
          if (req.method == 'HEAD') {
            return http.StreamedResponse(
              const Stream.empty(),
              200,
              headers: {
                'tus-resumable': '1.0.0',
                'upload-offset': '$totalBytes',
                'upload-length': '$totalBytes',
              },
            );
          }
          if (req.method == 'PATCH') patchCalls++;
          throw StateError('Unexpected ${req.method}');
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(
        PendingUploadItem(
          attachmentId: 'att-hook-failed',
          submissionId: 'sub-1',
          sessionId: 1,
          fieldKey: 'recording',
          localPath: file.path,
          originalName: 'finished_on_tusd.m4a',
          contentType: 'audio/mp4',
          fileSize: totalBytes,
          s3UploadId: '',
          partSize: 0,
          completedPartsJson: '[]',
          tusUploadUrl: 'https://fieldlog.test/tus/submissions/done.m4a+mp',
          uploadedOffset: 256 * 1024,
          status: MediaUploadStatus.queued,
          retryCount: 0,
          lastError: '',
          createdAt: '2026-11-27T00:00:00Z',
        ),
      );

      await worker.drainOnce();
      expect(confirmCalls, ['att-hook-failed']);
      expect(store.rows['att-hook-failed']!.status, MediaUploadStatus.queued);
      expect(file.existsSync(), isTrue);

      await worker.drainOnce();
      expect(confirmCalls, ['att-hook-failed', 'att-hook-failed']);
      expect(patchCalls, 0);
      expect(store.rows, isEmpty);
      expect(file.existsSync(), isFalse);
    },
  );

  test(
    'tus adaptive chunk size steps down to 128 KiB floor after 2 consecutive timeouts',
    () async {
      final totalBytes = 384 * 1024;
      final file = File('${tempDir.path}/timeout_stepdown.m4a')
        ..writeAsBytesSync(List<int>.filled(totalBytes, 3));
      final store = _InMemoryUploadStore();
      var timeoutsLeft = 2;
      final observedPatchLengths = <int>[];
      var serverOffset = 0;

      final gateway = _FakeGateway(
        tusEndpoint: 'https://fieldlog.test/tus/',
        onInit: (_, _) async => throw StateError('unexpected legacy init'),
        onPartUrls: (_, _) async => const [],
        onConfirm: (_, _) async {},
        onPut: (req) async {
          if (req.method == 'POST') {
            await req.finalize().drain<void>();
            return http.StreamedResponse(
              const Stream.empty(),
              201,
              headers: {
                'tus-resumable': '1.0.0',
                'location': 'https://fieldlog.test/tus/stepdown+mp',
              },
            );
          }
          if (req.method == 'HEAD') {
            await req.finalize().drain<void>();
            return http.StreamedResponse(
              const Stream.empty(),
              200,
              headers: {
                'tus-resumable': '1.0.0',
                'upload-offset': '$serverOffset',
              },
            );
          }
          if (req.method == 'PATCH') {
            final len = await req.finalize().fold<int>(0, (s, c) => s + c.length);
            observedPatchLengths.add(len);
            if (timeoutsLeft > 0) {
              timeoutsLeft--;
              throw TimeoutException('2G stall');
            }
            serverOffset += len;
            return http.StreamedResponse(
              const Stream.empty(),
              204,
              headers: {
                'tus-resumable': '1.0.0',
                'upload-offset': '$serverOffset',
              },
            );
          }
          throw StateError('Unexpected ${req.method}');
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: false),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        readLowCoverageMode: () => true,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      expect(worker.currentChunkSize(), MediaUploadQueueWorker.tusChunkSizeLowCoverage);
      await store.insert(_item('att-stepdown', file));

      await worker.drainOnce();
      await worker.drainOnce();
      expect(worker.currentChunkSize(), MediaUploadQueueWorker.tusChunkSizeMinFloor);

      await worker.drainOnce();
      expect(
        observedPatchLengths,
        [256 * 1024, 256 * 1024, 128 * 1024, 128 * 1024, 128 * 1024],
      );
      expect(store.rows, isEmpty);
    },
  );

  test(
    'tus falls back to legacy initUpload when server does not speak tus (no Tus-Resumable header)',
    () async {
      final file = File('${tempDir.path}/fallback.jpg')
        ..writeAsBytesSync(List<int>.filled(1024, 5));
      final store = _InMemoryUploadStore();
      var legacyInitCalled = false;
      var legacyConfirmCalled = false;

      final gateway = _FakeGateway(
        tusEndpoint: 'https://legacy.test/tus/',
        onInit: (id, size) async {
          legacyInitCalled = true;
          return {
            'attachment_id': id,
            'mode': 'single',
            'upload_url': 'https://s3.test/single/$id',
          };
        },
        onPartUrls: (_, _) async => const [],
        onConfirm: (_, _) async => legacyConfirmCalled = true,
        onPut: (req) async {
          await req.finalize().drain<void>();
          if (req.method == 'POST') {
            return http.StreamedResponse(const Stream.empty(), 404);
          }
          return http.StreamedResponse(const Stream.empty(), 200);
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: (_) {},
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-fallback', file, name: 'fallback.jpg', contentType: 'image/jpeg'));
      await worker.drainOnce();

      expect(legacyInitCalled, isTrue);
      expect(legacyConfirmCalled, isTrue);
      expect(store.rows, isEmpty);
    },
  );

  test(
    'tus handles 400 pre-finish rejection as failed_permanent and 409 already confirmed as done',
    () async {
      final badFile = File('${tempDir.path}/bad.png')
        ..writeAsBytesSync(List<int>.filled(512, 1));
      final dupFile = File('${tempDir.path}/dup.png')
        ..writeAsBytesSync(List<int>.filled(512, 2));
      final store = _InMemoryUploadStore();
      final userErrors = <String>[];

      final gateway = _FakeGateway(
        tusEndpoint: 'https://fieldlog.test/tus/',
        onInit: (_, _) async => throw StateError('unexpected legacy init'),
        onPartUrls: (_, _) async => const [],
        onConfirm: (_, _) async {},
        onPut: (req) async {
          await req.finalize().drain<void>();
          if (req.method == 'POST') {
            final meta = req.headers['Upload-Metadata'] ?? '';
            if (meta.contains(base64Encode(utf8.encode('att-dup')))) {
              return http.StreamedResponse(
                Stream.value(utf8.encode('{"status":"confirmed","detail":"Already confirmed."}')),
                409,
                headers: {'tus-resumable': '1.0.0'},
              );
            }
            return http.StreamedResponse(
              const Stream.empty(),
              201,
              headers: {
                'tus-resumable': '1.0.0',
                'location': 'https://fieldlog.test/tus/submissions/bad.png+mp',
              },
            );
          }
          if (req.method == 'PATCH') {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"detail":"Content type not allowed."}')),
              400,
              headers: {'tus-resumable': '1.0.0'},
            );
          }
          throw StateError('Unexpected ${req.method}');
        },
      );

      final worker = MediaUploadQueueWorker(
        store: store,
        gateway: gateway,
        readConnectivity: () =>
            const ConnectivityState(isOnline: true, isOnWifi: true),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        reportUserError: userErrors.add,
        reportError: (_, {attachmentId, statusCode}) async {},
      );
      addTearDown(worker.dispose);

      await store.insert(_item('att-bad-magic', badFile, name: 'bad.png', contentType: 'image/png'));
      await store.insert(_item('att-dup', dupFile, name: 'dup.png', contentType: 'image/png'));

      await worker.drainOnce();

      expect(store.rows['att-bad-magic']!.status, MediaUploadStatus.failedPermanent);
      expect(store.rows['att-bad-magic']!.lastError, 'Content type not allowed.');
      expect(store.rows.containsKey('att-dup'), isFalse);
      expect(dupFile.existsSync(), isFalse);
      expect(userErrors, hasLength(1));
    },
  );

  test(
    'Low Coverage Mode selects 48 kbps mono audio, 1600px/80 photos, and 256 KiB vs 4 MiB Wi-Fi chunks',
    () {
      final lowAudio = AudioService.recordingConfig(lowCoverage: true);
      final stdAudio = AudioService.recordingConfig(lowCoverage: false);
      expect(lowAudio.bitRate, 48000);
      expect(lowAudio.sampleRate, 24000);
      expect(lowAudio.numChannels, 1);
      expect(stdAudio.bitRate, 128000);
      expect(stdAudio.sampleRate, 44100);

      final lowPhoto = FileFieldWidget.imagePickSettings(lowCoverage: true);
      final stdPhoto = FileFieldWidget.imagePickSettings(lowCoverage: false);
      expect(lowPhoto.maxWidth, 1600);
      expect(lowPhoto.imageQuality, 80);
      expect(stdPhoto.maxWidth, 2048);
      expect(stdPhoto.imageQuality, 85);

      var lowCoverage = false;
      var onWifi = true;
      final worker = MediaUploadQueueWorker(
        store: _InMemoryUploadStore(),
        gateway: _FakeGateway(
          onInit: (_, _) async => {},
          onPartUrls: (_, _) async => const [],
          onConfirm: (_, _) async {},
          onPut: (_) async => http.StreamedResponse(const Stream.empty(), 200),
        ),
        readConnectivity: () => ConnectivityState(isOnline: true, isOnWifi: onWifi),
        readPolicy: () => MediaUploadNetworkPolicy.anyNetwork,
        readLowCoverageMode: () => lowCoverage,
      );
      addTearDown(worker.dispose);

      expect(worker.currentChunkSize(), 4 * 1024 * 1024);
      lowCoverage = true;
      expect(worker.currentChunkSize(), 256 * 1024);
      lowCoverage = false;
      onWifi = false;
      expect(worker.currentChunkSize(), 256 * 1024);
    },
  );
}
