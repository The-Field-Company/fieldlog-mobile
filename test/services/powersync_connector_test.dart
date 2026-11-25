import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fieldlog_mobile/services/powersync_connector.dart';

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
    tempDir = Directory.systemTemp.createTempSync('powersync_connector_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('FieldLogConnector upload deadlines', () {
    test('totalUploadDeadlineForBytes scales above 300s for large files', () {
      expect(
        FieldLogConnector.totalUploadDeadlineForBytes(2 * 1024 * 1024),
        const Duration(seconds: 300),
      );
      final fiftyMbDeadline = FieldLogConnector.totalUploadDeadlineForBytes(
        50 * 1024 * 1024,
      );
      // 50 MiB at 1 Mbit/s takes ~419s; deadline must comfortably exceed that.
      expect(fiftyMbDeadline.inSeconds, greaterThan(500));
    });

    test(
      'allows an actively progressing upload to exceed stallTimeout',
      () async {
        // Create a file large enough to span multiple 64 KiB openRead chunks.
        final file = File('${tempDir.path}/audio.m4a')
          ..writeAsBytesSync(List<int>.filled(256 * 1024, 7));
        final client = _FakeStreamingClient((request) async {
          final stream = request.finalize();
          var received = 0;
          await for (final chunk in stream) {
            received += chunk.length;
            // Pace chunk consumption slower than stallTimeout in total,
            // while staying under stallTimeout per chunk.
            await Future<void>.delayed(const Duration(milliseconds: 35));
          }
          expect(received, file.lengthSync());
          return http.StreamedResponse(const Stream.empty(), 200);
        });

        final statusCode = await FieldLogConnector.sendStreamingPutAttempt(
          client: client,
          url: Uri.parse('https://example.test/upload'),
          file: file,
          contentLength: file.lengthSync(),
          contentType: 'audio/mp4',
          stallTimeout: const Duration(milliseconds: 100),
          totalDeadline: const Duration(seconds: 5),
        );

        expect(statusCode, 200);
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
          FieldLogConnector.sendStreamingPutAttempt(
            client: client,
            url: Uri.parse('https://example.test/upload'),
            file: file,
            contentLength: file.lengthSync(),
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
          FieldLogConnector.sendStreamingPutAttempt(
            client: client,
            url: Uri.parse('https://example.test/upload'),
            file: file,
            contentLength: file.lengthSync(),
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
