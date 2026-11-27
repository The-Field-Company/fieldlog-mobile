import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import '../utils/attachment_accepts.dart';
import 'location_service.dart';

class AudioPickException implements Exception {
  final String message;

  const AudioPickException(this.message);

  @override
  String toString() => message;
}

class PickedAudioFile {
  final String path;
  final String name;
  final int size;

  const PickedAudioFile({
    required this.path,
    required this.name,
    required this.size,
  });
}

class RecordedAudio {
  final String path;
  final int size;
  final int durationMs;

  const RecordedAudio({
    required this.path,
    required this.size,
    required this.durationMs,
  });
}

class PlaybackStatus {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;

  const PlaybackStatus({
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
  });
}

abstract class AudioBackend {
  void setOnPlaybackComplete(VoidCallback? callback);
  Future<bool> hasMicPermission();
  Future<bool> openAppSettings();
  Future<PickedAudioFile?> pickAudioFile({required String destinationBasePath});
  Future<void> startRecording({required String path, bool lowCoverage = false});
  Future<void> pauseRecording();
  Future<void> resumeRecording();
  Future<RecordedAudio?> stopRecording();
  Future<void> cancelRecording();
  Future<double> getRecordingAmplitude();
  Future<int> startPlayback({required String path});
  Future<void> pausePlayback();
  Future<void> resumePlayback();
  Future<void> stopPlayback();
  Future<PlaybackStatus> getPlaybackStatus();
}

class _PluginAudioBackend implements AudioBackend {
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  VoidCallback? _onPlaybackComplete;
  String? _recordingPath;
  DateTime? _recordingSegmentStartedAt;
  Duration _recordingAccumulated = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;
  int _positionMs = 0;
  int _durationMs = 0;
  bool _startingPlayback = false;

  AudioRecorder get _audioRecorder => _recorder ??= AudioRecorder();

  AudioPlayer get _audioPlayer {
    if (_player != null) return _player!;
    final player = AudioPlayer();
    player.onPlayerComplete.listen((_) {
      _startingPlayback = false;
      _playerState = PlayerState.completed;
      _positionMs = 0;
      _onPlaybackComplete?.call();
    });
    player.onPlayerStateChanged.listen((state) {
      _playerState = state;
      if (state == PlayerState.playing ||
          state == PlayerState.stopped ||
          state == PlayerState.completed) {
        _startingPlayback = false;
      }
    });
    player.onPositionChanged.listen((pos) {
      _positionMs = pos.inMilliseconds;
    });
    player.onDurationChanged.listen((dur) {
      _durationMs = dur.inMilliseconds;
    });
    _player = player;
    return player;
  }

  @override
  void setOnPlaybackComplete(VoidCallback? callback) {
    _onPlaybackComplete = callback;
  }

