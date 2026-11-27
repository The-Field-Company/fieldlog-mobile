import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fieldlog_mobile/services/media_upload_queue_service.dart';

class _FakeStreamingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      onSend;
  bool closed = false;

  _FakeStreamingClient(this.onSend);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('upload_streaming_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('MediaUploadQueueWorker streaming PUT deadlines', () {
    test('totalUploadDeadlineForBytes accommodates 2G speeds for 5 MiB parts', () {
      expect(
        MediaUploadQueueWorker.totalUploadDeadlineForBytes(256 * 1024),
        const Duration(seconds: 300),
      );
      final fiveMbDeadline = MediaUploadQueueWorker.totalUploadDeadlineForBytes(
        5 * 1024 * 1024,
      );
      // 5 MiB on 50–100 kbps 2G takes ~7–15 minutes; deadline must exceed 1000s.
      expect(fiveMbDeadline.inSeconds, greaterThan(1000));
    });

    test(
      'allows an actively progressing upload to exceed stallTimeout and captures ETag',
      () async {
        final file = File('${tempDir.path}/audio.m4a')
          ..writeAsBytesSync(List<int>.filled(256 * 1024, 7));
        final client = _FakeStreamingClient((request) async {
          final stream = request.finalize();
          var received = 0;
          await for (final chunk in stream) {
            received += chunk.length;
            await Future<void>.delayed(const Duration(milliseconds: 35));
          }
          expect(received, file.lengthSync());
          return http.StreamedResponse(
            const Stream.empty(),
            200,
            headers: {'etag': '"abc123"'},
          );
        });

        final result = await MediaUploadQueueWorker.sendStreamingPutAttempt(
          client: client,
          url: Uri.parse('https://example.test/upload'),
          file: file,
          start: 0,
          end: file.lengthSync(),
          contentType: 'audio/mp4',
          stallTimeout: const Duration(milliseconds: 100),
          totalDeadline: const Duration(seconds: 5),
        );

        expect(result.statusCode, 200);
        expect(result.etag, '"abc123"');
        expect(client.closed, isTrue);
      },
    );

    test(
      'times out and closes client when response body stalls',
      () async {
        final file = File('${tempDir.path}/small.m4a')
          ..writeAsBytesSync(List<int>.filled(1024, 1));
        final bodyController = StreamController<List<int>>();
        addTearDown(bodyController.close);

        final client = _FakeStreamingClient((request) async {
          await request.finalize().drain<void>();
          return http.StreamedResponse(bodyController.stream, 200);
        });

        await expectLater(
          MediaUploadQueueWorker.sendStreamingPutAttempt(
            client: client,
            url: Uri.parse('https://example.test/upload'),
            file: file,
            start: 0,
            end: file.lengthSync(),
            contentType: 'audio/mp4',
            stallTimeout: const Duration(milliseconds: 80),
            totalDeadline: const Duration(seconds: 5),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(client.closed, isTrue);
      },
    );

    test(
      'enforces totalDeadline even when transfer keeps trickling',
      () async {
        final file = File('${tempDir.path}/trickle.m4a')
          ..writeAsBytesSync(List<int>.filled(512 * 1024, 2));
        final client = _FakeStreamingClient((request) async {
          final stream = request.finalize();
          await for (final _ in stream) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
          return http.StreamedResponse(const Stream.empty(), 200);
        });

        await expectLater(
          MediaUploadQueueWorker.sendStreamingPutAttempt(
            client: client,
            url: Uri.parse('https://example.test/upload'),
            file: file,
            start: 0,
            end: file.lengthSync(),
            contentType: 'audio/mp4',
            stallTimeout: const Duration(milliseconds: 200),
            totalDeadline: const Duration(milliseconds: 120),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(client.closed, isTrue);
      },
    );
  });
}
