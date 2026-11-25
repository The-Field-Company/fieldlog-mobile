import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldlog_mobile/services/audio_service.dart';
import 'package:fieldlog_mobile/widgets/field_widgets/file_field_widget.dart';
import 'package:fieldlog_mobile/widgets/formkit_renderer.dart';

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

    testWidgets(
      'playing a second audio field interrupts the first and blocks concurrent recording',
      (tester) async {
        final fileA = File('${tempDir.path}/a.m4a')
          ..writeAsBytesSync(List<int>.filled(2048, 1));
        final fileB = File('${tempDir.path}/b.m4a')
          ..writeAsBytesSync(List<int>.filled(2048, 2));

        await tester.pumpWidget(
          wrap(
            Column(
              children: [
                FileFieldWidget(
                  label: 'Audio A',
                  accepts: 'audio',
                  initialValue: {
                    'file_path': fileA.path,
                    'file_name': 'a.m4a',
                    'original_name': 'a.m4a',
                    'file_size': 2048,
                  },
                  onChanged: (_) {},
                ),
                FileFieldWidget(
                  label: 'Audio B',
                  accepts: 'audio',
                  initialValue: {
                    'file_path': fileB.path,
                    'file_name': 'b.m4a',
                    'original_name': 'b.m4a',
                    'file_size': 2048,
                  },
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        );

        final playButtons = find.byIcon(Icons.play_arrow_rounded);
        expect(playButtons, findsNWidgets(2));

        await tester.tap(playButtons.first);
        await tester.pump();
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

        // Playing Audio B resets Audio A back to play icon.
        await tester.tap(find.byIcon(Icons.play_arrow_rounded));
        await tester.pump();
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      },
    );

    testWidgets('blocks starting a second recording while one is active', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              FileFieldWidget(
                label: 'Note 1',
                accepts: 'audio',
                onChanged: (_) {},
              ),
              FileFieldWidget(
                label: 'Note 2',
                accepts: 'audio',
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Add audio').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Audio'));
      await tester.pump();

      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.text('Add audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Record Audio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('Finish or discard the other active recording first.'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('blocks playback while another field is recording', (
      tester,
    ) async {
      final clip = File('${tempDir.path}/clip.m4a')
        ..writeAsBytesSync(List<int>.filled(2048, 3));

      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              FileFieldWidget(
                label: 'Recorder Field',
                accepts: 'audio',
                onChanged: (_) {},
              ),
              FileFieldWidget(
                label: 'Playback Field',
                accepts: 'audio',
                initialValue: {
                  'file_path': clip.path,
                  'file_name': 'clip.m4a',
                  'original_name': 'clip.m4a',
                  'file_size': 2048,
                },
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Add audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record Audio'));
      await tester.pump();
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fakeBackend.playbackStarted, isFalse);
      expect(
        find.text(
          'Finish or discard the active recording before playing audio.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('clears required validation error after picking an audio file', (
      tester,
    ) async {
      final formKey = GlobalKey<FormState>();
      fakeBackend.onPickAudio = (destBase) async {
        final out = File('$destBase.m4a');
        out.writeAsBytesSync(List<int>.filled(1024, 5));
        return PickedAudioFile(path: out.path, name: 'bird.m4a', size: 1024);
      };

      await tester.pumpWidget(
        wrap(
          Form(
            key: formKey,
            child: FileFieldWidget(
              label: 'Voice Note',
              accepts: 'audio',
              isRequired: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Voice Note is required'), findsOneWidget);

      await tester.tap(find.text('Add audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose Audio File'));
      await tester.pumpAndSettle();

      expect(find.text('Voice Note is required'), findsNothing);
    });

    testWidgets(
      'blocks removing an attached audio file while form submission is in flight',
      (tester) async {
        final submitCompleter = Completer<void>();
        Map<String, dynamic>? submitted;
        fakeBackend.onPickAudio = (destBase) async {
          final out = File('$destBase.m4a');
          out.writeAsBytesSync(List<int>.filled(2048, 9));
          return PickedAudioFile(
            path: out.path,
            name: 'field_clip.m4a',
            size: 2048,
          );
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FormkitRenderer(
                components: const [
                  {
                    'key': 'audio_note',
                    'label': 'Audio Note',
                    'type': 'file',
                    'accepts': 'audio',
                  },
                ],
                onSubmit: (data) {
                  submitted = data;
                  return submitCompleter.future;
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Add audio'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose Audio File'));
        await tester.pumpAndSettle();

        expect(find.text('field_clip.m4a'), findsOneWidget);

        await tester.tap(find.text('Submit'));
        await tester.pump();

        expect(submitted, isNotNull);
        final filePath =
            (submitted!['audio_note'] as Map<String, dynamic>)['file_path']
                as String;
        expect(File(filePath).existsSync(), isTrue);

        // Attempt to remove the attachment while submission is awaiting GPS/DB.
        await tester.tap(
          find.byIcon(Icons.close_rounded),
          warnIfMissed: false,
        );
        await tester.pump();

        expect(File(filePath).existsSync(), isTrue);
        expect(find.text('field_clip.m4a'), findsOneWidget);

        submitCompleter.complete();
        await tester.pump();
      },
    );
  });
}