  @override
  Future<bool> hasMicPermission() async {
    try {
      return await _audioRecorder.hasPermission();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioService] hasMicPermission failed: $e');
      }
      return false;
    }
  }

  @override
  Future<bool> openAppSettings() => LocationService.openAppSettings();

  @override
  Future<PickedAudioFile?> pickAudioFile({
    required String destinationBasePath,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: audioMimeByExtension.keys.toList(),
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;

    final picked = result.files.single;
    final sourcePath = picked.path;
    if (sourcePath == null || sourcePath.isEmpty) return null;

    final ext = extensionOf(picked.name).isNotEmpty
        ? extensionOf(picked.name)
        : extensionOf(sourcePath);

    // Validate extension and size BEFORE copying potentially large files.
    if (kindForExtension(ext) != AttachmentKind.audio) {
      throw AudioPickException(
        'Unsupported audio format${ext.isNotEmpty ? ' (.$ext)' : ''}. '
        'Supported: M4A, MP3, WAV, OGG, OPUS, WEBM, AAC, FLAC.',
      );
    }

    final sourceFile = File(sourcePath);
    final sourceSize = picked.size > 0 ? picked.size : await sourceFile.length();
    if (sourceSize == 0) {
      throw const AudioPickException('Selected audio file is empty.');
    }
    if (sourceSize > maxAudioBytes) {
      throw AudioPickException(
        'Audio file too large (max ${maxMbForKind(AttachmentKind.audio)} MB).',
      );
    }

    final finalPath = '$destinationBasePath.$ext';
    final saved = await sourceFile.copy(finalPath);
    final size = await saved.length();

    return PickedAudioFile(
      path: saved.path,
      name: picked.name.isNotEmpty ? picked.name : saved.path.split('/').last,
      size: size,
    );
  }

  @override
  Future<void> startRecording({
    required String path,
    bool lowCoverage = false,
  }) async {
    await stopPlayback();
    await _audioRecorder.start(
      AudioService.recordingConfig(lowCoverage: lowCoverage),
      path: path,
    );
    _recordingPath = path;
    _recordingAccumulated = Duration.zero;
    _recordingSegmentStartedAt = DateTime.now();
  }

  @override
  Future<void> pauseRecording() async {
    await _audioRecorder.pause();
    if (_recordingSegmentStartedAt != null) {
      _recordingAccumulated += DateTime.now().difference(
        _recordingSegmentStartedAt!,
      );
      _recordingSegmentStartedAt = null;
    }
  }

  @override
  Future<void> resumeRecording() async {
    await _audioRecorder.resume();
    _recordingSegmentStartedAt = DateTime.now();
  }

  @override
  Future<RecordedAudio?> stopRecording() async {
    var totalDuration = _recordingAccumulated;
    if (_recordingSegmentStartedAt != null) {
      totalDuration += DateTime.now().difference(_recordingSegmentStartedAt!);
    }
    final fallbackPath = _recordingPath;
    _recordingAccumulated = Duration.zero;
    _recordingSegmentStartedAt = null;
    _recordingPath = null;

    final String? stoppedPath;
    try {
      stoppedPath = await _audioRecorder.stop() ?? fallbackPath;
    } catch (_) {
      try {
        await _recorder?.cancel();
      } catch (_) {}
      if (fallbackPath != null && fallbackPath.isNotEmpty) {
        try {
          final partial = File(fallbackPath);
          if (await partial.exists()) await partial.delete();
        } catch (_) {}
      }
      rethrow;
    }
    if (stoppedPath == null || stoppedPath.isEmpty) return null;

    final file = File(stoppedPath);
    if (!await file.exists()) return null;
    final size = await file.length();
    if (size <= 0) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }

    return RecordedAudio(
      path: file.path,
      size: size,
      durationMs: totalDuration.inMilliseconds,
    );
  }

  @override
  Future<void> cancelRecording() async {
    final path = _recordingPath;
    _recordingPath = null;
    _recordingAccumulated = Duration.zero;
    _recordingSegmentStartedAt = null;
    try {
      if (_recorder != null) {
        await _recorder!.cancel();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioService] cancelRecording failed: $e');
      }
    }
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  @override
  Future<double> getRecordingAmplitude() async {
    final recorder = _recorder;
    if (recorder == null) return 0.0;
    try {
      final amp = await recorder.getAmplitude();
      // dBFS typically spans -50 dB (quiet room) to 0 dB (loud).
      return ((amp.current + 50.0) / 50.0).clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Future<int> startPlayback({required String path}) async {
    final player = _audioPlayer;
    await player.stop();
    _positionMs = 0;
    _durationMs = 0;
    _startingPlayback = true;
    try {
      await player.play(DeviceFileSource(path));
    } catch (_) {
      _startingPlayback = false;
      rethrow;
    }
    final duration = await player.getDuration();
    final ms = duration?.inMilliseconds ?? _durationMs;
    if (ms > 0) _durationMs = ms;
    return ms;
  }

  @override
  Future<void> pausePlayback() async {
    _startingPlayback = false;
    await _player?.pause();
  }

  @override
  Future<void> resumePlayback() async {
    _startingPlayback = true;
    try {
      await _player?.resume();
    } catch (_) {
      _startingPlayback = false;
      rethrow;
    }
  }

  @override
  Future<void> stopPlayback() async {
    _startingPlayback = false;
    _positionMs = 0;
    try {
      await _player?.stop();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AudioService] stopPlayback failed: $e');
      }
    }
  }

  @override
  Future<PlaybackStatus> getPlaybackStatus() async {
    final player = _player;
    if (player == null) {
      return const PlaybackStatus(
        isPlaying: false,
        positionMs: 0,
        durationMs: 0,
      );
    }
    try {
      final pos = await player.getCurrentPosition();
      final dur = await player.getDuration();
      final posMs = pos?.inMilliseconds ?? _positionMs;
      final durMs = dur?.inMilliseconds ?? _durationMs;
      return PlaybackStatus(
        isPlaying: _startingPlayback ||
            _playerState == PlayerState.playing ||
            player.state == PlayerState.playing,
        positionMs: posMs,
        durationMs: durMs,
      );
    } catch (_) {
      return const PlaybackStatus(
        isPlaying: false,
        positionMs: 0,
        durationMs: 0,
      );
    }
  }
}

