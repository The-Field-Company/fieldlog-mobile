import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import '../utils/attachment_accepts.dart';
import 'location_service.dart';

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
  Future<void> startRecording({required String path});
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
  StreamSubscription<void>? _completeSub;
  VoidCallback? _onPlaybackComplete;
  String? _recordingPath;
  DateTime? _recordingSegmentStartedAt;
  Duration _recordingAccumulated = Duration.zero;

  AudioRecorder get _audioRecorder => _recorder ??= AudioRecorder();

  AudioPlayer get _audioPlayer {
    if (_player != null) return _player!;
    final player = AudioPlayer();
    _completeSub = player.onPlayerComplete.listen((_) {
      _onPlaybackComplete?.call();
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
    final finalPath = ext.isNotEmpty
        ? '$destinationBasePath.$ext'
        : destinationBasePath;

    final saved = await File(sourcePath).copy(finalPath);
    final size = await saved.length();

    return PickedAudioFile(
      path: saved.path,
      name: picked.name.isNotEmpty ? picked.name : saved.path.split('/').last,
      size: size,
    );
  }

  @override
  Future<void> startRecording({required String path}) async {
    await stopPlayback();
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
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

    final stoppedPath = await _audioRecorder.stop() ?? fallbackPath;
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
    await player.play(DeviceFileSource(path));
    final duration = await player.getDuration();
    return duration?.inMilliseconds ?? 0;
  }

  @override
  Future<void> pausePlayback() async {
    await _player?.pause();
  }

  @override
  Future<void> resumePlayback() async {
    await _player?.resume();
  }

  @override
  Future<void> stopPlayback() async {
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
      return PlaybackStatus(
        isPlaying: player.state == PlayerState.playing,
        positionMs: pos?.inMilliseconds ?? 0,
        durationMs: dur?.inMilliseconds ?? 0,
      );
    } catch (_) {
      return const PlaybackStatus(
        isPlaying: false,
        positionMs: 0,
        durationMs: 0,
      );
    }
  }

  // Keep reference so the subscription stays active while player lives.
  // ignore: unused_element
  Future<void> dispose() async {
    await _completeSub?.cancel();
    await _player?.dispose();
    await _recorder?.dispose();
  }
}

/// Wrapper around `file_picker`, `record`, and `audioplayers` for audio field
/// selection, in-app AAC `.m4a` recording, and playback preview.
class AudioService {
  static AudioBackend _backend = _PluginAudioBackend();

  @visibleForTesting
  static set backend(AudioBackend? override) {
    _backend = override ?? _PluginAudioBackend();
  }

  static void setOnPlaybackComplete(VoidCallback? callback) =>
      _backend.setOnPlaybackComplete(callback);

  static Future<bool> hasMicPermission() => _backend.hasMicPermission();

  static Future<bool> openAppSettings() => _backend.openAppSettings();

  static Future<PickedAudioFile?> pickAudioFile({
    required String destinationBasePath,
  }) => _backend.pickAudioFile(destinationBasePath: destinationBasePath);

  static Future<void> startRecording({required String path}) =>
      _backend.startRecording(path: path);

  static Future<void> pauseRecording() => _backend.pauseRecording();

  static Future<void> resumeRecording() => _backend.resumeRecording();

  static Future<RecordedAudio?> stopRecording() => _backend.stopRecording();

  static Future<void> cancelRecording() => _backend.cancelRecording();

  static Future<double> getRecordingAmplitude() =>
      _backend.getRecordingAmplitude();

  static Future<int> startPlayback({required String path}) =>
      _backend.startPlayback(path: path);

  static Future<void> pausePlayback() => _backend.pausePlayback();

  static Future<void> resumePlayback() => _backend.resumePlayback();

  static Future<void> stopPlayback() => _backend.stopPlayback();

  static Future<PlaybackStatus> getPlaybackStatus() =>
      _backend.getPlaybackStatus();
}
