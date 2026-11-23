import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldlog_mobile/services/audio_service.dart';
import 'package:fieldlog_mobile/widgets/field_widgets/file_field_widget.dart';

class _FakeAudioBackend implements AudioBackend {
  bool micPermission = true;
  bool playbackStarted = false;
  bool recordingPaused = false;
  String? activeRecordingPath;
  Future<PickedAudioFile?> Function(String destBase)? onPickAudio;
  Future<RecordedAudio?> Function(String path)? onStopRecording;

  @override
  void setOnPlaybackComplete(VoidCallback? callback) {}

  @override
  Future<bool> hasMicPermission() async => micPermission;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<PickedAudioFile?> pickAudioFile({
    required String destinationBasePath,
  }) async {
    return onPickAudio?.call(destinationBasePath);
  }

  @override
  Future<void> startRecording({required String path}) async {
    activeRecordingPath = path;
    recordingPaused = false;
  }

  @override
  Future<void> pauseRecording() async {
    recordingPaused = true;
  }

  @override
  Future<void> resumeRecording() async {
    recordingPaused = false;
  }

  @override
  Future<RecordedAudio?> stopRecording() async {
    final path = activeRecordingPath;
    activeRecordingPath = null;
    if (path == null) return null;
    return onStopRecording?.call(path);
  }

  @override
  Future<void> cancelRecording() async {
    activeRecordingPath = null;
  }

  @override
  Future<double> getRecordingAmplitude() async => 0.4;

  @override
  Future<int> startPlayback({required String path}) async {
    playbackStarted = true;
    return 3000;
  }

  @override
  Future<void> pausePlayback() async {}

  @override
  Future<void> resumePlayback() async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<PlaybackStatus> getPlaybackStatus() async => const PlaybackStatus(
    isPlaying: true,
    positionMs: 1000,
    durationMs: 3000,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tempDir;
  late _FakeAudioBackend fakeBackend;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fieldlog_audio_test_');
    fakeBackend = _FakeAudioBackend();
    AudioService.backend = fakeBackend;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
  });

  tearDown(() async {
    AudioService.backend = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  group('FileFieldWidget accepts modes', () {
    testWidgets('default (null accepts) shows photo-only prompt and options', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(FileFieldWidget(label: 'Specimen Photo', onChanged: (_) {})),
      );

      expect(find.text('Add photo'), findsOneWidget);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Photo Library'), findsOneWidget);
      expect(find.text('Record Audio'), findsNothing);
      expect(find.text('Choose Audio File'), findsNothing);
    });

    testWidgets('audio accepts shows audio-only prompt and options', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          FileFieldWidget(
            label: 'Bird Call',
            accepts: 'audio',
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Add audio'), findsOneWidget);

      await tester.tap(find.text('Add audio'));
      await tester.pumpAndSettle();

      expect(find.text('Record Audio'), findsOneWidget);
      expect(find.text('Choose Audio File'), findsOneWidget);
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Photo Library'), findsNothing);
    });

    testWidgets('image,audio accepts shows both photo and audio options', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          FileFieldWidget(
            label: 'Field Media',
            accepts: 'image,audio',
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Add photo or audio'), findsOneWidget);

      await tester.tap(find.text('Add photo or audio'));
      await tester.pumpAndSettle();

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Photo Library'), findsOneWidget);
      expect(find.text('Record Audio'), findsOneWidget);
      expect(find.text('Choose Audio File'), findsOneWidget);
    });
  });

  group('FileFieldWidget audio file pick and recording', () {
    testWidgets('picking a valid audio file renders preview and emits value', (
      tester,
    ) async {
      Map<String, dynamic>? emitted;
      fakeBackend.onPickAudio = (destBase) async {
        final out = File('$destBase.m4a');
        out.writeAsBytesSync(List<int>.filled(4096, 1));
        return PickedAudioFile(
          path: out.path,
          name: 'dawn_chorus.m4a',
          size: 4096,
        );
      };

      await tester.pumpWidget(
        wrap(
          FileFieldWidget(
            label: 'Bird Call',
            accepts: 'audio',
            onChanged: (v) => emitted = v,
          ),
        ),
      );

      await tester.tap(find.text('Add audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose Audio File'));
      await tester.pumpAndSettle();

      expect(find.text('dawn_chorus.m4a'), findsOneWidget);
      expect(find.text('4 KB'), findsOneWidget);
      expect(emitted, isNotNull);
      expect(emitted!['original_name'], 'dawn_chorus.m4a');
      expect(emitted!['file_size'], 4096);
      expect((emitted!['file_name'] as String).endsWith('.m4a'), isTrue);

      await tester.tap(find.byTooltip('Remove audio'));
      await tester.pumpAndSettle();
      expect(emitted, isNull);
      expect(find.text('Add audio'), findsOneWidget);
    });

    testWidgets('recording audio saves .m4a file and supports playback toggle', (
      tester,
    ) async {
      Map<String, dynamic>? emitted;
      fakeBackend.onStopRecording = (path) async {
        final out = File(path);
        out.writeAsBytesSync(List<int>.filled(8192, 2));
        return RecordedAudio(path: out.path, size: 8192, durationMs: 3000);
      };

      await tester.pumpWidget(
        wrap(
          FileFieldWidget(
            label: 'Voice Note',
            accepts: 'audio',
            onChanged: (v) => emitted = v,
          ),
        ),
      );

      await tester.tap(find.text('Add audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Audio'));
      await tester.pump();

      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(fakeBackend.recordingPaused, isTrue);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(fakeBackend.recordingPaused, isFalse);
      expect(find.text('Pause'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(emitted, isNotNull);
      expect((emitted!['file_name'] as String).endsWith('.m4a'), isTrue);
      expect(
        (emitted!['original_name'] as String).startsWith('recording_'),
        isTrue,
      );
      expect(emitted!['file_size'], 8192);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(fakeBackend.playbackStarted, isTrue);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });

    testWidgets('rejects unsupported file extension with error snackbar', (
      tester,
    ) async {
      Map<String, dynamic>? emitted;
      fakeBackend.onPickAudio = (destBase) async {
        final out = File('$destBase.txt');
        out.writeAsStringSync('not audio');
        return PickedAudioFile(path: out.path, name: 'notes.txt', size: 9);
      };

      await tester.pumpWidget(
        wrap(
          FileFieldWidget(
            label: 'Audio',
            accepts: 'audio',
            onChanged: (v) => emitted = v,
          ),
        ),
      );

      await tester.tap(find.text('Add audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose Audio File'));
      await tester.pumpAndSettle();

      expect(emitted, isNull);
      expect(find.textContaining('Unsupported audio format'), findsOneWidget);
    });

    testWidgets('shows permission snackbar when mic permission is denied', (
      tester,
    ) async {
      fakeBackend.micPermission = false;

      await tester.pumpWidget(
        wrap(
          FileFieldWidget(
            label: 'Voice Note',
            accepts: 'audio',
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('Add audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Audio'));
      await tester.pumpAndSettle();

      expect(
        find.text('Microphone permission is required to record audio.'),
        findsOneWidget,
      );
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