/// Wrapper around `file_picker`, `record`, and `audioplayers` for audio field
/// selection, in-app AAC `.m4a` recording, and playback preview.
///
/// Tracks active recording and playback owners so multiple `FileFieldWidget`
/// instances on the same form never clobber each other's state or hardware.
class AudioService {
  static const String _defaultOwner = 'default';
  static AudioBackend _backend = _PluginAudioBackend();
  static String? _activeRecordingOwner;
  static String? _activePlaybackOwner;
  static VoidCallback? _onPlaybackInterrupted;
  static int _playbackSeq = 0;
  static Future<void>? _pendingPlaybackStart;

  static bool get isRecording => _activeRecordingOwner != null;

  static bool isPlaybackOwner(String ownerId) =>
      _activePlaybackOwner == ownerId;

  @visibleForTesting
  static set backend(AudioBackend? override) {
    _backend = override ?? _PluginAudioBackend();
    _activeRecordingOwner = null;
    _activePlaybackOwner = null;
    _onPlaybackInterrupted = null;
    _playbackSeq = 0;
    _pendingPlaybackStart = null;
  }

  static void setOnPlaybackComplete(VoidCallback? callback) =>
      _backend.setOnPlaybackComplete(callback);

  static Future<bool> hasMicPermission() => _backend.hasMicPermission();

  static Future<bool> openAppSettings() => _backend.openAppSettings();

  static Future<PickedAudioFile?> pickAudioFile({
    required String destinationBasePath,
  }) => _backend.pickAudioFile(destinationBasePath: destinationBasePath);

  @visibleForTesting
  static RecordConfig recordingConfig({required bool lowCoverage}) {
    if (lowCoverage) {
      return const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 48000,
        sampleRate: 24000,
        numChannels: 1,
      );
    }
    return const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
      numChannels: 1,
    );
  }

  static Future<void> startRecording({
    required String path,
    String ownerId = _defaultOwner,
    bool lowCoverage = false,
  }) async {
    if (_activeRecordingOwner != null && _activeRecordingOwner != ownerId) {
      throw StateError('Another audio field is currently recording.');
    }
    // Notify any active playback owner before recording stops playback.
    if (_activePlaybackOwner != null) {
      final interrupted = _onPlaybackInterrupted;
      _playbackSeq++;
      _activePlaybackOwner = null;
      _onPlaybackInterrupted = null;
      _backend.setOnPlaybackComplete(null);
      interrupted?.call();
    }
    _activeRecordingOwner = ownerId;
    try {
      await _backend.startRecording(path: path, lowCoverage: lowCoverage);
    } catch (_) {
      if (_activeRecordingOwner == ownerId) {
        _activeRecordingOwner = null;
      }
      rethrow;
    }
  }

  static Future<void> pauseRecording({String ownerId = _defaultOwner}) async {
    if (_activeRecordingOwner != ownerId) return;
    await _backend.pauseRecording();
  }

  static Future<void> resumeRecording({String ownerId = _defaultOwner}) async {
    if (_activeRecordingOwner != ownerId) return;
    await _backend.resumeRecording();
  }

  static Future<RecordedAudio?> stopRecording({
    String ownerId = _defaultOwner,
  }) async {
    if (_activeRecordingOwner != ownerId) return null;
    try {
      return await _backend.stopRecording();
    } finally {
      if (_activeRecordingOwner == ownerId) {
        _activeRecordingOwner = null;
      }
    }
  }

  static Future<void> cancelRecording({String ownerId = _defaultOwner}) async {
    if (_activeRecordingOwner != ownerId) return;
    _activeRecordingOwner = null;
    await _backend.cancelRecording();
  }

  static Future<double> getRecordingAmplitude({
    String ownerId = _defaultOwner,
  }) async {
    if (_activeRecordingOwner != ownerId) return 0.0;
    return _backend.getRecordingAmplitude();
  }

  static Future<int?> startPlayback({
    required String path,
    String ownerId = _defaultOwner,
    VoidCallback? onComplete,
    VoidCallback? onInterrupted,
  }) async {
    if (_activeRecordingOwner != null) {
      throw StateError(
        'Finish or discard the active recording before playing audio.',
      );
    }
    if (_activePlaybackOwner != null && _activePlaybackOwner != ownerId) {
      final previousInterrupted = _onPlaybackInterrupted;
      _activePlaybackOwner = null;
      _onPlaybackInterrupted = null;
      _backend.setOnPlaybackComplete(null);
      previousInterrupted?.call();
    }

    final seq = ++_playbackSeq;
    _activePlaybackOwner = ownerId;
    _onPlaybackInterrupted = onInterrupted;

    final priorStart = _pendingPlaybackStart;
    final startCompleter = Completer<void>();
    _pendingPlaybackStart = startCompleter.future;

    try {
      if (priorStart != null) {
        await priorStart.catchError((_) {});
      }
      if (_playbackSeq != seq || _activePlaybackOwner != ownerId) {
        return null;
      }

      _backend.setOnPlaybackComplete(() {
        if (_playbackSeq != seq || _activePlaybackOwner != ownerId) return;
        _activePlaybackOwner = null;
        _onPlaybackInterrupted = null;
        _backend.setOnPlaybackComplete(null);
        onComplete?.call();
      });

      final durationMs = await _backend.startPlayback(path: path);
      if (_playbackSeq != seq || _activePlaybackOwner != ownerId) {
        if (_activePlaybackOwner == null) {
          await _backend.stopPlayback();
        }
        return null;
      }
      return durationMs;
    } catch (_) {
      if (_playbackSeq == seq && _activePlaybackOwner == ownerId) {
        _activePlaybackOwner = null;
        _onPlaybackInterrupted = null;
        _backend.setOnPlaybackComplete(null);
      }
      rethrow;
    } finally {
      if (identical(_pendingPlaybackStart, startCompleter.future)) {
        _pendingPlaybackStart = null;
      }
      if (!startCompleter.isCompleted) {
        startCompleter.complete();
      }
    }
  }

  static Future<void> pausePlayback({String ownerId = _defaultOwner}) async {
    if (_activePlaybackOwner != ownerId) return;
    await _backend.pausePlayback();
  }

  static Future<void> resumePlayback({String ownerId = _defaultOwner}) async {
    if (_activePlaybackOwner != ownerId) return;
    await _backend.resumePlayback();
  }

  static Future<void> stopPlayback({String ownerId = _defaultOwner}) async {
    if (_activePlaybackOwner != ownerId) return;
    _playbackSeq++;
    _activePlaybackOwner = null;
    _onPlaybackInterrupted = null;
    _backend.setOnPlaybackComplete(null);
    await _backend.stopPlayback();
  }

  static Future<void> stopActivePlayback() async {
    if (_activePlaybackOwner == null) return;
    final interrupted = _onPlaybackInterrupted;
    _playbackSeq++;
    _activePlaybackOwner = null;
    _onPlaybackInterrupted = null;
    _backend.setOnPlaybackComplete(null);
    interrupted?.call();
    await _backend.stopPlayback();
  }

  static Future<PlaybackStatus> getPlaybackStatus({
    String ownerId = _defaultOwner,
  }) async {
    if (_activePlaybackOwner != ownerId) {
      return const PlaybackStatus(
        isPlaying: false,
        positionMs: 0,
        durationMs: 0,
      );
    }
    return _backend.getPlaybackStatus();
  }
}
